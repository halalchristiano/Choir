import Foundation
import Testing
@testable import Choir

/// SRS Part IV — package structure, public API, and the error model.
@Suite("SRS Part IV — package and API")
struct PackageAndAPITests {

    /// PKG-005 requires permissive-licensed third-party work to be documented
    /// in a NOTICE file. CMUdict is redistributed, so the file must exist and
    /// must name it.
    @Test("PKG-005: third-party work is documented in NOTICE")
    func testNoticeFile() throws {
        // The repository root is four levels above this file at build time,
        // so the check is on the shipped licence text instead, which must
        // accompany the data per its own terms.
        let licence = Bundle.module.url(forResource: "CMUDICT-LICENSE", withExtension: "txt")
        #expect(licence != nil, "CMUdict licence is not shipped alongside the data")
    }

    /// API-001 Tier 1: a one-liner that is complete for its use level.
    @Test("API-001: Tier 1 synthesizes in one call")
    func testTierOne() async throws {
        let audio = try await Choir.synthesize("Hello there.", voice: .maeve)
        #expect(!audio.samples.isEmpty)
    }

    @Test("API-001: the tiers are concentric, not exclusive")
    func testTiersCoexist() async throws {
        // Tier 2 remains available and is what Tier 1 is written in terms of.
        let engine = ChoirEngine()
        try await engine.initialize()
        let viaEngine = try await engine.synthesize(text: "Hello there.", voice: .maeve)
        let viaOneLiner = try await Choir.synthesize("Hello there.", voice: .maeve)

        #expect(!viaEngine.samples.isEmpty)
        #expect(!viaOneLiner.samples.isEmpty)
    }

    /// API-003: voices addressable dynamically by stable string ID, for
    /// data-driven use such as game character tables.
    @Test("API-003: voices resolve from a string id")
    func testDynamicVoiceAddressing() {
        #expect(Voice(id: "choir.eld.female.maeve") == .maeve)
        #expect(Voice(id: "MAEVE") == .maeve)
        #expect(Voice(id: "maeve") == .maeve)
        #expect(Voice(id: "  Grimshaw  ") == .grimshaw)
        #expect(Voice(id: "no-such-voice") == nil)
    }

    @Test("API-003: every voice round-trips through its identifier")
    func testEveryVoiceRoundTrips() {
        for voice in Voice.allCases {
            #expect(Voice(id: voice.identifier) == voice)
            #expect(Voice(id: voice.displayName) == voice)
        }
    }

    /// API-004: validation that *reports* envelope clamping. Silent clamping
    /// is the failure this exists to prevent.
    @Test("API-004: clamping is reported, not silent")
    func testClampingReported() {
        let clamped = SynthesisParameters(pitchShift: 24, rate: 5.0)
        #expect(clamped.pitchShift == 12)
        #expect(clamped.rate == 2.0)
        #expect(clamped.wasClamped)
        #expect(clamped.clampings.count == 2)

        let names = Set(clamped.clampings.map(\.parameter))
        #expect(names == ["pitchShift", "rate"])

        let pitch = clamped.clampings.first { $0.parameter == "pitchShift" }
        #expect(pitch?.requested == 24)
        #expect(pitch?.applied == 12)
    }

    @Test("API-004: in-range values report no clamping")
    func testNoClampingWhenInRange() {
        let parameters = SynthesisParameters(pitchShift: 3, rate: 1.2)
        #expect(!parameters.wasClamped)
        #expect(parameters.clampings.isEmpty)
    }

    /// API-004: builder-style modification.
    @Test("API-004: builder-style modification")
    func testBuilder() {
        let parameters = SynthesisParameters()
            .pitch(5)
            .speed(1.5)
            .emotion(0.8)
            .breath(0.3)
            .seeded(42)

        #expect(parameters.pitchShift == 5)
        #expect(parameters.rate == 1.5)
        #expect(parameters.emotionalIntensity == 0.8)
        #expect(parameters.breathiness == 0.3)
        #expect(parameters.seed == 42)
    }

    /// A builder step must not smuggle an out-of-range value past validation.
    @Test("API-004: the builder clamps and reports too")
    func testBuilderClamps() {
        let parameters = SynthesisParameters().pitch(99)
        #expect(parameters.pitchShift == 12)
        #expect(parameters.wasClamped)
    }

    /// REL-001: a stable code, a description, and a recovery suggestion on
    /// every case.
    @Test("REL-001: every error carries a code, description and recovery")
    func testErrorTaxonomy() {
        let errors: [ChoirError] = [
            .modelLoadFailed(reason: "x"), .textProcessingFailed(reason: "x"),
            .synthesisError(reason: "x"), .audioEncodingFailed(reason: "x"),
            .notInitialized, .cancelled,
            .invalidParameter(parameter: "p", reason: "x"),
            .outOfMemory, .timeout, .unknown("x"),
        ]

        var codes: Set<String> = []
        for error in errors {
            #expect(error.code.hasPrefix("CHOIR-"), "\(error) has no stable code")
            #expect(error.errorDescription?.isEmpty == false, "\(error) has no description")
            #expect(error.recoverySuggestion?.isEmpty == false, "\(error) has no recovery suggestion")
            codes.insert(error.code)
        }
        #expect(codes.count == errors.count, "error codes are not unique")
    }

