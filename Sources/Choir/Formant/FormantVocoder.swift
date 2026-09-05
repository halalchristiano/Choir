import Foundation

/// A two-pole resonator with unity gain at DC.
///
/// This is the standard digital formant filter: one complex pole pair placed
/// at the formant frequency, with the pole radius set by the bandwidth.
struct FormantResonator {
    private var y1 = 0.0
    private var y2 = 0.0
    private var a = 1.0
    private var b = 0.0
    private var c = 0.0

    mutating func tune(frequency: Double, bandwidth: Double, sampleRate: Double) {
        // Keep the pole inside the unit circle and below Nyquist, whatever the
        // caller asked for; an out-of-range formant would make the filter blow up.
        let nyquist = sampleRate / 2
        let frequency = min(max(frequency, 30), nyquist - 100)
        let bandwidth = min(max(bandwidth, 20), 2_000)

        let radius = exp(-Double.pi * bandwidth / sampleRate)
        c = -radius * radius
        b = 2 * radius * cos(2 * Double.pi * frequency / sampleRate)
        a = 1 - b - c
    }

    mutating func process(_ input: Double) -> Double {
        let output = a * input + b * y1 + c * y2
        y2 = y1
        y1 = output
        return output
    }
}

/// A two-pole band-pass, used for the turbulence of fricatives and bursts.
///
/// Frication is generated at a constriction near the front of the vocal tract,
/// so unlike voicing it is not shaped by the whole formant cascade. It gets its
/// own filter and is summed in afterwards.
struct NoiseBandPass {
    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0
    private var a = 0.0
    private var b = 0.0
    private var c = 0.0

    mutating func tune(frequency: Double, bandwidth: Double, sampleRate: Double) {
        let nyquist = sampleRate / 2
        let frequency = min(max(frequency, 100), nyquist - 200)
        let bandwidth = min(max(bandwidth, 100), 6_000)

        let radius = exp(-Double.pi * bandwidth / sampleRate)
        c = -radius * radius
        b = 2 * radius * cos(2 * Double.pi * frequency / sampleRate)
        a = (1 - radius * radius) / 2
    }

    mutating func process(_ input: Double) -> Double {
        let output = a * (input - x2) + b * y1 + c * y2
        x2 = x1
        x1 = input
        y2 = y1
        y1 = output
        return output
    }
}

/// Renders the ``FormantChannel`` control track produced by
/// ``FormantAcousticModel`` into PCM.
///
/// The signal chain is the classic source-filter model:
///
/// 1. A Rosenberg glottal pulse at the frame's F0, plus aspiration noise.
/// 2. A spectral-tilt filter, which carries much of the speaker's character.
/// 3. Three formant resonators in cascade, which shape the vowel identity.
/// 4. Frication noise through its own band-pass, summed in.
/// 5. A first difference, modelling radiation from the lips.
///
/// Output is deterministic: the noise sources run from ``SeededGenerator`` with
/// a fixed seed, so the same feature track always renders to the same samples.
/// SYN-002 requires that, and the pipeline relies on it because batch and
/// progressive delivery render the same units through this same call.
public struct FormantVocoder: VocoderProtocol {

    /// Output scaling applied after radiation, before conversion to 16-bit.
    ///
    /// The chain's natural peak is small — the radiation difference attenuates
    /// everything below Nyquist — so this brings a normal utterance to roughly
    /// half of full scale, leaving headroom for the louder vowels.
    public let gain: Double

    /// Seed for the noise sources. Fixed by default so that rendering is
    /// reproducible; exposed so that tests can show it actually matters.
    public let seed: UInt64

    /// Level of the frication path relative to voicing.
    ///
    /// Turbulence enters after the formant cascade, so it is not subject to the
    /// same attenuation as the voiced source and needs scaling to sit where it
    /// belongs. Measured against a sustained vowel, an /s/ should land roughly
    /// 12 dB down; unscaled it comes out about 11 dB up, loud enough to mask
    /// the vowels entirely.
    static let fricationScale = 0.07

