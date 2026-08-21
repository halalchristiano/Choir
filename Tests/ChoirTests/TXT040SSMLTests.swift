import Foundation
import Testing
@testable import Choir

/// SRS TXT-040 (MUST) — the SSML-C markup dialect.
///
/// The engine shall parse an inline XML-like dialect supporting at minimum
/// `break`, `emphasis`, `prosody`, `phoneme`, `say-as`, `voice` and `mark`.
@Suite("SRS TXT-040 — SSML-C dialect")
struct SSMLCParsingTests {
    let parser = SSMLCParser()

    private func events(_ markup: String) throws -> [SSMLEvent] {
        try parser.parse(markup).events
    }

    @Test("TXT-040: plain text passes through unchanged")
    func testPlainText() throws {
        let result = try parser.parse("Hello world")
        #expect(result.plainText == "Hello world")
        #expect(result.diagnostics.isEmpty)
    }

    @Test("TXT-040: break with an explicit time")
    func testBreakTime() throws {
        for (markup, expected) in [("<break time=\"500ms\"/>", 500.0),
                                   ("<break time=\"1.5s\"/>", 1500.0),
                                   ("<break time=\"250\"/>", 250.0)] {
            let found = try events("a\(markup)b").compactMap { event -> SSMLBreak? in
                if case .pause(let b) = event { return b }
                return nil
            }
            #expect(found.first?.resolvedMs == expected, "\(markup)")
        }
    }

    @Test("TXT-040: break strengths")
    func testBreakStrength() throws {
        for strength in SSMLBreak.Strength.allCases {
            let found = try events("a<break strength=\"\(strength.rawValue)\"/>b")
                .compactMap { event -> SSMLBreak? in
                    if case .pause(let b) = event { return b }
                    return nil
                }
            #expect(found.first?.strength == strength)
            #expect(found.first?.resolvedMs == strength.nominalMs)
        }
    }

    @Test("TXT-040: explicit time beats strength")
    func testTimeBeatsStrength() throws {
        let found = try events("<break time=\"777ms\" strength=\"weak\"/>")
            .compactMap { event -> SSMLBreak? in
                if case .pause(let b) = event { return b }
                return nil
            }
        #expect(found.first?.resolvedMs == 777)
    }

    @Test("TXT-040: emphasis levels")
    func testEmphasis() throws {
        for level in ["reduced", "moderate", "strong"] {
            let result = try parser.parse("say <emphasis level=\"\(level)\">this</emphasis> now")
            let styled = result.events.compactMap { event -> SSMLStyle? in
                if case .speech(let text, let style) = event, text.contains("this") { return style }
                return nil
            }
            #expect(styled.first?.emphasis.rawValue == level)
            #expect(result.diagnostics.isEmpty)
        }
    }

    @Test("TXT-040: prosody pitch, rate and volume")
    func testProsody() throws {
        let result = try parser.parse(
            "<prosody pitch=\"+5st\" rate=\"120%\" volume=\"+6dB\">loud</prosody>")
        let style = result.events.compactMap { event -> SSMLStyle? in
            if case .speech(_, let s) = event { return s }
            return nil
        }.first

        #expect(style?.pitchSemitones == 5)
        #expect(style?.ratePercent == 120)
        #expect(style?.volumeDb == 6)
    }

    /// The specification requires prosody to be nestable.
    @Test("TXT-040: nested prosody compounds")
    func testNestedProsody() throws {
        let result = try parser.parse(
            "<prosody pitch=\"+2st\"><prosody pitch=\"+3st\" rate=\"50%\">deep</prosody></prosody>")
        let style = result.events.compactMap { event -> SSMLStyle? in
            if case .speech(let text, let s) = event, text.contains("deep") { return s }
            return nil
        }.first

        // Pitch offsets add; rates multiply.
        #expect(style?.pitchSemitones == 5)
        #expect(style?.ratePercent == 50)
    }

    @Test("TXT-040: styling ends at the closing tag")
    func testStyleScoping() throws {
        let result = try parser.parse("plain <emphasis level=\"strong\">loud</emphasis> plain again")
        for event in result.events {
            guard case .speech(let text, let style) = event else { continue }
            if text.contains("loud") {
                #expect(style.emphasis == .strong)
            } else {
                #expect(style.emphasis == .none, "styling leaked into '\(text)'")
            }
        }
    }

