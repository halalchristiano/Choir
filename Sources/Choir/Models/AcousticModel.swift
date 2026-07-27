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
        Double(frameCount) / Double(frameRate)
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
        self.frameRate = frameRate
        self.frequencyBins = frequencyBins
    }

    public func predict(input: AcousticModelInput) async throws -> AcousticFeatures {
        // Calculate total duration from phonemes
        let totalDurationMs = input.durations.reduce(0, +)
        let totalDurationSecs = totalDurationMs / 1000.0

        // Generate frame count
        let frameCount = Int(totalDurationSecs * Double(frameRate))
        guard frameCount > 0 else {
            throw ChoirError.synthesisError(reason: "Invalid frame count from duration")
        }

        // Generate mock acoustic features
        // In reality, these would come from a Core ML model
        var features: [[Float]] = []
        for _ in 0..<frameCount {
            var frame: [Float] = []
            for _ in 0..<frequencyBins {
                // Generate realistic-ish mel-spectrogram values
                let value = Float.random(in: -4...0)  // Log scale
                frame.append(value)
            }
            features.append(frame)
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
        throw ChoirError.unknown("CoreML acoustic model not yet implemented")
    }
}

/// Encoder for converting phonemes to model input indices.
public struct PhonemeEncoder: Sendable {
    /// Maps phoneme symbols to integer indices.
    private let phonemeToIndex: [String: Int]

    /// Maps integer indices back to phoneme symbols.
    private let indexToPhoneme: [Int: String]

    public init() {
        let phonemeList = [
            "ɑ", "æ", "ɛ", "ə", "ɪ", "ɔ", "ʊ", "ʌ",
            "iː", "uː", "oʊ", "eɪ", "aɪ", "ɔɪ", "aʊ", "ɪə", "ɛə", "ʊə",
            "b", "d", "f", "g", "h", "j", "k", "l", "m", "n", "ŋ", "p", "r", "s", "t", "v", "w", "z",
            "θ", "ð", "ʃ", "ʒ", "tʃ", "dʒ",
        ]

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

    /// Decodes integer indices back to phonemes.
    public func decode(_ indices: [Int]) -> [String] {
        indices.compactMap { indexToPhoneme[$0] }
    }

    /// Returns the vocabulary size.
    public var vocabularySize: Int {
        phonemeToIndex.count
    }
}
