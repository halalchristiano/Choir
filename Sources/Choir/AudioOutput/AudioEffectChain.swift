import Foundation

/// Effect configuration for the chain.
public struct AudioEffect: Sendable {
    /// Effect type and parameters.
    public enum Kind: Sendable {
        case highPass(cutoffHz: Double)
        case lowPass(cutoffHz: Double)
        case normalize(targetLevel: Double)
        case compress(threshold: Double, ratio: Double)
        case deEsser(centerHz: Double)
        case softClip(threshold: Double)
        case reverb(wetLevel: Double)
    }

    public let name: String
    public let kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
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
