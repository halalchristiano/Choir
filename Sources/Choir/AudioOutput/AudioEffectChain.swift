import Foundation

/// Effect configuration for the chain.
public struct AudioEffect: Sendable, Equatable {
    /// Effect type and parameters.
    public enum Kind: Sendable, Equatable {
        case highPass(cutoffHz: Double)
        case lowPass(cutoffHz: Double)
        case normalize(targetLevel: Double)
        case compress(threshold: Double, ratio: Double)
        case deEsser(centerHz: Double)
        case softClip(threshold: Double)
        case removeDCOffset
        case edgeFade(durationMilliseconds: Double)
        case softKneeLimiter(ceilingDB: Double, kneeWidthDB: Double)
        case reverb(wetLevel: Double)

        /// Validates effect parameters against the processing sample rate.
        public func validate(sampleRate: Int) throws {
            guard 8_000...384_000 ~= sampleRate else {
                throw ChoirError.invalidParameter(
                    parameter: "sampleRate",
                    reason: "Effect sample rate must be within 8,000...384,000 Hz")
            }
            let nyquist = Double(sampleRate) / 2
            switch self {
            case .highPass(let cutoff), .lowPass(let cutoff):
                guard cutoff.isFinite, cutoff > 0, cutoff < nyquist else {
                    throw ChoirError.invalidParameter(
                        parameter: "cutoffHz",
                        reason: "Filter cutoff must be finite and below the Nyquist frequency")
                }
            case .normalize(let target):
                guard target.isFinite, -20...0 ~= target else {
                    throw ChoirError.invalidParameter(
                        parameter: "targetLevel",
                        reason: "Normalization target must be within -20...0 dB")
                }
            case .compress(let threshold, let ratio):
                guard threshold.isFinite, -120...0 ~= threshold else {
                    throw ChoirError.invalidParameter(
                        parameter: "threshold",
                        reason: "Compression threshold must be within -120...0 dB")
                }
                guard ratio.isFinite, 1...100 ~= ratio else {
                    throw ChoirError.invalidParameter(
                        parameter: "ratio",
                        reason: "Compression ratio must be within 1...100")
                }
            case .deEsser(let center):
                guard center.isFinite, center > 0, center < nyquist else {
                    throw ChoirError.invalidParameter(
                        parameter: "centerHz",
                        reason: "De-esser center must be finite and below the Nyquist frequency")
                }
            case .softClip(let threshold):
                guard threshold.isFinite, threshold > 0, threshold <= 1 else {
                    throw ChoirError.invalidParameter(
                        parameter: "threshold",
                        reason: "Soft-clip threshold must be within (0, 1]")
                }
            case .removeDCOffset:
                break
            case .edgeFade(let duration):
                guard duration.isFinite, 0...5 ~= duration else {
                    throw ChoirError.invalidParameter(
                        parameter: "durationMilliseconds",
                        reason: "Edge-fade duration must be within 0...5 ms")
                }
            case .softKneeLimiter(let ceiling, let knee):
                guard ceiling.isFinite, -24...0 ~= ceiling else {
                    throw ChoirError.invalidParameter(
                        parameter: "ceilingDB",
                        reason: "Limiter ceiling must be within -24...0 dBFS")
                }
                guard knee.isFinite, 0...24 ~= knee else {
                    throw ChoirError.invalidParameter(
                        parameter: "kneeWidthDB",
                        reason: "Limiter knee width must be within 0...24 dB")
                }
            case .reverb(let wetLevel):
                guard wetLevel.isFinite, 0...1 ~= wetLevel else {
                    throw ChoirError.invalidParameter(
                        parameter: "wetLevel",
                        reason: "Reverb wet level must be within 0...1")
                }
            }
        }
    }

    public let name: String
    public let kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    /// Validates the display name and the effect's signal-processing parameters.
    public func validate(sampleRate: Int) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "name", reason: "Effect name must not be empty")
        }
        try kind.validate(sampleRate: sampleRate)
    }
}

