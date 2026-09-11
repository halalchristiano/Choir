import Foundation

/// The channel layout shared by ``FormantAcousticModel`` and
/// ``FormantVocoder``.
///
/// ``AcousticFeatures`` is documented as "Mel-spectrogram or similar". The
/// formant path uses that same container for a control-parameter track rather
/// than a spectrogram, so the two ends must agree on what each column means.
/// This enum is that agreement; nothing else in the package interprets these
/// columns.
public enum FormantChannel: Int, Sendable, CaseIterable {
    /// Fundamental frequency in Hz. Zero means the frame is unvoiced.
    case f0 = 0
    /// Amplitude of the voiced source, 0...1.
    case voicingAmplitude = 1
    /// Amplitude of the aspiration noise, 0...1.
    case aspirationAmplitude = 2
    /// Amplitude of the frication noise, 0...1.
    case fricationAmplitude = 3
    case f1 = 4
    case b1 = 5
    case f2 = 6
    case b2 = 7
    case f3 = 8
    case b3 = 9
    /// Centre frequency of the frication resonator in Hz.
    case noiseFrequency = 10
    /// Bandwidth of the frication resonator in Hz.
    case noiseBandwidth = 11
    /// Spectral tilt of the voiced source in dB per octave. More negative is
    /// darker; this is a large part of what separates one speaker from another.
    case spectralTilt = 12
    /// Cycle-to-cycle pitch jitter, 0...1, which reads as vocal roughness.
    case roughness = 13

    public static let channelCount = FormantChannel.allCases.count
}

/// A rule-based acoustic model that needs no trained weights.
///
/// The model converts the linguistic front end's phoneme, duration and pitch
/// output into the formant control track described by ``FormantChannel``.
/// Paired with ``FormantVocoder`` it gives the package an audible,
/// data-free synthesis path, which the default mock models do not: a mock
/// returns a fixed test tone, so nothing downstream is ever exercised against
/// real speech structure.
///
/// The result is intelligible and clearly synthetic, in the tradition of the
/// formant synthesizers that preceded concatenative and neural systems. It is
/// a working baseline and a reference implementation of the model interface,
/// not a replacement for the trained models the SRS requires.
public struct FormantAcousticModel: AcousticModelProtocol {

    /// Frames per second of the control track. 200 gives 5 ms resolution,
    /// which is fine enough that formant transitions do not step audibly.
    public let frameRate: Int

    /// Overrides the vocal-tract scaling that would otherwise come from the
    /// voice profile. Used by tests that need a fixed reference speaker.
    private let formantScaleOverride: Double?

    public init(frameRate: Int = 200, formantScaleOverride: Double? = nil) {
        self.frameRate = min(1_000, max(50, frameRate))
        self.formantScaleOverride = formantScaleOverride
    }

    public func predict(input: AcousticModelInput) async throws -> AcousticFeatures {
        try input.validate()

        let plan = Self.plan(for: input)
        let scale = formantScaleOverride ?? Self.formantScale(for: input)
        let voice = Voice.allCases.first { $0.conditioningID == input.voiceID }
        let tilt = voice?.profile.spectralTilt ?? -12.0
        let roughness = voice?.profile.roughness ?? 0.0

        let totalMs = plan.reduce(0) { $0 + $1.durationMs }
        // Guarantee a non-empty rectangular tensor even for a degenerate
        // request: the feature contract requires at least one frame.
        let frameCount = max(1, Int((totalMs / 1_000.0 * Double(frameRate)).rounded()))

        let anchors = Self.formantAnchors(plan: plan, totalMs: totalMs, scale: scale)
        var frames: [[Float]] = []
        frames.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            let timeMs = Double(frameIndex) / Double(frameRate) * 1_000.0
            let target = Self.formants(at: timeMs, anchors: anchors, scale: scale)
            let segment = Self.segment(at: timeMs, plan: plan)
            let source = Self.source(at: timeMs, segment: segment, input: input)

            var frame = [Float](repeating: 0, count: FormantChannel.channelCount)
            frame[FormantChannel.f0.rawValue] = Float(source.f0)
            frame[FormantChannel.voicingAmplitude.rawValue] = Float(source.voicing)
            frame[FormantChannel.aspirationAmplitude.rawValue] = Float(source.aspiration)
            frame[FormantChannel.fricationAmplitude.rawValue] = Float(source.frication)
            frame[FormantChannel.f1.rawValue] = Float(target.f1)
            frame[FormantChannel.b1.rawValue] = Float(target.b1)
            frame[FormantChannel.f2.rawValue] = Float(target.f2)
            frame[FormantChannel.b2.rawValue] = Float(target.b2)
            frame[FormantChannel.f3.rawValue] = Float(target.f3)
            frame[FormantChannel.b3.rawValue] = Float(target.b3)
            frame[FormantChannel.noiseFrequency.rawValue] = Float(source.noiseFrequency)
            frame[FormantChannel.noiseBandwidth.rawValue] = Float(source.noiseBandwidth)
            frame[FormantChannel.spectralTilt.rawValue] = Float(tilt)
            frame[FormantChannel.roughness.rawValue] = Float(roughness)
            frames.append(frame)
        }

