import Testing
@testable import Choir

/// SRS TXT-011 (MUST) — Scripture reference formats as a first-class category.
///
/// The specification's rationale is explicit: THE ONE is a primary consumer,
/// and verse references must never be spoken as "john three colon sixteen".
@Suite("SRS TXT-011 — Scripture references")
struct ScriptureNormalizationTests {
    let normalizer = TextNormalizer()

    /// The specification's own worked example.
    @Test("TXT-011: John 3:16 is spoken as book, chapter, verse")
    func testSpecExample() {
        let result = normalizer.normalize("John 3:16")
        #expect(result.contains("john"))
        #expect(result.contains("three"))
        #expect(result.contains("sixteen"))
        #expect(!result.contains(":"))
        #expect(!result.contains("colon"), "TXT-011 forbids the colon reading by default")
    }

    @Test("TXT-011: reference inside a sentence")
    func testInSentence() {
        let result = normalizer.normalize("Please turn to John 3:16 and read along.")
        #expect(result.contains("john three, sixteen"))
        #expect(result.contains("please turn to"))
        #expect(result.contains("read along"))
    }

    /// The specification names "Rom. 8:28–30" as a range example.
    @Test("TXT-011: verse ranges")
    func testVerseRange() {
        for dash in ["-", "\u{2013}", "\u{2014}"] {
            let result = normalizer.normalize("Rom. 8:28\(dash)30")
            #expect(result.contains("romans"), "dash \(dash): \(result)")
            #expect(result.contains("twenty eight"), "dash \(dash): \(result)")
            #expect(result.contains("thirty"), "dash \(dash): \(result)")
            #expect(result.contains("through"), "dash \(dash): \(result)")
        }
    }

    @Test("TXT-011: abbreviations with and without a trailing period")
    func testAbbreviations() {
        let cases = [
            ("Gen. 1:1", "genesis"),
            ("Gen 1:1", "genesis"),
            ("Ps. 23:1", "psalms"),
            ("Matt. 5:9", "matthew"),
            ("Rev. 21:4", "revelation"),
            ("Phil. 4:13", "philippians"),
            ("Heb. 11:1", "hebrews"),
        ]
        for (input, expected) in cases {
            let result = normalizer.normalize(input)
            #expect(result.contains(expected), "\(input) -> \(result)")
            #expect(!result.contains(":"), "\(input) kept a colon: \(result)")
        }
    }

    /// Numbered books must not be read as a stray digit plus a book name.
    @Test("TXT-011: numbered books are spoken as ordinals")
    func testNumberedBooks() {
        let cases = [
            ("1 John 4:8", "first john"),
            ("2 John 1:6", "second john"),
            ("3 John 1:4", "third john"),
            ("1 Cor. 13:4", "first corinthians"),
            ("2 Cor 5:17", "second corinthians"),
            ("1 Sam 16:7", "first samuel"),
            ("2 Tim 3:16", "second timothy"),
            ("1 Pet 5:7", "first peter"),
        ]
        for (input, expected) in cases {
            let result = normalizer.normalize(input)
            #expect(result.contains(expected), "\(input) -> \(result)")
        }
    }

    /// A numbered book must win over the bare book name it contains.
    @Test("TXT-011: numbered book beats the bare book name")
    func testLongestMatchWins() {
        let result = normalizer.normalize("1 John 4:8")
        #expect(result.contains("first john"))
        #expect(!result.contains("one john"), "the leading 1 was read as a number: \(result)")
    }

    @Test("TXT-011: multi-reference lists")
    func testMultipleReferences() {
        let result = normalizer.normalize("Compare Gen 1:1; John 1:1 and Col. 1:16.")
        #expect(result.contains("genesis one, one"), "\(result)")
        #expect(result.contains("john one, one"), "\(result)")
        #expect(result.contains("colossians one, sixteen"), "\(result)")
        #expect(!result.contains(":"), "\(result)")
    }

    @Test("TXT-011: multi-word book names")
    func testMultiWordBooks() {
        #expect(normalizer.normalize("Song of Solomon 2:1").contains("song of solomon"))
        #expect(normalizer.normalize("Song of Songs 2:1").contains("song of solomon"))
    }

    /// TXT-011 requires configurable style; the colon reading is offered as an
    /// explicit option even though it is forbidden as the default.
    @Test("TXT-011: style is configurable")
    func testConfigurableStyle() {
        let full = TextNormalizer(policy: NormalizationPolicy(scriptureStyle: .spokenFull))
        let fullResult = full.normalize("John 3:16")
        #expect(fullResult.contains("chapter three"), "\(fullResult)")
        #expect(fullResult.contains("verse sixteen"), "\(fullResult)")

        let colon = TextNormalizer(policy: NormalizationPolicy(scriptureStyle: .chapterColonVerse))
        #expect(colon.normalize("John 3:16").contains("colon"))

        let ranged = TextNormalizer(policy: NormalizationPolicy(scriptureStyle: .spokenFull))
        #expect(ranged.normalize("Rom 8:28-30").contains("verses"), "range should pluralize")
    }

    @Test("TXT-011: expansion can be disabled")
    func testCanBeDisabled() {
        let off = TextNormalizer(policy: NormalizationPolicy(expandsScriptureReferences: false))
        let result = off.normalize("John 3:16")
        #expect(!result.contains("john three, sixteen"), "\(result)")
    }

    /// TXT-011 requires book abbreviations for all 66 Protestant canonical books.
    @Test("TXT-011: all 66 canonical books are covered")
    func testAllBooksPresent() {
        let names = Set(ScriptureNormalizer.canonicalBookNames)
        // 66 books, but 1/2 Samuel etc. are distinct spoken names, so the set
        // of distinct spoken names is exactly the canon.
        #expect(names.count == 66, "expected 66 distinct book names, got \(names.count)")

        for expected in ["genesis", "malachi", "matthew", "revelation",
                         "first samuel", "second kings", "third john",
                         "song of solomon", "philemon", "obadiah"] {
            #expect(names.contains(expected), "missing \(expected)")
        }
    }

    /// Every book must actually resolve through the full pipeline.
    @Test("TXT-011: every canonical book resolves from its full name")
    func testEveryBookResolves() {
        for book in ScriptureNormalizer.canonicalBookNames {
            // Rebuild a written form from the spoken name.
            let written = book
                .replacingOccurrences(of: "first ", with: "1 ")
                .replacingOccurrences(of: "second ", with: "2 ")
                .replacingOccurrences(of: "third ", with: "3 ")
            let result = normalizer.normalize("\(written) 1:1")
            #expect(result.contains(book), "\(written) 1:1 -> \(result)")
        }
    }

    /// Non-references must be left alone: a bare time or ratio is not Scripture.
    @Test("TXT-011: non-Scripture colons are not treated as references")
    func testNonScriptureUntouched() {
        let result = normalizer.normalize("The ratio was 3:16 overall.")
        #expect(!result.contains("chapter"), "\(result)")
    }

    /// TXT-012: verbatim mode suppresses expansion for code and identifiers.
    @Test("TXT-012: verbatim mode leaves references unexpanded")
    func testVerbatimMode() {
        let verbatim = TextNormalizer(policy: .verbatimMode)
        let result = verbatim.normalize("John 3:16")
        #expect(!result.contains("sixteen"), "\(result)")
    }
}
