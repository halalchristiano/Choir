import Foundation
import Testing
@testable import Choir

/// SRS QUA-004 (MUST) — intelligibility.
///
/// "Word-level transcription accuracy ≥ 98% when standard Harvard sentences
/// synthesized by each voice (default parameters) are transcribed by an
/// independent ASR system, and ≥ 96% at envelope corners (VOX-G-007)."
///
/// The harness cannot return a meaningful score until a trained acoustic model
/// exists, so these tests verify the scoring, the corpus and the plumbing —
/// the parts that must already be right for the first real measurement to mean
/// anything.
@Suite("SRS QUA-004 — intelligibility scoring")
struct TranscriptionScoringTests {

    @Test("QUA-004: a perfect transcription scores 100%")
    func testPerfect() {
        let sentence = "The birch canoe slid on the smooth planks."
        #expect(TranscriptionScoring.wordAccuracy(reference: sentence, hypothesis: sentence) == 1.0)
        #expect(TranscriptionScoring.wordErrorRate(reference: sentence, hypothesis: sentence) == 0)
    }

    /// An ASR system returns neither punctuation nor reliable casing, so
    /// comparing raw strings would score correct transcriptions as errors.
    @Test("QUA-004: casing and punctuation are not errors")
    func testNormalization() {
        let reference = "The birch canoe slid on the smooth planks."
        let hypothesis = "the birch canoe slid on the smooth planks"
        #expect(TranscriptionScoring.wordAccuracy(reference: reference, hypothesis: hypothesis) == 1.0)
    }

    /// Contractions must not be conflated: "it's" and "its" are different
    /// words, and treating them as one would hide a real failure.
    @Test("QUA-004: contractions are preserved")
    func testContractions() {
        let words = TranscriptionScoring.normalizedWords("It's easy to tell the depth of a well.")
        #expect(words.first == "it's")
        #expect(words.contains("well"))
    }