/// Chains multiple audio effects for processing.
///
/// Allows building complex audio processing pipelines by composing filters.
public struct AudioEffectChain: Sendable {
    private let effects: [AudioEffect]
    private let filters = AudioFilters()
    private let sampleRate: Int

    public init(sampleRate: Int = 48000) {
        self.effects = []
        self.sampleRate = sampleRate
    }

    private init(effects: [AudioEffect], sampleRate: Int) {
        self.effects = effects
        self.sampleRate = sampleRate
    }

    /// Number of effects that will run.
    public var effectCount: Int { effects.count }

    /// Whether processing is a no-op because the chain has no effects.
    public var isEmpty: Bool { effects.isEmpty }

    /// Effect names in processing order.
    public var effectNames: [String] { effects.map(\.name) }

    /// Sample rate supplied to frequency-dependent effects.
    public var sampleRateHz: Int { sampleRate }

    /// Adds an effect to the chain.
    public func add(_ effect: AudioEffect) -> AudioEffectChain {
        var newEffects = effects
        newEffects.append(effect)
        return AudioEffectChain(effects: newEffects, sampleRate: sampleRate)
    }

    /// Adds multiple effects.
    public func add(_ effects: [AudioEffect]) -> AudioEffectChain {
        var newEffects = self.effects
        newEffects.append(contentsOf: effects)
        return AudioEffectChain(effects: newEffects, sampleRate: sampleRate)
    }

    /// Processes audio through all effects in order.
    public func process(_ samples: [Int16]) -> [Int16] {
        var processed = samples

        for effect in effects {
            processed = processWithEffect(processed, effect: effect)
        }

        return processed
    }

    /// Validates the chain's sample rate and every configured effect.
    public func validate() throws {
        guard 8_000...384_000 ~= sampleRate else {
            throw ChoirError.invalidParameter(
                parameter: "sampleRate",
                reason: "Effect-chain sample rate must be within 8,000...384,000 Hz")
        }
        for effect in effects {
            try effect.validate(sampleRate: sampleRate)
        }
    }

    /// Processes a validated buffer while preserving its PCM format metadata.
    public func process(_ buffer: AudioBuffer) throws -> AudioBuffer {
        try buffer.validate()
        try validate()
        guard buffer.format.sampleRate == sampleRate else {
            throw ChoirError.invalidParameter(
                parameter: "buffer",
                reason: "Buffer and effect-chain sample rates must match")
        }
        guard buffer.format.channels > 1 else {
            return AudioBuffer(samples: process(buffer.samples), format: buffer.format)
        }

        // Stateful filters must never carry their previous sample from one
        // interleaved channel into the next. Process each channel as its own
        // signal, then restore the original interleaving.
        let channelCount = buffer.format.channels
        var channels = Array(repeating: [Int16](), count: channelCount)
        for channel in channels.indices {
            channels[channel].reserveCapacity(buffer.frameCount)
        }
        for frame in 0..<buffer.frameCount {
            for channel in channels.indices {
                channels[channel].append(buffer.samples[frame * channelCount + channel])
            }
        }
        let processedChannels = channels.map { process($0) }
        var interleaved: [Int16] = []
        interleaved.reserveCapacity(buffer.samples.count)
        for frame in 0..<buffer.frameCount {
            for channel in processedChannels.indices {
                interleaved.append(processedChannels[channel][frame])
            }
        }
        return AudioBuffer(samples: interleaved, format: buffer.format)
    }

    /// Processes audio with a single effect.
    private func processWithEffect(_ samples: [Int16], effect: AudioEffect) -> [Int16] {
        switch effect.kind {
        case .highPass(let cutoff):
            return filters.highPassFilter(samples, cutoffFrequency: cutoff, sampleRate: sampleRate)

        case .lowPass(let cutoff):
            return filters.lowPassFilter(samples, cutoffFrequency: cutoff, sampleRate: sampleRate)

        case .normalize(let target):
            return filters.normalize(samples, targetLevel: target)

        case .compress(let threshold, let ratio):
            return filters.compress(samples, threshold: threshold, ratio: ratio)

        case .deEsser(let center):
            return filters.deEsser(samples, sibilantFrequency: center, sampleRate: sampleRate)

        case .softClip(let threshold):
            return filters.softClip(samples, threshold: threshold)

        case .removeDCOffset:
            return filters.removeDCOffset(samples)

        case .edgeFade(let duration):
            return filters.fadeEdges(
                samples, durationMilliseconds: duration, sampleRate: sampleRate)

        case .softKneeLimiter(let ceiling, let knee):
            return filters.softKneeLimiter(
                samples, ceilingDB: ceiling, kneeWidthDB: knee)

        case .reverb(let wet):
            return filters.reverb(samples, wetLevel: wet, sampleRate: sampleRate)
        }
    }

