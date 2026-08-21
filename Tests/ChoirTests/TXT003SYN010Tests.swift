import Foundation
import Testing
@testable import Choir

/// SRS TXT-003 (MUST) — input mode is selected explicitly, never guessed.
///
/// "Input shall be accepted as (a) plain text, (b) plain text with SSML-C
/// inline markup, or (c) a pre-phonemized sequence, selected explicitly by
/// API — never by guessing."
@Suite("SRS TXT-003 — explicit input modes")
struct InputModeTests {
    let frontend = LinguisticFrontend()

    @Test("TXT-003: markup mode parses tags")
    func testMarkupMode() throws {
        let transcript = try frontend.process(.markup("say <emphasis level=\"strong\">this</emphasis>"))
        #expect(!transcript.phonemes.isEmpty)
        // The tag itself is not spoken.
        #expect(!transcript.wordTexts.contains("emphasis"), "\(transcript.wordTexts)")
    }

    /// The point of the requirement: the same string is read differently
    /// depending on the declared mode, and never by sniffing content.
    @Test("TXT-003: plain text speaks markup characters literally")
    func testPlainTextMode() throws {
        let markup = try frontend.process(.markup("a <emphasis>b</emphasis> c"))
        let plain = try frontend.process(.plainText("a <emphasis>b</emphasis> c"))
        #expect(markup.phonemes.count != plain.phonemes.count,
                "the two modes produced identical output, so the mode was ignored")
    }

    @Test("TXT-003: a stray angle bracket is safe in plain text")
    func testStrayBracket() throws {
        // "5 < 7" is exactly the case content-sniffing gets wrong.
        let transcript = try frontend.process(.plainText("5 < 7 is true"))
        #expect(!transcript.phonemes.isEmpty)
    }

    @Test("TXT-050: pre-phonemized input bypasses the front end")
    func testPhonemeMode() throws {
        let phonemes = [Phoneme("h"), Phoneme("ɛ", stress: 1), Phoneme("l"), Phoneme("oʊ")]
        let transcript = try frontend.process(.phonemes(phonemes))
        #expect(transcript.phonemes.map(\.symbol) == phonemes.map(\.symbol))
        #expect(transcript.phonemes[1].stress == 1, "stress was not preserved")
    }

    /// TXT-024 requires the inventory to gate this path.
    @Test("TXT-050: symbols outside the inventory are rejected")
    func testInvalidPhonemesRejected() {
        let bad = SynthesisInput.phonemes([Phoneme("h"), Phoneme("QQQ")])
        #expect(bad.unknownPhonemeSymbols == ["QQQ"])
        #expect(throws: ChoirError.self) {
            _ = try LinguisticFrontend().process(bad)
        }
    }

    @Test("TXT-003: empty input is rejected in every mode")
    func testEmptyRejected() {
        for input in [SynthesisInput.plainText(""), .markup("   "), .phonemes([])] {
            #expect(input.isEmpty)
            #expect(throws: ChoirError.self) {
                _ = try LinguisticFrontend().process(input)
            }
        }
    }

    @Test("TXT-003: text accessor reflects the mode")
    func testTextAccessor() {
        #expect(SynthesisInput.plainText("a").text == "a")
        #expect(SynthesisInput.markup("b").text == "b")
        #expect(SynthesisInput.phonemes([Phoneme("h")]).text == nil)
    }
}

/// SRS SYN-010 (SHOULD) — lightweight duration estimate.
///
/// "The engine shall expose a lightweight duration estimate API (predicted
/// speech duration for text+voice+rate without full synthesis, ±10% accuracy)
/// for layout, pagination, and video planning."
@Suite("SRS SYN-010 — duration estimate")
struct DurationEstimateTests {
    let estimator = DurationEstimator()

    @Test("SYN-010: estimates are positive and grow with length")
    func testMonotonic() {
        let short = estimator.estimate(text: "Hello.", voice: .isla)
        let long = estimator.estimate(
            text: "Hello. " + String(repeating: "This is a longer passage. ", count: 20),
            voice: .isla)

        #expect(short.seconds > 0)
        #expect(long.seconds > short.seconds)
        #expect(long.syllables > short.syllables)
    }

    @Test("SYN-010: rate scales the estimate inversely")
    func testRateScaling() {
        let normal = estimator.estimate(text: "The quick brown fox.", voice: .isla, rate: 1.0)
        let fast = estimator.estimate(text: "The quick brown fox.", voice: .isla, rate: 2.0)
        let slow = estimator.estimate(text: "The quick brown fox.", voice: .isla, rate: 0.5)

        #expect(fast.seconds < normal.seconds)
        #expect(slow.seconds > normal.seconds)
    }

