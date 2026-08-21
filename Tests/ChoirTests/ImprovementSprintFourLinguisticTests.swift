import Foundation
import Testing
@testable import Choir

@Suite("Fourth improvement sprint: text normalization")
struct ImprovementSprintFourTextNormalizerTests {
    let normalizer = TextNormalizer()

    @Test("351: Normalizer configuration is a codable hashable value")
    func normalizerValueSemantics() throws {
        let value = TextNormalizer(policy: NormalizationPolicy(
            expandsScriptureReferences: false,
            scriptureStyle: .spokenFull,
            treatsAllCapsAsEmphasis: false
        ))
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(TextNormalizer.self, from: data)
        #expect(decoded == value)
        #expect(Set([value, decoded]).count == 1)
    }

    @Test("352: Unicode whitespace collapses in prose and verbatim modes")
    func unicodeWhitespace() {
        let input = "  Alpha\t\n\u{2003}\u{2028}Beta  "
        #expect(normalizer.normalize(input) == "alpha beta")
        #expect(TextNormalizer(policy: .verbatimMode).normalize(input) == "alpha beta")
    }

    @Test("353: Contractions expand only at lexical boundaries")
    func contractionBoundaries() {
        #expect(normalizer.normalize("D'Artagnan said don't.") == "d'artagnan said do not.")
    }

    @Test("354: Abbreviations expand only at lexical boundaries")
    func abbreviationBoundaries() {
        #expect(normalizer.normalize("co.operative with Co.") == "co.operative with company")
    }

    @Test("355: One dollar uses singular grammar")
    func singularDollar() {
        #expect(normalizer.normalize("$1 and $2") == "one dollar and two dollars")
    }

    @Test("356: Fractional currency is spoken as dollars and cents")
    func currencyCents() {
        let result = normalizer.normalize("$1.01 and $0.50")
        #expect(result == "one dollar and one cent and fifty cents")
    }

    @Test("357: Currency accepts canonical thousands separators")
    func groupedCurrency() {
        #expect(normalizer.normalize("$1,234.56")
            == "one thousand two hundred thirty four dollars and fifty six cents")
    }

    @Test("358: Currency accepts signs before or after the dollar symbol")
    func signedCurrency() {
        #expect(normalizer.normalize("-$5.25 and $-2")
            == "minus five dollars and twenty five cents and minus two dollars")
    }
}

@Suite("Fourth improvement sprint: Scripture normalization")
struct ImprovementSprintFourScriptureTests {
    let normalizer = ScriptureNormalizer()

    @Test("359: Scripture references are validated canonical codable values")
    func scriptureReferenceValue() throws {
        guard let value = ScriptureReference(book: "1 Jn.", chapter: 4, verse: 8) else {
            Issue.record("Expected a valid reference")
            return
        }
        #expect(value.book == "first john")
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(ScriptureReference.self, from: data) == value)
    }

    @Test("360: Structured references are extracted in source order")
    func orderedExtraction() {
        let values = normalizer.references(in: "Compare Gen 1:1 with Rev. 21:4.")
        #expect(values.map(\.book) == ["genesis", "revelation"])
        #expect(values.map(\.chapter) == [1, 21])
    }

    @Test("361: Validated references have a public spoken renderer")
    func publicRenderer() {
        guard let value = ScriptureReference(
            book: "Romans", chapter: 8, verse: 28, verseEnd: 30
        ) else {
            Issue.record("Expected a valid reference")
            return
        }
        #expect(ScriptureNormalizer(style: .spokenFull).spoken(value)
            == "romans chapter eight, verses twenty eight through thirty")
    }

    @Test("362: References permit whitespace around the colon")
    func colonWhitespace() {
        #expect(normalizer.normalize("John 3 : 16") == "john three, sixteen")
    }

    @Test("363: References accept the fullwidth colon")
    func fullwidthColon() {
        #expect(TextNormalizer().normalize("John 3：16") == "john three, sixteen")
    }

    @Test("364: Enclosing punctuation survives reference expansion")
    func enclosingPunctuation() {
        #expect(normalizer.normalize("(John 3:16)") == "(john three, sixteen)")
    }

    @Test("365: Chapter and verse zero are rejected")
    func rejectZeroValues() {
        #expect(ScriptureReference(book: "John", chapter: 0, verse: 1) == nil)
        #expect(ScriptureReference(book: "John", chapter: 1, verse: 0) == nil)
    }

    @Test("366: Chapters cannot exceed the selected canonical book")
    func canonicalChapterCeilings() {
        #expect(ScriptureReference(book: "Jude", chapter: 2, verse: 1) == nil)
        #expect(ScriptureReference(book: "Psalms", chapter: 150, verse: 6) != nil)
    }

    @Test("367: Verse values respect the canon-wide maximum")
    func canonicalVerseCeiling() {
        #expect(ScriptureReference(book: "Psalm", chapter: 119, verse: 176) != nil)
        #expect(ScriptureReference(book: "Psalm", chapter: 119, verse: 177) == nil)
    }

    @Test("368: Descending verse ranges are rejected intact")
    func descendingRange() {
        #expect(ScriptureReference(book: "John", chapter: 3, verse: 16, verseEnd: 12) == nil)
        #expect(normalizer.normalize("John 3:16-12") == "John 3:16-12")
    }
}