    /// Level of the aspiration path, which passes through the cascade with the
    /// voiced source and so needs much less correction.
    static let aspirationScale = 1.0

    public init(gain: Double = 2.5, seed: UInt64 = 0x43_48_4F_49_52) {
        self.gain = max(0, gain)
        self.seed = seed
    }

    public func synthesize(features: AcousticFeatures, sampleRate: Int) async throws -> [Int16] {
        guard features.frameCount > 0, features.isRectangular,
              features.frequencyBins >= FormantChannel.channelCount else {
            throw ChoirError.synthesisError(
                reason: "Formant vocoder requires a \(FormantChannel.channelCount)-channel "
                    + "control track from FormantAcousticModel")
        }
        guard features.containsOnlyFiniteValues else {
            throw ChoirError.synthesisError(
                reason: "Formant vocoder received a non-finite control track")
        }
        guard sampleRate >= 8_000, sampleRate <= 384_000 else {
            throw ChoirError.invalidParameter(
                parameter: "sampleRate", reason: "Sample rate must be within 8,000...384,000 Hz")
        }
        guard features.frameRate > 0 else {
            throw ChoirError.invalidParameter(
                parameter: "features", reason: "Frame rate must be positive")
        }

        let rate = Double(sampleRate)
        let sampleCount = Int(
            (Double(features.frameCount) / Double(features.frameRate) * rate).rounded())
        guard sampleCount > 0 else {
            throw ChoirError.synthesisError(reason: "Formant vocoder produced no samples")
        }

        var generator = SeededGenerator(seed: seed)
        var f1 = FormantResonator()
        var f2 = FormantResonator()
        var f3 = FormantResonator()
        var frication = NoiseBandPass()

        // Glottal cycle state. `phase` runs 0..<1 over one pitch period.
        var phase = 0.0
        var periodJitter = 1.0
        var periodShimmer = 1.0
        // Radiation is a first difference, so it needs the previous sample.
        var previousTractOutput = 0.0
        // One-pole state for the spectral-tilt filter.
        var tiltState = 0.0

        var samples = [Int16]()
        samples.reserveCapacity(sampleCount)

        let framesPerSample = Double(features.frameRate) / rate

        for index in 0..<sampleCount {
            let frame = Self.interpolatedFrame(
                at: Double(index) * framesPerSample, features: features)

            f1.tune(frequency: frame.f1, bandwidth: frame.b1, sampleRate: rate)
            f2.tune(frequency: frame.f2, bandwidth: frame.b2, sampleRate: rate)
            f3.tune(frequency: frame.f3, bandwidth: frame.b3, sampleRate: rate)

            // MARK: Source
            var source = 0.0
            if frame.f0 > 20, frame.voicing > 0 {
                let period = rate / (frame.f0 * periodJitter)
                phase += 1.0 / max(1, period)
                if phase >= 1 {
                    phase -= 1
                    // Jitter and shimmer are re-drawn once per cycle, which is
                    // what makes roughness read as a voice quality rather than
                    // as broadband noise.
                    let amount = min(1, max(0, frame.roughness))
                    periodJitter = 1 + generator.jitter(magnitude: 0.04 * amount)
                    periodShimmer = 1 + generator.jitter(magnitude: 0.15 * amount)
                }
                source = Self.glottalFlow(phase: phase) * frame.voicing * periodShimmer
            } else {
                phase = 0
            }

            if frame.aspiration > 0 {
                // Aspiration is generated at the glottis, so it goes through
                // the formant cascade with the voiced source.
                source += generator.jitter(magnitude: 1.0) * frame.aspiration
                    * Self.aspirationScale
            }

            // MARK: Spectral tilt
            let cutoff = Self.tiltCutoff(dBPerOctave: frame.spectralTilt)
            let alpha = 1 - exp(-2 * Double.pi * cutoff / rate)
            tiltState += alpha * (source - tiltState)

            // MARK: Vocal tract
            var tract = f3.process(f2.process(f1.process(tiltState)))

            if frame.frication > 0 {
                frication.tune(
                    frequency: frame.noiseFrequency, bandwidth: frame.noiseBandwidth,
                    sampleRate: rate)
                tract += frication.process(generator.jitter(magnitude: 1.0))
                    * frame.frication * Self.fricationScale
            }

            // MARK: Radiation
            let radiated = tract - previousTractOutput
            previousTractOutput = tract

            let scaled = radiated * gain
            // Clamp rather than wrap: an overdriven vowel should distort, not
            // invert its waveform.
            let limited = min(1.0, max(-1.0, scaled))
            samples.append(Int16(limited * 32_767))
        }

        return samples
    }