    @Test("TXT-040: phoneme override")
    func testPhonemeOverride() throws {
        let result = try parser.parse("<phoneme ph=\"toh MAH toh\">tomato</phoneme>")
        let style = result.events.compactMap { event -> SSMLStyle? in
            if case .speech(_, let s) = event { return s }
            return nil
        }.first
        #expect(style?.phonemeOverride == "toh MAH toh")
    }

    @Test("TXT-040: say-as interpretations")
    func testSayAs() throws {
        for value in SSMLInterpretAs.allCases {
            let result = try parser.parse("<say-as interpret-as=\"\(value.rawValue)\">123</say-as>")
            let style = result.events.compactMap { event -> SSMLStyle? in
                if case .speech(_, let s) = event { return s }
                return nil
            }.first
            #expect(style?.interpretAs == value)
        }
    }

    /// TXT-042: `<voice>` permits multi-character dialogue in one request.
    @Test("TXT-042: voice switching mid-text")
    func testVoiceSwitching() throws {
        let result = try parser.parse(
            "<voice id=\"garrick\">Who goes there?</voice> <voice id=\"lyra\">A friend.</voice>")

        let voiced = result.events.compactMap { event -> (String, String?)? in
            if case .speech(let text, let style) = event { return (text, style.voiceID) }
            return nil
        }.filter { !$0.0.trimmingCharacters(in: .whitespaces).isEmpty }

        #expect(voiced.count >= 2, "expected two voiced segments, got \(voiced.count)")
        #expect(voiced.first?.1 == "garrick")
        #expect(voiced.last?.1 == "lyra")
    }

    @Test("TXT-040: marks are captured in order")
    func testMarks() throws {
        let result = try parser.parse("one <mark name=\"a\"/> two <mark name=\"b\"/> three")
        #expect(result.markNames == ["a", "b"])
        #expect(result.diagnostics.isEmpty)
    }

    @Test("TXT-040: attributes tolerate single quotes and spacing")
    func testAttributeForms() throws {
        for markup in ["<mark name='x'/>", "<mark  name = \"x\" />", "<mark name=x/>"] {
            let result = try parser.parse(markup)
            #expect(result.markNames == ["x"], "\(markup)")
        }
    }
}

/// SRS TXT-041 (MUST) — graceful degradation and diagnostics.
///
/// "Malformed markup shall degrade gracefully: unparseable tags are stripped
/// and their text content spoken, a diagnostics list of markup warnings shall
/// be returned with the result, and strict mode (throwing on malformed markup)
/// shall be available."
@Suite("SRS TXT-041 — markup degradation")
struct SSMLDegradationTests {
    let lenient = SSMLCParser()
    let strict = SSMLCParser(strict: true)

    @Test("TXT-041: unknown tags are stripped but their text is spoken")
    func testUnknownTagStripped() throws {
        let result = try lenient.parse("keep <bogus>this text</bogus> please")
        #expect(result.plainText.contains("this text"))
        #expect(!result.plainText.contains("bogus"))
        #expect(!result.diagnostics.isEmpty, "no diagnostic recorded")
    }

    @Test("TXT-041: unclosed tags are tolerated")
    func testUnclosedTag() throws {
        let result = try lenient.parse("start <emphasis level=\"strong\">never closed")
        #expect(result.plainText.contains("never closed"))
        #expect(result.diagnostics.contains { $0.message.contains("Unclosed") })
    }

    @Test("TXT-041: stray closing tags are tolerated")
    func testStrayClosingTag() throws {
        let result = try lenient.parse("text </emphasis> more")
        #expect(result.plainText.contains("more"))
        #expect(!result.diagnostics.isEmpty)
    }

    @Test("TXT-041: an unterminated tag is spoken as text")
    func testUnterminatedTag() throws {
        let result = try lenient.parse("a < b and c")
        #expect(result.plainText.contains("b and c"))
        #expect(!result.diagnostics.isEmpty)
    }

