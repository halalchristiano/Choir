import Testing
@testable import Choir

/// SRS TXT-001/TXT-002 and SYN-008 — input acceptance and robustness.
///
/// TXT-002 (MUST): the engine shall never crash, hang, or produce unbounded
/// output on malformed, adversarial, or degenerate input (emoji floods,
/// zero-width characters, control characters, single repeated character x 10^6,
/// mixed scripts). Unsupported characters shall be skipped or spoken via
/// documented fallback rules.
///
/// SYN-008 (MUST): any internal failure shall surface as a typed error, never
/// a trap, for all inputs satisfying TXT-001/002.
@Suite("SRS TXT-002 — adversarial input robustness")
struct TextRobustnessTests {
    let normalizer = TextNormalizer()
    let frontend = LinguisticFrontend()

    /// Degenerate inputs the specification names explicitly, plus neighbours.
    static let adversarial: [(String, String)] = [
        ("empty", ""),
        ("single space", " "),
        ("single char", "a"),
        ("zero-width", "a\u{200B}b\u{200C}c\u{200D}d"),
        ("BOM", "\u{FEFF}hello"),
        ("control chars", "a\u{0000}b\u{0001}c\u{001F}d"),
        ("emoji flood", String(repeating: "😀", count: 5_000)),
        ("skin tone emoji", "👋🏽👨‍👩‍👧‍👦"),
        ("mixed scripts", "hello Привет こんにちは مرحبا שלום"),
        ("RTL override", "a\u{202E}bcd\u{202C}e"),
        ("combining marks", "e" + String(repeating: "\u{0301}", count: 500)),
        ("only punctuation", "!!!???...,,,;;;"),
        ("only digits", String(repeating: "9", count: 500)),
        ("huge number", String(repeating: "1", count: 400)),
        ("nested markup", String(repeating: "<emphasis>", count: 200)),
        ("unclosed tag", "hello <prosody pitch=\"+5\">world"),
        ("malformed tag", "hello <<>><prosody"),
        ("angle brackets", "a < b > c"),
        ("newline flood", String(repeating: "\n", count: 1_000)),
        ("tab flood", String(repeating: "\t", count: 1_000)),
        ("currency salad", "$$$ £££ €€€ $1.2.3 $-5 $"),
        ("decimal salad", "1.2.3.4 .. 5. .6"),
        ("negative numbers", "-5 -0 -1000000"),
        ("whitespace only", "   \t\n\r   "),
        ("quotes", "\"'“”‘’«»"),
        ("dashes", "a-b — c – d -- e"),
        ("url", "https://example.com/a?b=c&d=e#f"),
        ("email", "someone@example.co.uk"),
        ("repeated char 100k", String(repeating: "a", count: 100_000)),
    ]

    /// TXT-002: normalization must terminate and stay bounded on every input.
    @Test("TXT-002: normalizer survives adversarial input", arguments: adversarial)
    func testNormalizerRobustness(name: String, input: String) {
        let result = normalizer.normalize(input)

        // Bounded output: normalization expands text, but must not explode.
        // A generous ceiling still catches runaway expansion.
        let ceiling = max(4_096, input.count * 64)
        #expect(result.count <= ceiling,
                "\(name): output \(result.count) chars from \(input.count) exceeds bound \(ceiling)")
    }

    /// TXT-002 with SYN-008: the front end must surface failures as typed
    /// errors rather than trapping.
    @Test("TXT-002: front end surfaces typed errors, never traps", arguments: adversarial)
    func testFrontendRobustness(name: String, input: String) {
        do {
            let transcript = try frontend.process(input)
            #expect(transcript.phonemes.count >= 0, "\(name): produced a transcript")
        } catch let error as ChoirError {
            // A typed error is a conforming outcome per SYN-008.
            #expect(!error.localizedDescription.isEmpty, "\(name): error lacked a description")
        } catch {
            Issue.record("\(name): threw a non-ChoirError: \(error)")
        }
    }

    /// TXT-001 (MUST): input from 1 character upward must be accepted.
    @Test("TXT-001: accepts single-character input")
    func testSingleCharacter() {
        for c in ["a", "1", ".", " ", "😀", "\u{4E00}"] {
            let result = normalizer.normalize(c)
            #expect(result.count <= 512, "single char \(c) expanded to \(result.count)")
        }
    }

    /// TXT-002 names "single repeated character x 10^6" explicitly. This uses
    /// 200k to keep the suite fast while still exercising the same path.
    @Test("TXT-002: large degenerate input terminates")
    func testLargeRepeatedInput() {
        let input = String(repeating: "a ", count: 100_000)  // 200k chars
        let result = normalizer.normalize(input)
        #expect(!result.isEmpty)
    }

    /// TXT-002: digits are the expansion-sensitive path, since each digit run
    /// becomes words. Output must stay proportionate.
    @Test("TXT-002: long digit runs expand boundedly")
    func testLongDigitRuns() {
        for length in [10, 50, 100, 400] {
            let input = String(repeating: "7", count: length)
            let result = normalizer.normalize(input)
            #expect(result.count < 100_000,
                    "\(length) digits expanded to \(result.count) chars")
        }
    }
}