    /// Returns effect descriptions.
    public var description: String {
        effects.isEmpty ? "Empty chain" : effects.map { $0.name }.joined(separator: " → ")
    }

    // MARK: - Preset Chains

    /// Standard mastering chain: normalize → compress → HF polish.
    public static let standardMastering: AudioEffectChain = {
        AudioEffectChain()
            .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -6.0)))
            .add(AudioEffect(name: "Compress", kind: .compress(threshold: -20, ratio: 4.0)))
            .add(AudioEffect(name: "De-esser", kind: .deEsser(centerHz: 6000)))
    }()

    /// Podcast chain: de-ess → normalize → light compression.
    public static let podcast: AudioEffectChain = {
        AudioEffectChain()
            .add(AudioEffect(name: "De-esser", kind: .deEsser(centerHz: 5500)))
            .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -6.0)))
            .add(AudioEffect(name: "Compress", kind: .compress(threshold: -15, ratio: 3.0)))
    }()

    /// Warmth chain: low-pass gentle roll-off → slight compression → reverb.
    public static let warmth: AudioEffectChain = {
        AudioEffectChain()
            .add(AudioEffect(name: "Smooth", kind: .lowPass(cutoffHz: 12000)))
            .add(AudioEffect(name: "Compress", kind: .compress(threshold: -20, ratio: 2.0)))
            .add(AudioEffect(name: "Reverb", kind: .reverb(wetLevel: 0.2)))
    }()

    /// Clean chain: remove rumble → normalize → de-esser.
    public static let clean: AudioEffectChain = {
        AudioEffectChain()
            .add(AudioEffect(name: "Rumble Filter", kind: .highPass(cutoffHz: 60)))
            .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -6.0)))
            .add(AudioEffect(name: "De-esser", kind: .deEsser(centerHz: 6500)))
    }()

    /// Voice clarity: de-esser → HF boost (simulated) → normalize.
    public static let voiceClarity: AudioEffectChain = {
        AudioEffectChain()
            .add(AudioEffect(name: "De-esser", kind: .deEsser(centerHz: 5000)))
            .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -3.0)))
            .add(AudioEffect(name: "Soft Clip", kind: .softClip(threshold: 0.95)))
    }()

    /// Builds the optional AUD-022 broadcast chain for an output sample rate.
    /// It is deliberately opt-in rather than applied by default synthesis.
    public static func broadcast(sampleRate: Int) -> AudioEffectChain {
        // Keep the de-esser below Nyquist for supported low-rate exports while
        // preserving the canonical 6 kHz target at 16 kHz and above.
        let deEsserCenterHz = min(6_000, Double(sampleRate) * 0.45)
        return AudioEffectChain(sampleRate: sampleRate)
            .add(AudioEffect(name: "DC Block", kind: .removeDCOffset))
            .add(AudioEffect(name: "40 Hz High Pass", kind: .highPass(cutoffHz: 40)))
            .add(AudioEffect(name: "De-esser", kind: .deEsser(centerHz: deEsserCenterHz)))
            .add(AudioEffect(
                name: "Soft-knee Limiter",
                kind: .softKneeLimiter(ceilingDB: -1, kneeWidthDB: 3)))
            .add(AudioEffect(name: "Clickless Edges", kind: .edgeFade(durationMilliseconds: 5)))
    }

    /// The canonical 48 kHz broadcast chain retained for source compatibility.
    public static let broadcast = broadcast(sampleRate: 48_000)
}