    @Test("QUA-004: substitutions, deletions and insertions all count")
    func testErrorTypes() {
        let reference = "one two three four"

        // One substitution in four words.
        #expect(abs(TranscriptionScoring.wordErrorRate(
            reference: reference, hypothesis: "one two THREE_WRONG four") - 0.25) < 0.001)

        // One deletion.
        #expect(abs(TranscriptionScoring.wordErrorRate(
            reference: reference, hypothesis: "one two four") - 0.25) < 0.001)

        // One insertion.
        #expect(abs(TranscriptionScoring.wordErrorRate(
            reference: reference, hypothesis: "one two two three four") - 0.25) < 0.001)
    }

    /// Insertions can push WER above 1; a negative accuracy is not meaningful.
    @Test("QUA-004: accuracy is floored at zero")
    func testAccuracyFloor() {
        let accuracy = TranscriptionScoring.wordAccuracy(
            reference: "one",
            hypothesis: "a b c d e f g h")
        #expect(accuracy >= 0)
    }

    /// Silence must score zero, not be mistaken for a pass.
    @Test("QUA-004: an empty transcription scores zero")
    func testEmptyTranscription() {
        #expect(TranscriptionScoring.wordAccuracy(
            reference: "the birch canoe", hypothesis: "") == 0)
    }

    @Test("QUA-004: the corpus is the standard Harvard lists")
    func testCorpus() {
        #expect(HarvardSentences.list1.count == 10)
        #expect(HarvardSentences.list2.count == 10)
        #expect(HarvardSentences.standard.count == 20)
        #expect(HarvardSentences.standard.first == "The birch canoe slid on the smooth planks.")
        #expect(HarvardSentences.standardWordCount > 100)
    }

    @Test("QUA-004: report accuracy is weighted by sentence length")
    func testWeightedAccuracy() {
        // A perfect long sentence and a failed short one. An unweighted mean
        // would report 50%; word-level accuracy must favour the longer.
        let long = SentenceScore(
            reference: "one two three four five six seven eight nine ten",
            hypothesis: "one two three four five six seven eight nine ten")
        let short = SentenceScore(reference: "alpha beta", hypothesis: "")

        let report = IntelligibilityReport(
            voice: .isla,
            condition: .defaultParameters,
            transcriberIdentifier: "test",
            parameters: SynthesisParameters(),
            scores: [long, short])

        // 10 of 12 reference words correct.
        #expect(abs(report.wordAccuracy - 10.0 / 12.0) < 0.001)
        #expect(!report.meetsTarget)
    }

    @Test("QUA-004: the two targets match the requirement")
    func testTargets() {
        #expect(IntelligibilityCondition.defaultParameters.target == 0.98)
        #expect(IntelligibilityCondition.envelopeCorner.target == 0.96)
    }

    @Test("QUA-004: a passing run is recognized")
    func testPassingRun() {
        let scores = HarvardSentences.standard.map {
            SentenceScore(reference: $0, hypothesis: $0)
        }
        let report = IntelligibilityReport(
            voice: .isla,
            condition: .defaultParameters,
            transcriberIdentifier: "test",
            parameters: SynthesisParameters(),
            scores: scores)

        #expect(report.wordAccuracy == 1.0)
        #expect(report.meetsTarget)
        #expect(report.summary.contains("PASS"))
    }

    /// VOX-G-007 requires intelligibility across the customization envelope,
    /// so the corners must be the actual parameter extremes.
    @Test("VOX-G-007: the envelope corners are the parameter extremes")
    func testEnvelopeCorners() {
        let corners = IntelligibilityHarness.envelopeCorners
        #expect(corners.count == 4)

        let pitches = Set(corners.map(\.pitchShift))
        let rates = Set(corners.map(\.rate))
        #expect(pitches == [-12, 12])
        #expect(rates == [0.5, 2.0])
    }

    /// An unavailable recognizer is a failure to measure, not a score of zero.
    /// Conflating the two would report an unrunnable test as catastrophic.
    @Test("QUA-004: an unavailable recognizer throws rather than scoring zero")
    func testUnavailableRecognizerThrows() async throws {
        struct Unavailable: SpeechTranscriber {
            let identifier = "unavailable"
            var isAvailable: Bool { get async { false } }
            func transcribe(_ audio: AudioBuffer) async throws -> String { "" }
        }

        let engine = ChoirEngine()
        try await engine.initialize()

        await #expect(throws: ChoirError.self) {
            _ = try await IntelligibilityHarness(sentences: ["one two three"])
                .evaluate(voice: .isla, engine: engine, transcriber: Unavailable())
        }
    }

    /// End-to-end with a stub recognizer that returns the reference text: it
    /// proves the plumbing carries audio through synthesis and scoring.
    @Test("QUA-004: the harness runs end to end")
    func testHarnessEndToEnd() async throws {
        struct EchoTranscriber: SpeechTranscriber {
            let identifier = "echo"
            let text: String
            var isAvailable: Bool { get async { true } }
            func transcribe(_ audio: AudioBuffer) async throws -> String { text }
        }

        let engine = ChoirEngine()
        try await engine.initialize()

        let sentence = "The birch canoe slid on the smooth planks."
        let report = try await IntelligibilityHarness(sentences: [sentence])
            .evaluate(
                voice: .isla,
                engine: engine,
                transcriber: EchoTranscriber(text: sentence))

        #expect(report.scores.count == 1)
        #expect(report.wordAccuracy == 1.0)
        #expect(report.voice == .isla)
        #expect(report.transcriberIdentifier == "echo")
    }

    @Test("QUA-004: the report round-trips as JSON")
    func testCodable() throws {
        let report = IntelligibilityReport(
            voice: .grimshaw,
            condition: .envelopeCorner,
            transcriberIdentifier: "test",
            parameters: SynthesisParameters(pitchShift: -12, rate: 2.0),
            scores: [SentenceScore(reference: "a b", hypothesis: "a b")])

        let data = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(IntelligibilityReport.self, from: data) == report)
    }
}