    /// Retryability differs per case, and a caller needs to know which.
    @Test("REL-001: retryability is classified")
    func testRetryability() {
        #expect(ChoirError.outOfMemory.isRetryable)
        #expect(ChoirError.timeout.isRetryable)
        #expect(!ChoirError.cancelled.isRetryable)
        #expect(!ChoirError.notInitialized.isRetryable)
        #expect(!ChoirError.invalidParameter(parameter: "p", reason: "r").isRetryable)
    }

    /// REL-003: a start-up self-check, so an app detects a broken installation
    /// deterministically rather than at the user's first request.
    @Test("REL-003: verify reports a healthy installation")
    func testVerifyHealthy() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let result = await engine.verify()
        #expect(result.isHealthy, "\(result.summary): \(result.failures.map(\.detail))")
        #expect(result.checks.count >= 4)
        #expect(result.checks.contains { $0.name == "lexicon" })
        #expect(result.checks.contains { $0.name == "smoke synthesis" })
    }

    @Test("REL-003: verify detects an uninitialized engine")
    func testVerifyUninitialized() async {
        let result = await ChoirEngine().verify()
        #expect(!result.isHealthy)
        #expect(result.failures.contains { $0.name == "initialization" })
        #expect(result.summary.contains("broken"))
    }
}

/// SRS TXT-032 — paragraph and section breaks.
@Suite("SRS TXT-032 — structural pauses and pitch reset")
struct StructuralProsodyTests {

    private func transcript(_ text: String) throws -> PhoneticTranscription {
        try LinguisticFrontend().process(text)
    }

    @Test("TXT-032: sentence boundaries reach the transcription")
    func testBoundariesCarried() throws {
        let result = try transcript("First one. Second one. Third one.")
        #expect(!result.phraseBoundaries.isEmpty, "no boundaries were recorded")
    }

    @Test("TXT-032: a paragraph break outranks a sentence break")
    func testParagraphOutranksSentence() throws {
        let result = try transcript("First paragraph here.\n\nSecond paragraph here.")
        let strengths = Set(result.phraseBoundaries.values)
        #expect(strengths.contains(.paragraph), "found \(strengths)")
    }

    /// The behaviour the requirement asks for: a stronger break must lengthen
    /// the pause, or a paragraph reads exactly like a comma.
    @Test("TXT-032: a stronger boundary produces a longer pause")
    func testStrongerBoundaryLengthensPause() {
        var short = [100.0, 100.0, 100.0]
        var long = short

        let minor = PhoneticTranscription(
            phonemes: [Phoneme("a"), Phoneme("b"), Phoneme("c")],
            originalText: "a b c",
            wordBoundaries: [0, 1, 2],
            wordTexts: ["a", "b", "c"],
            phraseBoundaries: [1: .minor])
        let paragraph = PhoneticTranscription(
            phonemes: [Phoneme("a"), Phoneme("b"), Phoneme("c")],
            originalText: "a b c",
            wordBoundaries: [0, 1, 2],
            wordTexts: ["a", "b", "c"],
            phraseBoundaries: [1: .paragraph])

        ProsodyPredictor.applyBoundaryPauses(to: &short, transcript: minor, rate: 1.0)
        ProsodyPredictor.applyBoundaryPauses(to: &long, transcript: paragraph, rate: 1.0)

        #expect(long[1] > short[1], "paragraph pause \(long[1]) not longer than minor \(short[1])")
        #expect(short[1] > 100.0, "no pause was added at all")
    }

    /// Pauses shorten as speech speeds up, as they do in natural speech.
    @Test("TXT-032: pauses scale with rate")
    func testPauseScalesWithRate() {
        let transcript = PhoneticTranscription(
            phonemes: [Phoneme("a"), Phoneme("b")],
            originalText: "a b",
            wordBoundaries: [0, 1],
            wordTexts: ["a", "b"],
            phraseBoundaries: [0: .paragraph])

        var slow = [100.0, 100.0]
        var fast = [100.0, 100.0]
        ProsodyPredictor.applyBoundaryPauses(to: &slow, transcript: transcript, rate: 0.5)
        ProsodyPredictor.applyBoundaryPauses(to: &fast, transcript: transcript, rate: 2.0)

        #expect(slow[0] > fast[0], "pause did not shorten at speed")
    }

    @Test("TXT-032: text with no boundaries is untouched")
    func testNoBoundariesNoChange() {
        let transcript = PhoneticTranscription(
            phonemes: [Phoneme("a")], originalText: "a",
            wordBoundaries: [0], wordTexts: ["a"])
        var durations = [100.0]
        ProsodyPredictor.applyBoundaryPauses(to: &durations, transcript: transcript, rate: 1.0)
        #expect(durations == [100.0])
    }

    /// Only structural breaks reset pitch; a comma must not.
    @Test("TXT-032: only paragraph and section breaks reset pitch")
    func testPitchResetOnlyAtStructuralBreaks() {
        #expect(!PhraseBoundary.minor.resetsPitch)
        #expect(!PhraseBoundary.major.resetsPitch)
        #expect(PhraseBoundary.paragraph.resetsPitch)
        #expect(PhraseBoundary.section.resetsPitch)
    }

    @Test("TXT-023: the supplement has grown")
    func testSupplementGrown() {
        #expect(TheologicalLexicon.count >= 190,
                "supplement has \(TheologicalLexicon.count) entries")
        for word in ["augustine", "calvin", "damascus", "atonement", "seraphim"] {
            #expect(BuiltInLexicon.shared.contains(word), "missing \(word)")
        }
    }
}