    @Test("TXT-041: unparseable attribute values are reported, not fatal")
    func testBadAttributeValue() throws {
        let result = try lenient.parse("<prosody rate=\"fast-ish\">text</prosody>")
        #expect(result.plainText.contains("text"))
        #expect(result.diagnostics.contains { $0.message.contains("rate") })
    }

    @Test("TXT-041: mark without a name is reported")
    func testMarkWithoutName() throws {
        let result = try lenient.parse("a <mark/> b")
        #expect(result.markNames.isEmpty)
        #expect(!result.diagnostics.isEmpty)
    }

    @Test("TXT-041: strict mode throws on malformed markup")
    func testStrictModeThrows() throws {
        let malformed = [
            "keep <bogus>this</bogus>",
            "start <emphasis level=\"strong\">never closed",
            "text </emphasis> more",
            "<prosody rate=\"fast-ish\">text</prosody>",
            "a <mark/> b",
        ]
        for markup in malformed {
            #expect(throws: ChoirError.self, "should have thrown for \(markup)") {
                _ = try strict.parse(markup)
            }
        }
    }

    @Test("TXT-041: strict mode accepts well-formed markup")
    func testStrictModeAcceptsValid() throws {
        let result = try strict.parse(
            "<prosody pitch=\"+2st\">hello <emphasis level=\"strong\">there</emphasis></prosody><break time=\"200ms\"/>")
        #expect(result.diagnostics.isEmpty)
        #expect(result.plainText.contains("hello"))
    }

    /// TXT-002 still applies to the markup path.
    @Test("TXT-041: adversarial markup terminates")
    func testAdversarialMarkup() throws {
        let inputs = [
            String(repeating: "<emphasis>", count: 500),
            String(repeating: "</emphasis>", count: 500),
            String(repeating: "<", count: 1000),
            "<<<>>>",
            "<prosody " + String(repeating: "a=\"b\" ", count: 500) + ">x</prosody>",
        ]
        for input in inputs {
            let result = try lenient.parse(input)
            #expect(result.events.count < 10_000)
        }
    }
}

/// SYN-005 marks and diagnostics, now that TXT-040/041 supply them.
@Suite("SRS SYN-005 — marks and diagnostics")
struct SynthesisMarkTests {

    private func metadata(for text: String) throws -> SynthesisMetadata {
        let transcript = try LinguisticFrontend().process(text)
        let durations = Array(repeating: 50.0, count: transcript.phonemes.count)
        let markup = try SSMLCParser().parse(text)
        return SynthesisPipeline.buildMetadata(
            transcript: transcript,
            durationsMs: durations,
            audio: AudioBuffer(samples: [], format: AudioFormat()),
            voice: .isla,
            parameters: SynthesisParameters(),
            markup: markup
        )
    }

    @Test("SYN-005: mark positions are reported with times")
    func testMarkPositions() throws {
        let meta = try metadata(for: "one two <mark name=\"here\"/> three four")
        #expect(meta.marks.count == 1)
        #expect(meta.marks.first?.name == "here")
        #expect(meta.time(ofMark: "here") != nil)
        #expect(meta.time(ofMark: "absent") == nil)
    }

    @Test("SYN-005: marks are ordered by time")
    func testMarkOrdering() throws {
        let meta = try metadata(for: "a <mark name=\"one\"/> b <mark name=\"two\"/> c")
        #expect(meta.marks.map(\.name) == ["one", "two"])
        if meta.marks.count == 2 {
            #expect(meta.marks[0].timeMs <= meta.marks[1].timeMs)
        }
    }

    @Test("SYN-005: markup diagnostics reach the metadata")
    func testDiagnosticsPropagate() throws {
        let meta = try metadata(for: "text <bogus>here</bogus>")
        #expect(!meta.diagnostics.isEmpty, "diagnostics did not reach metadata")
    }

    @Test("SYN-005: clean input produces no diagnostics")
    func testCleanInput() throws {
        let meta = try metadata(for: "Hello world.")
        #expect(meta.diagnostics.isEmpty)
        #expect(meta.marks.isEmpty)
    }
}
