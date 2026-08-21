import Foundation

/// Input features to the acoustic model.
public struct AcousticModelInput: Sendable {
    /// Phoneme indices (phoneme embedding input).
    public let phonemeIndices: [Int]

    /// Duration of each phoneme in milliseconds.
    public let durations: [Double]

    /// Fundamental frequency (pitch) in Hz for each phoneme.
    public let fundamentalFrequency: [Double]

    /// Energy (loudness) in LUFS for each phoneme.
    public let energy: [Double]

    /// Stress level (0, 1, or 2) for each phoneme.
    public let stress: [Int]

    /// Whether each phoneme is voiced (1.0) or unvoiced (0.0).
    public let voicing: [Double]

    /// Speaker/voice ID.
    public let voiceID: Int

    public init(
        phonemeIndices: [Int],
        durations: [Double],
        fundamentalFrequency: [Double],
        energy: [Double],
        stress: [Int],
        voicing: [Double],
        voiceID: Int = 0
    ) {
        self.phonemeIndices = phonemeIndices
        self.durations = durations
        self.fundamentalFrequency = fundamentalFrequency
        self.energy = energy
        self.stress = stress
        self.voicing = voicing
        self.voiceID = voiceID
    }

    /// Number of phoneme-aligned rows carried by the input.
    public var count: Int { phonemeIndices.count }

    /// Validates the parallel tensor contract before model inference.
    public func validate() throws {
        guard !phonemeIndices.isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "phonemeIndices", reason: "At least one phoneme is required")
        }

        let counts = [
            durations.count,
            fundamentalFrequency.count,
            energy.count,
            stress.count,
            voicing.count,
        ]
        guard counts.allSatisfy({ $0 == phonemeIndices.count }) else {
            throw ChoirError.invalidParameter(
                parameter: "acousticModelInput",
                reason: "All phoneme-aligned tensors must have the same length")
        }
        guard phonemeIndices.allSatisfy({ $0 >= 0 }) else {
            throw ChoirError.invalidParameter(
                parameter: "phonemeIndices", reason: "Indices cannot be negative")
        }
        guard durations.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw ChoirError.invalidParameter(
                parameter: "durations", reason: "Durations must be finite and greater than zero")
        }
        guard fundamentalFrequency.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw ChoirError.invalidParameter(
                parameter: "fundamentalFrequency",
                reason: "Fundamental frequency must be finite and non-negative")
        }
        guard energy.allSatisfy({ $0.isFinite }) else {
            throw ChoirError.invalidParameter(
                parameter: "energy", reason: "Energy values must be finite")
        }
        guard stress.allSatisfy({ 0...2 ~= $0 }) else {
            throw ChoirError.invalidParameter(
                parameter: "stress", reason: "Stress values must be 0, 1, or 2")
        }
        guard voicing.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }) else {
            throw ChoirError.invalidParameter(
                parameter: "voicing", reason: "Voicing values must be finite and within 0...1")
        }
        guard voiceID >= 0 else {
            throw ChoirError.invalidParameter(
                parameter: "voiceID", reason: "Voice ID cannot be negative")
        }
    }
}

/// Acoustic features output from the model (Mel-spectrogram or similar).
public struct AcousticFeatures: Sendable {
    /// Mel-spectrogram or acoustic feature matrix (time × frequency).
    public let features: [[Float]]

    /// Number of time frames.
    public var frameCount: Int {
        features.count
    }

    /// Number of frequency bins.
    public var frequencyBins: Int {
        features.first?.count ?? 0
    }

    /// Frame rate (frames per second).
    public let frameRate: Int

    /// Duration in seconds.
    public var duration: Double {
        guard frameRate > 0 else { return 0 }
        return Double(frameCount) / Double(frameRate)
    }

    /// Whether every frame has the same number of frequency bins.
    public var isRectangular: Bool {
        guard let width = features.first?.count else { return true }
        return features.allSatisfy { $0.count == width }
    }

    /// Whether every feature value is finite.
    public var containsOnlyFiniteValues: Bool {
        features.allSatisfy { frame in frame.allSatisfy { $0.isFinite } }
    }

    public init(features: [[Float]], frameRate: Int = 50) {
        self.features = features
        self.frameRate = frameRate
    }
}