    // MARK: - Helpers

    /// One frame's worth of control values, already interpolated.
    struct Frame {
        var f0 = 0.0
        var voicing = 0.0
        var aspiration = 0.0
        var frication = 0.0
        var f1 = 500.0
        var b1 = 60.0
        var f2 = 1_500.0
        var b2 = 90.0
        var f3 = 2_500.0
        var b3 = 150.0
        var noiseFrequency = 3_000.0
        var noiseBandwidth = 1_000.0
        var spectralTilt = -12.0
        var roughness = 0.0
    }

    /// Linearly interpolates the control track between frames.
    ///
    /// Formants must move continuously; stepping them at the frame rate would
    /// add an audible buzz at 200 Hz and smear the transitions that carry
    /// place of articulation.
    static func interpolatedFrame(at position: Double, features: AcousticFeatures) -> Frame {
        let lastIndex = features.frameCount - 1
        let lower = min(lastIndex, max(0, Int(position)))
        let upper = min(lastIndex, lower + 1)
        let fraction = min(1, max(0, position - Double(lower)))

        let a = features.features[lower]
        let b = features.features[upper]

        func value(_ channel: FormantChannel) -> Double {
            let low = Double(a[channel.rawValue])
            let high = Double(b[channel.rawValue])
            return low + (high - low) * fraction
        }

        var frame = Frame()
        frame.f0 = value(.f0)
        frame.voicing = value(.voicingAmplitude)
        frame.aspiration = value(.aspirationAmplitude)
        frame.frication = value(.fricationAmplitude)
        frame.f1 = value(.f1)
        frame.b1 = value(.b1)
        frame.f2 = value(.f2)
        frame.b2 = value(.b2)
        frame.f3 = value(.f3)
        frame.b3 = value(.b3)
        frame.noiseFrequency = value(.noiseFrequency)
        frame.noiseBandwidth = value(.noiseBandwidth)
        frame.spectralTilt = value(.spectralTilt)
        frame.roughness = value(.roughness)
        return frame
    }

    /// The Rosenberg glottal flow pulse over one normalized period.
    ///
    /// The asymmetry matters: the glottis opens gradually and closes abruptly,
    /// and it is that sharp closure which supplies the harmonic energy the
    /// formants resonate. A symmetric pulse sounds like a hum, not a voice.
    static func glottalFlow(phase: Double) -> Double {
        let openFraction = 0.40
        let closeFraction = 0.16

        if phase < openFraction {
            return 0.5 * (1 - cos(Double.pi * phase / openFraction))
        }
        if phase < openFraction + closeFraction {
            return cos(Double.pi * (phase - openFraction) / (2 * closeFraction))
        }
        return 0
    }

    /// Maps a spectral tilt in dB per octave onto a one-pole cutoff.
    ///
    /// -6 dB/octave is a bright voice and -18 a dark one; the mapping keeps
    /// those at 4 kHz and 1 kHz respectively.
    static func tiltCutoff(dBPerOctave: Double) -> Double {
        guard dBPerOctave.isFinite else { return 2_000 }
        let tilt = min(-3.0, max(-24.0, dBPerOctave))
        return min(8_000, max(400, 4_000 * pow(2, (tilt + 6) / 6)))
    }
}
