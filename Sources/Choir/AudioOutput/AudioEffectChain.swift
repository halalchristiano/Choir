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
        return AudioBuffer(samples: process(buffer.samples), format: buffer.format)
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
}
