import Foundation

/// An independent speech recognizer used to score intelligibility (QUA-004).
///
/// The requirement calls for "an independent ASR system" — independent of
/// CHOIR, so that the engine is not marking its own homework. The protocol
/// keeps the recognizer out of the shipping library: `SEC-001` requires the
/// runtime to make zero network connections, and a consuming app should not
/// link a speech framework or face a privacy prompt because CHOIR can test
/// itself. Implementations live in the benchmark tool.
public protocol SpeechTranscriber: Sendable {
    /// Identifies the recognizer in the report, so a score can be attributed.
    var identifier: String { get }

    /// Whether this recognizer can run here and now.
    ///
    /// Recognition may need authorization or an on-device model that is not
    /// installed. An unavailable recognizer must say so rather than returning
    /// empty transcriptions, which would score as total unintelligibility.
    var isAvailable: Bool { get async }

    /// Transcribes synthesized audio.
    func transcribe(_ audio: AudioBuffer) async throws -> String
}

/// One sentence's result.
public struct SentenceScore: Sendable, Equatable, Codable {
    public let reference: String
    public let hypothesis: String
    public let wordAccuracy: Double
    public let referenceWordCount: Int

    public init(reference: String, hypothesis: String) {
        self.reference = reference
        self.hypothesis = hypothesis
        self.wordAccuracy = TranscriptionScoring.wordAccuracy(
            reference: reference, hypothesis: hypothesis)
        self.referenceWordCount = TranscriptionScoring.normalizedWords(reference).count
    }
}

/// The conditions a voice was measured under.
public enum IntelligibilityCondition: String, Sendable, Equatable, Codable, CaseIterable {
    /// Default parameters. QUA-004 requires ≥ 98% here.
    case defaultParameters

    /// The corners of the customization envelope: minimum and maximum pitch
    /// against minimum and maximum rate. QUA-004 requires ≥ 96% here, and
    /// VOX-G-007 requires the voice to stay intelligible across them.
    case envelopeCorner

    /// The accuracy this condition must reach.
    public var target: Double {
        switch self {
        case .defaultParameters: return 0.98
        case .envelopeCorner: return 0.96
        }
    }
}

/// The outcome of an intelligibility run for one voice.
public struct IntelligibilityReport: Sendable, Equatable, Codable {
    public let voice: Voice
    public let condition: IntelligibilityCondition
    public let transcriberIdentifier: String
    public let parameters: SynthesisParameters
    public let scores: [SentenceScore]

    public init(
        voice: Voice,
        condition: IntelligibilityCondition,
        transcriberIdentifier: String,
        parameters: SynthesisParameters,
        scores: [SentenceScore]
    ) {
        self.voice = voice
        self.condition = condition
        self.transcriberIdentifier = transcriberIdentifier
        self.parameters = parameters
        self.scores = scores
    }

    /// Word accuracy across the corpus, weighted by sentence length.
    ///
    /// Weighted rather than averaged per sentence: a ten-word sentence and a
    /// four-word sentence should not count equally toward a word-level figure.
    public var wordAccuracy: Double {
        let totalWords = scores.reduce(0) { $0 + $1.referenceWordCount }
        guard totalWords > 0 else { return 0 }
        let correct = scores.reduce(0.0) { $0 + $1.wordAccuracy * Double($1.referenceWordCount) }
        return correct / Double(totalWords)
    }

    /// Whether this run meets its target.
    public var meetsTarget: Bool { wordAccuracy >= condition.target }

    public var summary: String {
        String(format: "%@ (%@, %@): %.1f%% word accuracy against a %.0f%% target — %@",
               voice.displayName,
               condition.rawValue,
               transcriberIdentifier,
               wordAccuracy * 100,
               condition.target * 100,
               meetsTarget ? "PASS" : "FAIL")
    }
}

/// Measures whether synthesized speech can be understood (SRS QUA-004).
///
/// "Intelligibility: word-level transcription accuracy ≥ 98% when standard
/// Harvard sentences synthesized by each voice (default parameters) are
/// transcribed by an independent ASR system, and ≥ 96% at envelope corners."
///
/// - Important: this is the objective gate on whether a trained voice is
///   usable, and it cannot return a meaningful number until such a voice
///   exists. Run against the current mock acoustic model and Griffin-Lim
///   vocoder it will score near zero, correctly: the audio is not speech. The
///   harness is built now so that the first trained model can be judged the day
///   it lands rather than by ear.
public struct IntelligibilityHarness: Sendable {

    /// The corpus to synthesize.
    public let sentences: [String]

    public init(sentences: [String] = HarvardSentences.standard) {
        self.sentences = sentences
    }

    /// The four corners of the customization envelope (VOX-G-007).
    ///
    /// Minimum and maximum pitch against minimum and maximum rate, which are
    /// the extremes a consuming app can reach through the public parameters.
    public static var envelopeCorners: [SynthesisParameters] {
        [
            SynthesisParameters(pitchShift: -12, rate: 0.5),
            SynthesisParameters(pitchShift: -12, rate: 2.0),
            SynthesisParameters(pitchShift: 12, rate: 0.5),
            SynthesisParameters(pitchShift: 12, rate: 2.0),
        ]
    }

    /// Runs the corpus through `voice` and scores the transcriptions.
    ///
    /// - Throws: ``ChoirError`` if the recognizer is unavailable. That is a
    ///   failure to measure, not a measurement of zero, and conflating the two
    ///   would report an unrunnable test as a catastrophic result.
    public func evaluate(
        voice: Voice,
        engine: ChoirEngine,
        transcriber: SpeechTranscriber,
        parameters: SynthesisParameters = SynthesisParameters(),
        condition: IntelligibilityCondition = .defaultParameters
    ) async throws -> IntelligibilityReport {
        guard await transcriber.isAvailable else {
            throw ChoirError.synthesisError(
                reason: "Speech recognizer '\(transcriber.identifier)' is unavailable; intelligibility cannot be measured")
        }

        var scores: [SentenceScore] = []
        for sentence in sentences {
            let audio = try await engine.synthesize(
                text: sentence, voice: voice, parameters: parameters)
            let hypothesis = (try? await transcriber.transcribe(audio)) ?? ""
            scores.append(SentenceScore(reference: sentence, hypothesis: hypothesis))
        }

        return IntelligibilityReport(
            voice: voice,
            condition: condition,
            transcriberIdentifier: transcriber.identifier,
            parameters: parameters,
            scores: scores)
    }

    /// Runs the corpus at every envelope corner (VOX-G-007, QUA-004).
    public func evaluateEnvelopeCorners(
        voice: Voice,
        engine: ChoirEngine,
        transcriber: SpeechTranscriber
    ) async throws -> [IntelligibilityReport] {
        var reports: [IntelligibilityReport] = []
        for corner in Self.envelopeCorners {
            reports.append(try await evaluate(
                voice: voice,
                engine: engine,
                transcriber: transcriber,
                parameters: corner,
                condition: .envelopeCorner))
        }
        return reports
    }
}