@Suite("Fourth improvement sprint: stress assignment")
struct ImprovementSprintFourStressTests {
    @Test("369: Lexical patterns target vowel nuclei")
    func vowelNucleusPatterns() {
        let phonemes = [Phoneme("h"), Phoneme("ə"), Phoneme("l"), Phoneme("oʊ")]
        #expect(StressAssigner().assignStress(to: phonemes, for: "hello").map(\.stress)
            == [0, 0, 0, 1])
    }

    @Test("370: Rule fallback never stresses consonants")
    func consonantsRemainUnstressed() {
        let phonemes = [Phoneme("k", stress: 2), Phoneme("æ"), Phoneme("t", stress: 2), Phoneme("ə")]
        #expect(StressAssigner().assignStress(to: phonemes, for: "unknown").map(\.stress)
            == [0, 1, 0, 0])
    }

    @Test("371: Custom stress levels clamp to the supported range")
    func customStressClamps() {
        let assigner = StressAssigner(patterns: ["sample": [-5, 9]])
        let result = assigner.assignStress(to: [Phoneme("æ"), Phoneme("ə")], for: "sample")
        #expect(result.map(\.stress) == [0, 2])
    }

    @Test("372: Pattern keys and lookup words normalize consistently")
    func normalizedPatternLookup() {
        let assigner = StressAssigner(patterns: ["  HELLO! ": [0, 1]])
        let phonemes = [Phoneme("ə"), Phoneme("oʊ")]
        #expect(assigner.assignStress(to: phonemes, for: "(hello)").map(\.stress) == [0, 1])
    }

    @Test("373: Explicit vowel stress survives while consonant stress is repaired")
    func preserveAuthoritativeVowelStress() {
        let phonemes = [
            Phoneme("k", stress: 2), Phoneme("æ", stress: 2),
            Phoneme("t", stress: 1), Phoneme("ə"),
        ]
        #expect(StressAssigner().assignStress(to: phonemes, for: "cat").map(\.stress)
            == [0, 2, 0, 0])
    }

    @Test("374: Empty custom patterns fall back to the default rule")
    func emptyPatternFallsBack() {
        let assigner = StressAssigner(patterns: ["mystery": []])
        let result = assigner.assignStress(
            to: [Phoneme("m"), Phoneme("ə"), Phoneme("s")], for: "mystery")
        #expect(result.map(\.stress) == [0, 1, 0])
    }

    @Test("375: Sanitized stress patterns are publicly inspectable")
    func inspectPattern() {
        #expect(StressAssigner().stressPattern(for: "HELLO!") == [0, 1])
    }
}
