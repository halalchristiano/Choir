import Testing
@testable import Choir

@Suite("Text Normalization")
struct TextNormalizerTests {
    let normalizer = TextNormalizer()

    @Test("Normalizes contractions")
    func testContractionsExpansion() {
        #expect(normalizer.normalize("don't") == "do not")
        #expect(normalizer.normalize("i'm happy") == "i am happy")
        #expect(normalizer.normalize("they're here") == "they are here")
    }

    @Test("Expands numbers")
    func testNumberExpansion() {
        let result = normalizer.normalize("I have 2 apples")
        #expect(result.contains("two"))
        #expect(!result.contains("2"))
    }

    @Test("Expands abbreviations")
    func testAbbreviationExpansion() {
        #expect(normalizer.normalize("Dr. Smith") == "doctor smith")
        #expect(normalizer.normalize("Mr. Jones") == "mister jones")
    }

    @Test("Handles currency")
    func testCurrencyExpansion() {
        let result = normalizer.normalize("It costs $50")
        #expect(result.contains("dollars"))
        #expect(!result.contains("$"))
    }

    @Test("Lowercases text")
    func testCaseNormalization() {
        #expect(normalizer.normalize("HELLO WORLD") == "hello world")
        #expect(normalizer.normalize("Hello World") == "hello world")
    }
}

@Suite("Phonemization (G2P)")
struct PhonemizerTests {
    let phonemizer = Phonemizer()

    @Test("Phonemizes dictionary words")
    func testDictionaryLookup() {
        let phonemes = phonemizer.phonemize("hello")
        #expect(phonemes.count > 0)
        #expect(phonemes[0].symbol == "h")
    }

    @Test("Handles unknown words with rules")
    func testRuleBasedG2P() {
        let phonemes = phonemizer.phonemize("cat")
        #expect(!phonemes.isEmpty)
    }

    @Test("Handles case insensitivity")
    func testCaseInsensitivity() {
        let lower = phonemizer.phonemize("hello")
        let upper = phonemizer.phonemize("HELLO")
        #expect(lower.count == upper.count)
    }

    @Test("Ignores punctuation")
    func testPunctuationHandling() {
        let withPunct = phonemizer.phonemize("hello.")
        let noPunct = phonemizer.phonemize("hello")
        #expect(withPunct.count == noPunct.count)
    }

    @Test("Handles vowel length")
    func testVowelLength() {
        let phonemes = phonemizer.phonemize("make")
        #expect(!phonemes.isEmpty)
    }
}

@Suite("Stress Assignment")
struct StressAssignerTests {
    let stressAssigner = StressAssigner()

    @Test("Assigns stress to dictionary words")
    func testKnownWordStress() {
        let phonemes = [
            Phoneme("h"),
            Phoneme("ə"),
            Phoneme("l"),
            Phoneme("oʊ"),
        ]
        let stressed = stressAssigner.assignStress(to: phonemes, for: "hello")
        // Should have primary stress
        #expect(stressed.contains { $0.stress == 1 })
    }

    @Test("Applies default stress pattern")
    func testDefaultStressPattern() {
        let phonemes = Array(repeating: Phoneme("æ"), count: 3)
        let stressed = stressAssigner.assignStress(to: phonemes, for: "unknown")
        // First syllable should have stress by default
        #expect(stressed[0].stress > 0)
    }

    @Test("Handles single syllable words")
    func testSingleSyllableStress() {
        let phonemes = [Phoneme("k"), Phoneme("æ"), Phoneme("t")]
        let stressed = stressAssigner.assignStress(to: phonemes, for: "cat")
        #expect(stressed.count == 3)
    }
}

@Suite("SSML Parsing")
struct SSMLParserTests {
    let parser = SSMLParser()

    @Test("Extracts plain text from SSML")
    func testPlainTextExtraction() {
        let ssml = "Hello <emphasis>world</emphasis>!"
        let text = parser.extractPlainText(from: ssml)
        #expect(text == "Hello world!")
    }

    @Test("Parses prosody tags")
    func testProsodyParsing() {
        let ssml = #"<prosody pitch="+5" rate="1.2">hello</prosody>"#
        let segments = parser.parse(ssml)
        #expect(!segments.isEmpty)
        #expect(segments[0].text.contains("hello"))
    }

    @Test("Parses emphasis tags")
    func testEmphasisParsing() {
        let ssml = #"<emphasis level="strong">important</emphasis>"#
        let segments = parser.parse(ssml)
        #expect(!segments.isEmpty)
        #expect(segments[0].emphasis == "strong")
    }

    @Test("Parses pause tags")
    func testPauseParsing() {
        let ssml = #"Hello<pause time="500ms" />world"#
        let segments = parser.parse(ssml)
        #expect(segments.count > 0)
    }

    @Test("Handles HTML entities")
    func testHTMLEntityHandling() {
        let ssml = "Tom &amp; Jerry"
        let text = parser.extractPlainText(from: ssml)
        #expect(text == "Tom & Jerry")
    }

    @Test("Parses pitch values")
    func testPitchValueParsing() {
        let ssml = #"<prosody pitch="+5">high</prosody>"#
        let segments = parser.parse(ssml)
        #expect(segments[0].pitch == 5)
    }

    @Test("Parses rate values")
    func testRateValueParsing() {
        let ssml = #"<prosody rate="1.5">fast</prosody>"#
        let segments = parser.parse(ssml)
        #expect(segments[0].rate == 1.5)
    }
}

@Suite("Linguistic Frontend Integration")
struct LinguisticFrontendTests {
    let frontend = LinguisticFrontend()

    @Test("Processes simple text")
    func testSimpleTextProcessing() async throws {
        let transcript = try frontend.process("Hello world")
        #expect(!transcript.phonemes.isEmpty)
        #expect(transcript.originalText == "Hello world")
    }

    @Test("Processes text with punctuation")
    func testPunctuationHandling() async throws {
        let transcript = try frontend.process("Hello, world!")
        #expect(!transcript.phonemes.isEmpty)
    }

    @Test("Handles numbers")
    func testNumberProcessing() async throws {
        let transcript = try frontend.process("I have 5 apples")
        #expect(!transcript.phonemes.isEmpty)
    }

    @Test("Processes SSML markup")
    func testSSMLProcessing() async throws {
        let ssml = "Hello <emphasis level=\"strong\">world</emphasis>"
        let transcript = try frontend.process(ssml)
        #expect(!transcript.phonemes.isEmpty)
    }

    @Test("Detects word boundaries")
    func testWordBoundaries() async throws {
        let transcript = try frontend.process("Hello world")
        #expect(transcript.wordBoundaries.count >= 1)
    }

    @Test("Generates word sequences")
    func testWordExtraction() async throws {
        let transcript = try frontend.process("Hello world")
        #expect(!transcript.words.isEmpty)
    }

    @Test("Rejects empty text")
    func testEmptyTextRejection() async throws {
        do {
            _ = try frontend.process("")
            #expect(Bool(false), "Should reject empty text")
        } catch ChoirError.textProcessingFailed {
            // Expected
        }
    }

    @Test("Handles long text")
    func testLongTextProcessing() async throws {
        let longText = "The quick brown fox jumps over the lazy dog. " +
                       "This is a test of the linguistic frontend. " +
                       "It should process multiple sentences correctly."
        let transcript = try frontend.process(longText)
        #expect(!transcript.phonemes.isEmpty)
    }

    @Test("Assigns stress to phonemes")
    func testStressAssignment() async throws {
        let transcript = try frontend.process("hello")
        // At least one phoneme should have stress
        #expect(transcript.phonemes.contains { $0.stress > 0 })
    }
}
