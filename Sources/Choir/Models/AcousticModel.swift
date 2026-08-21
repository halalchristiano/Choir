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

    /// Request-level conditioning values. They remain explicit model inputs
    /// even when pitch/rate have also shaped the aligned contours, so a real
    /// acoustic model can learn timbre and realization changes (ML-A-002).
    public let pitchShift: Double
    public let rate: Double
    public let emotionalIntensity: Double
    public let breathiness: Double
    public let ageShift: Double
    public let genderShift: Double

    public init(
        phonemeIndices: [Int],
        durations: [Double],
        fundamentalFrequency: [Double],
        energy: [Double],
        stress: [Int],
        voicing: [Double],
        voiceID: Int = 0,
        pitchShift: Double = 0,
        rate: Double = 1,
        emotionalIntensity: Double = 0.5,
        breathiness: Double = 0,
        ageShift: Double = 0,
        genderShift: Double = 0
    ) {
        self.phonemeIndices = phonemeIndices
        self.durations = durations
        self.fundamentalFrequency = fundamentalFrequency
        self.energy = energy
        self.stress = stress
        self.voicing = voicing
        self.voiceID = voiceID
        self.pitchShift = pitchShift
        self.rate = rate
        self.emotionalIntensity = emotionalIntensity
        self.breathiness = breathiness
        self.ageShift = ageShift
        self.genderShift = genderShift
    }

    /// Number of phoneme-aligned rows carried by the input.
    public var count: Int { phonemeIndices.count }

    /// Validates the parallel tensor contract before model inference.
    public func validate() throws {
        guard !phonemeIndices.isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "phonemeIndices", reason: "At least one phoneme is required")
        }
        guard phonemeIndices.count <= 4_096 else {
            throw ChoirError.invalidParameter(
                parameter: "phonemeIndices",
                reason: "One acoustic-model invocation may contain at most 4,096 phonemes")
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
        guard durations.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 10_000 }) else {
            throw ChoirError.invalidParameter(
                parameter: "durations",
                reason: "Durations must be finite and within (0, 10,000] ms")
        }
        let totalDurationMs = durations.reduce(0, +)
        guard totalDurationMs.isFinite, totalDurationMs <= 600_000 else {
            throw ChoirError.invalidParameter(
                parameter: "durations",
                reason: "One acoustic-model invocation may describe at most 10 minutes")
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
        let controls = [
            ("pitchShift", pitchShift, -6.0 ... 6.0),
            ("rate", rate, 0.6 ... 2.0),
            ("emotionalIntensity", emotionalIntensity, 0.0 ... 1.0),
            ("breathiness", breathiness, 0.0 ... 1.0),
            ("ageShift", ageShift, -1.0 ... 1.0),
            ("genderShift", genderShift, -1.0 ... 1.0),
        ]
        for (name, value, envelope) in controls {
            guard value.isFinite, envelope.contains(value) else {
                throw ChoirError.invalidParameter(
                    parameter: name,
                    reason: "Model conditioning must be finite and within \(envelope)")
            }
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
        self.frameRate = min(1_000, max(1, frameRate))
        self.frequencyBins = min(4_096, max(1, frequencyBins))
    }

    public func predict(input: AcousticModelInput) async throws -> AcousticFeatures {
        try input.validate()

        // Calculate total duration from phonemes
        let totalDurationMs = input.durations.reduce(0, +)
        let totalDurationSecs = totalDurationMs / 1000.0

        // Generate frame count
        let frameCount = max(1, Int(ceil(totalDurationSecs * Double(frameRate))))
        let featureElements = frameCount.multipliedReportingOverflow(by: frequencyBins)
        guard !featureElements.overflow, featureElements.partialValue <= 100_000_000 else {
            throw ChoirError.outOfMemory
        }

        // Deterministic test features. Random output made identical requests
        // nondeterministic and could hide regressions behind changing mocks.
        let features: [[Float]] = (0..<frameCount).map { frame in
            (0..<frequencyBins).map { bin in
                let phase = (
                    Double(frame + 1) * Double(bin + 1) + Double(input.voiceID)
                ) * 0.017
                return Float(-2 + 2 * sin(phase))
            }
        }

        return AcousticFeatures(features: features, frameRate: frameRate)
    }
}

/// Adapter for a generated Core ML acoustic model.
///
/// Xcode-generated model classes differ by model architecture, so CHOIR keeps
/// their tensor spelling out of the public engine. The consuming asset target
/// supplies a `@Sendable` inference closure that invokes its generated Core ML
/// class and returns the normalized CHOIR feature representation. This makes a
/// production model injectable without making the engine depend on a specific
/// training checkpoint's generated Swift symbols.
public struct CoreMLAcousticModel: AcousticModelProtocol {
    public typealias Inference = @Sendable (AcousticModelInput) async throws -> AcousticFeatures

    private let inference: Inference?

    /// Creates an unavailable adapter. Kept for source compatibility and for
    /// deterministic diagnostics when no production asset is bundled.
    public init() {
        self.inference = nil
    }

    /// Creates an adapter around an Xcode-generated Core ML model invocation.
    public init(inference: @escaping Inference) {
        self.inference = inference
    }

    public func predict(input: AcousticModelInput) async throws -> AcousticFeatures {
        try input.validate()
        guard let inference else {
            throw ChoirError.modelLoadFailed(
                reason: "No production Core ML acoustic model is bundled in this build")
        }

        let result: AcousticFeatures
        do {
            result = try await inference(input)
        } catch let error as ChoirError {
            throw error
        } catch {
            throw ChoirError.synthesisError(
                reason: "Core ML acoustic inference failed: \(error.localizedDescription)")
        }

        guard (1...1_000).contains(result.frameRate),
              result.frameCount > 0,
              result.frameCount <= 600_000,
              result.frequencyBins > 0,
              result.frequencyBins <= 4_096,
              result.isRectangular,
              result.containsOnlyFiniteValues,
              result.duration.isFinite,
              result.duration <= 600 else {
            throw ChoirError.synthesisError(
                reason: "Core ML acoustic model returned an invalid feature tensor")
        }
        return result
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