/// Protocol for acoustic model inference.
public protocol AcousticModelProtocol: Sendable {
    /// Infers acoustic features from linguistic input.
    ///
    /// - Parameter input: Acoustic model input features.
    /// - Returns: Acoustic features ready for vocoding.
    /// - Throws: `ChoirError` if inference fails.
    func predict(input: AcousticModelInput) async throws -> AcousticFeatures
}

/// Mock acoustic model for testing (generates random features).
public struct MockAcousticModel: AcousticModelProtocol {
    private let frameRate: Int
    private let frequencyBins: Int

    public init(frameRate: Int = 50, frequencyBins: Int = 80) {
        self.frameRate = max(1, frameRate)
        self.frequencyBins = max(1, frequencyBins)
    }

    public func predict(input: AcousticModelInput) async throws -> AcousticFeatures {
        try input.validate()

        // Calculate total duration from phonemes
        let totalDurationMs = input.durations.reduce(0, +)
        let totalDurationSecs = totalDurationMs / 1000.0

        // Generate frame count
        let frameCount = max(1, Int(ceil(totalDurationSecs * Double(frameRate))))

        // Deterministic test features. Random output made identical requests
        // nondeterministic and could hide regressions behind changing mocks.
        let features: [[Float]] = (0..<frameCount).map { frame in
            (0..<frequencyBins).map { bin in
                let phase = Double((frame + 1) * (bin + 1) + input.voiceID) * 0.017
                return Float(-2 + 2 * sin(phase))
            }
        }

        return AcousticFeatures(features: features, frameRate: frameRate)
    }
}

/// Placeholder for future Core ML acoustic model.
public struct CoreMLAcousticModel: AcousticModelProtocol {
    // TODO: Implement when Core ML model files are available
    // private let model: MLModel?

    public init() {}

    public func predict(input: AcousticModelInput) async throws -> AcousticFeatures {
        try input.validate()
        throw ChoirError.modelLoadFailed(
            reason: "No production Core ML acoustic model is bundled in this build")
    }
}

/// Encoder for converting phonemes to model input indices.
public struct PhonemeEncoder: Sendable {
    /// Maps phoneme symbols to integer indices.
    private let phonemeToIndex: [String: Int]

    /// Maps integer indices back to phoneme symbols.
    private let indexToPhoneme: [Int: String]

    public init() {
        // Derive the model vocabulary from the public inventory so the two
        // cannot drift. In particular, this preserves U+0261 script-g.
        let phonemeList = PhonemeInventory.all.map(\.ipa)

        var toIndex: [String: Int] = [:]
        var toPhoneme: [Int: String] = [:]

        for (idx, phoneme) in phonemeList.enumerated() {
            toIndex[phoneme] = idx
            toPhoneme[idx] = phoneme
        }

        self.phonemeToIndex = toIndex
        self.indexToPhoneme = toPhoneme
    }

    /// Encodes phonemes to integer indices.
    public func encode(_ phonemes: [Phoneme]) -> [Int] {
        phonemes.compactMap { phonemeToIndex[$0.symbol] }
    }

    /// Encodes without silently dropping an unknown phoneme.
    public func encodeStrict(_ phonemes: [Phoneme]) throws -> [Int] {
        let unknown = unknownSymbols(in: phonemes)
        guard unknown.isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "phonemes",
                reason: "Unknown phoneme symbols: \(unknown.joined(separator: ", "))")
        }
        return phonemes.map { phonemeToIndex[$0.symbol]! }
    }

    /// Decodes integer indices back to phonemes.
    public func decode(_ indices: [Int]) -> [String] {
        indices.compactMap { indexToPhoneme[$0] }
    }

    /// Decodes without silently dropping an unknown model index.
    public func decodeStrict(_ indices: [Int]) throws -> [String] {
        let unknown = Array(Set(indices.filter { indexToPhoneme[$0] == nil })).sorted()
        guard unknown.isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "phonemeIndices",
                reason: "Unknown phoneme indices: \(unknown.map { String($0) }.joined(separator: ", "))")
        }
        return indices.map { indexToPhoneme[$0]! }
    }

    /// Unknown symbols in first-seen order, without duplicates.
    public func unknownSymbols(in phonemes: [Phoneme]) -> [String] {
        var seen: Set<String> = []
        return phonemes.compactMap { phoneme in
            guard phonemeToIndex[phoneme.symbol] == nil,
                  seen.insert(phoneme.symbol).inserted else { return nil }
            return phoneme.symbol
        }
    }

    /// Returns the vocabulary size.
    public var vocabularySize: Int {
        phonemeToIndex.count
    }
}