    /// A voice's designed tempo (VOX-P-001) must affect the estimate.
    @Test("SYN-010: a faster voice yields a shorter estimate")
    func testVoiceTempoMatters() {
        // WREN speaks at 5.0 syll/s, GRIMSHAW at 3.1.
        let quick = estimator.estimate(text: "The quick brown fox jumps.", voice: .wren)
        let slow = estimator.estimate(text: "The quick brown fox jumps.", voice: .grimshaw)
        #expect(quick.seconds < slow.seconds,
                "voice tempo had no effect: \(quick.seconds) vs \(slow.seconds)")
    }

    @Test("SYN-010: the estimate accounts for boundary pauses")
    func testPausesCounted() {
        let estimate = estimator.estimate(text: "One. Two. Three.", voice: .isla)
        #expect(estimate.pauseSeconds > 0)
        #expect(estimate.seconds > estimate.pauseSeconds)
        #expect(estimate.breathGroupCount >= 3)
    }

    /// The estimate must reflect the *spoken* form, not the written one.
    @Test("SYN-010: normalization is applied before estimating")
    func testNormalizedBeforeEstimating() {
        // "$1,250" is a few characters but many spoken syllables.
        let currency = estimator.estimate(text: "$1250", voice: .isla)
        let literal = estimator.estimate(text: "cat", voice: .isla)
        #expect(currency.syllables > literal.syllables,
                "expansion was not accounted for")
    }

    @Test("SYN-010: degenerate input does not trap")
    func testDegenerate() {
        for text in ["", "   ", "!!!", String(repeating: "a ", count: 5_000)] {
            let estimate = estimator.estimate(text: text, voice: .isla)
            #expect(estimate.seconds >= 0)
        }
    }

    @Test("SYN-010: milliseconds accessor agrees with seconds")
    func testMilliseconds() {
        let estimate = estimator.estimate(text: "Hello there.", voice: .isla)
        #expect(abs(estimate.milliseconds - estimate.seconds * 1000) < 0.001)
    }
}

/// SRS TXT-042 (MUST) — mid-text voice switching.
@Suite("SRS TXT-042 — voice switching")
struct VoiceSwitchingTests {

    @Test("TXT-042: voice ids resolve by identifier, name and case")
    func testVoiceResolution() {
        #expect(SynthesisPipeline.voice(forID: "choir.mid.male.garrick") == .garrick)
        #expect(SynthesisPipeline.voice(forID: "GARRICK") == .garrick)
        #expect(SynthesisPipeline.voice(forID: "garrick") == .garrick)
        #expect(SynthesisPipeline.voice(forID: "  Lyra  ") == .lyra)
        #expect(SynthesisPipeline.voice(forID: "nobody") == nil)
    }

    @Test("TXT-042: dialogue carries a voice per segment")
    func testDialogueSegments() throws {
        let markup = "<voice id=\"garrick\">Who goes there?</voice> <voice id=\"lyra\">A friend.</voice>"
        let result = try SSMLCParser().parse(markup)

        let voices = result.events.compactMap { event -> Voice? in
            guard case .speech(let text, let style) = event,
                  !text.trimmingCharacters(in: .whitespaces).isEmpty,
                  let id = style.voiceID else { return nil }
            return SynthesisPipeline.voice(forID: id)
        }
        #expect(voices == [.garrick, .lyra], "\(voices)")
    }

    @Test("TXT-042: an unknown voice id falls back rather than failing")
    func testUnknownVoiceFallsBack() throws {
        let result = try SSMLCParser().parse("<voice id=\"nosuchvoice\">text</voice>")
        let ids = result.events.compactMap { event -> String? in
            if case .speech(_, let style) = event { return style.voiceID }
            return nil
        }
        #expect(ids.first == "nosuchvoice")
        #expect(SynthesisPipeline.voice(forID: "nosuchvoice") == nil)
    }
}

/// SRS TXT-013 — ALL-CAPS emphasis.
@Suite("SRS TXT-013 — ALL-CAPS emphasis")
struct AllCapsTests {

    @Test("TXT-013: ALL-CAPS words become emphasis markup")
    func testAllCapsMarked() {
        let marked = TextNormalizer().markAllCapsEmphasis("this is URGENT news")
        #expect(marked.contains("<emphasis level=\"strong\">URGENT</emphasis>"), "\(marked)")
    }

    /// Two-letter capitals are usually abbreviations, not shouting.
    @Test("TXT-013: short capitals are not treated as shouting")
    func testShortCapsIgnored() {
        let marked = TextNormalizer().markAllCapsEmphasis("the US at 9 AM")
        #expect(!marked.contains("<emphasis"), "\(marked)")
    }

    @Test("TXT-013: emphasis reaches the transcription")
    func testEmphasisApplied() throws {
        let frontend = LinguisticFrontend()
        let shouted = try frontend.process("this is URGENT")
        let plain = try frontend.process("this is urgent")

        let shoutedStress = shouted.phonemes.map(\.stress).reduce(0, +)
        let plainStress = plain.phonemes.map(\.stress).reduce(0, +)
        #expect(shoutedStress > plainStress,
                "ALL-CAPS did not raise stress: \(shoutedStress) vs \(plainStress)")
    }

    @Test("TXT-013: the behaviour is configurable")
    func testConfigurable() throws {
        let off = NormalizationPolicy(treatsAllCapsAsEmphasis: false)
        let frontend = LinguisticFrontend(normalizer: TextNormalizer(policy: off))
        let transcript = try frontend.process("this is URGENT")
        #expect(!transcript.phonemes.isEmpty)
    }
}