        return AcousticFeatures(features: frames, frameRate: frameRate)
    }

    // MARK: - Segment plan

    /// One phoneme placed on the utterance timeline.
    struct Segment: Sendable {
        let definition: FormantDefinition
        let startMs: Double
        let durationMs: Double
        let f0: Double
        let energy: Double
        var endMs: Double { startMs + durationMs }
    }

    /// Pairs each phoneme index with its duration, pitch and energy.
    static func plan(for input: AcousticModelInput) -> [Segment] {
        var segments: [Segment] = []
        segments.reserveCapacity(input.phonemeIndices.count)
        var cursor = 0.0

        for (position, index) in input.phonemeIndices.enumerated() {
            let definition = FormantTable.definition(forIndex: index) ?? FormantTable.silence
            // The front end guarantees parallel arrays, but a caller-built
            // input only has to satisfy validate(); fall back rather than trap.
            let duration = position < input.durations.count ? input.durations[position] : 80
            let f0 = position < input.fundamentalFrequency.count
                ? input.fundamentalFrequency[position] : 120
            let energy = position < input.energy.count ? input.energy[position] : -23

            segments.append(Segment(
                definition: definition,
                startMs: cursor,
                durationMs: max(1, duration),
                f0: f0,
                energy: energy))
            cursor += max(1, duration)
        }
        return segments
    }

    /// The segment covering a point in time, or the nearest one.
    static func segment(at timeMs: Double, plan: [Segment]) -> Segment? {
        guard !plan.isEmpty else { return nil }
        for segment in plan where timeMs >= segment.startMs && timeMs < segment.endMs {
            return segment
        }
        return timeMs < plan[0].startMs ? plan[0] : plan[plan.count - 1]
    }

    // MARK: - Formant trajectory

    /// A formant target pinned to a moment in the utterance.
    struct Anchor: Sendable {
        let timeMs: Double
        let target: FormantTarget
    }

    /// Places one anchor at the centre of each phoneme — two for a diphthong —
    /// and interpolates between them.
    ///
    /// Anchoring at centres rather than at boundaries is what produces
    /// coarticulation: the trajectory is already moving toward the next
    /// phoneme's target while the current one is still sounding, so a stop's
    /// formant locus bends the neighbouring vowel the way a real transition
    /// does. That bend is the primary cue to place of articulation.
    static func formantAnchors(
        plan: [Segment], totalMs: Double, scale: Double
    ) -> [Anchor] {
        var anchors: [Anchor] = []

        for segment in plan {
            let definition = segment.definition
            // /h/ is aspiration shaped by its neighbours, so it contributes no
            // target of its own; the trajectory glides straight through it.
            // Silence likewise holds the previous position rather than
            // yanking the formants back to neutral.
            if definition.manner == .aspirate || definition.manner == .silence {
                continue
            }

            if let glide = definition.glideTarget {
                // A diphthong is two targets inside one segment.
                anchors.append(Anchor(
                    timeMs: segment.startMs + segment.durationMs * 0.25,
                    target: definition.target.scaled(by: scale)))
                anchors.append(Anchor(
                    timeMs: segment.startMs + segment.durationMs * 0.85,
                    target: glide.scaled(by: scale)))
            } else {
                anchors.append(Anchor(
                    timeMs: segment.startMs + segment.durationMs * 0.5,
                    target: definition.target.scaled(by: scale)))
            }
        }

        if anchors.isEmpty {
            anchors.append(Anchor(timeMs: 0, target: FormantTable.neutral.scaled(by: scale)))
            anchors.append(Anchor(
                timeMs: max(1, totalMs), target: FormantTable.neutral.scaled(by: scale)))
        }
        return anchors
    }

    /// Linear interpolation along the anchor track, holding the endpoints.
    static func formants(at timeMs: Double, anchors: [Anchor], scale: Double) -> FormantTarget {
        guard let first = anchors.first, let last = anchors.last else {
            return FormantTable.neutral.scaled(by: scale)
        }
        if timeMs <= first.timeMs { return first.target }
        if timeMs >= last.timeMs { return last.target }

        for pair in 0..<(anchors.count - 1) {
            let left = anchors[pair]
            let right = anchors[pair + 1]
            guard timeMs >= left.timeMs, timeMs <= right.timeMs else { continue }
            let span = right.timeMs - left.timeMs
            guard span > 0 else { return right.target }
            return left.target.interpolated(
                towards: right.target, fraction: (timeMs - left.timeMs) / span)
        }
        return last.target
    }

    // MARK: - Source parameters

    /// The excitation for one frame.
    struct Source: Sendable {
        var f0: Double = 0
        var voicing: Double = 0
        var aspiration: Double = 0
        var frication: Double = 0
        var noiseFrequency: Double = 0
        var noiseBandwidth: Double = 1_000
    }

    /// Duration of a stop burst. Long enough to be heard as a transient,
    /// short enough not to read as a fricative.
    static let burstMs = 12.0

    static func source(
        at timeMs: Double, segment: Segment?, input: AcousticModelInput
    ) -> Source {
        guard let segment else { return Source() }
        let definition = segment.definition
        let position = segment.durationMs > 0
            ? (timeMs - segment.startMs) / segment.durationMs : 0

        var source = Source()
        source.noiseFrequency = definition.noiseFrequency
        source.noiseBandwidth = definition.noiseBandwidth

        // Energy arrives in LUFS. Map the useful part of that range onto a
        // linear gain so that stressed syllables stay louder than unstressed
        // ones without the quiet ones vanishing.
        let loudness = Self.gain(fromLUFS: segment.energy)
        let amplitude = definition.amplitude * loudness
        // Breathiness trades voiced energy for aspiration noise.
        let breath = min(1, max(0, input.breathiness))

        switch definition.manner {
        case .vowel, .nasal, .approximant:
            source.f0 = segment.f0
            source.voicing = amplitude * (1 - 0.45 * breath)
            source.aspiration = amplitude * 0.35 * breath
            source.noiseFrequency = 1_800
            source.noiseBandwidth = 2_500

        case .voicedFricative:
            source.f0 = segment.f0
            source.voicing = amplitude * 0.55
            source.frication = amplitude

        case .fricative:
            source.frication = amplitude

        case .aspirate:
            source.aspiration = amplitude

        case .stop, .voicedStop:
            // Closure, then burst, then a short aspiration tail for the
            // voiceless stops. The closure is what makes a stop audible as a
            // stop: without the silence it reads as a weak fricative.
            let burstStart = max(0, segment.durationMs - Self.burstMs)
            let intoSegment = timeMs - segment.startMs
            if intoSegment < burstStart {
                if definition.manner == .voicedStop {
                    // A voice bar: low-frequency voicing during the closure.
                    source.f0 = segment.f0
                    source.voicing = amplitude * 0.12
                }
            } else {
                source.frication = amplitude
                if definition.manner == .stop {
                    source.aspiration = amplitude * 0.5
                } else {
                    source.f0 = segment.f0
                    source.voicing = amplitude * 0.3
                }
            }

        case .affricate, .voicedAffricate:
            // Like a stop, but the release is a sustained fricative rather
            // than a transient burst.
            if position < 0.4 {
                if definition.manner == .voicedAffricate {
                    source.f0 = segment.f0
                    source.voicing = amplitude * 0.12
                }
            } else {
                source.frication = amplitude
                if definition.manner == .voicedAffricate {
                    source.f0 = segment.f0
                    source.voicing = amplitude * 0.4
                }
            }

        case .silence:
            break
        }

        // Taper the very edges of a voiced segment so that joins do not click.
        if source.voicing > 0 {
            let edgeMs = min(8.0, segment.durationMs * 0.25)
            if edgeMs > 0 {
                let intoSegment = timeMs - segment.startMs
                let fromEnd = segment.endMs - timeMs
                let rise = min(1, max(0, intoSegment / edgeMs))
                let fall = min(1, max(0, fromEnd / edgeMs))
                source.voicing *= min(rise, fall)
            }
        }

        return source
    }

    /// Maps LUFS onto a linear gain over the range the prosody predictor uses.
    static func gain(fromLUFS lufs: Double) -> Double {
        guard lufs.isFinite else { return 0.8 }
        let clamped = min(-6.0, max(-40.0, lufs))
        // -40 LUFS maps to 0.35, -6 maps to 1.0.
        return 0.35 + (clamped + 40.0) / 34.0 * 0.65
    }

    // MARK: - Voice conditioning

    /// Vocal-tract scaling for the requested voice.
    ///
    /// This is what makes the 32 profiles audibly different rather than 32
    /// labels on one voice: the profile's formant scale moves every resonance,
    /// which is the perceptual cue for speaker size. Age and gender shifts
    /// then apply on top of it.
    static func formantScale(for input: AcousticModelInput) -> Double {
        var scale = 1.0
        if let voice = Voice.allCases.first(where: { $0.conditioningID == input.voiceID }) {
            scale = voice.profile.formantScale
        }
        // A more feminine or younger setting shortens the tract, raising every
        // formant; the opposite lengthens it.
        scale *= 1.0 + 0.12 * min(1, max(-1, input.genderShift))
        scale *= 1.0 - 0.10 * min(1, max(-1, input.ageShift))
        return min(2.0, max(0.5, scale))
    }
}
