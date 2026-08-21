import Foundation
import Testing
@testable import Choir

/// SRS TXT-024 (MUST) — documented, stable phoneme inventory.
@Suite("SRS TXT-024 — phoneme inventory")
struct PhonemeInventoryTests {

    @Test("TXT-024: the inventory is the 39 ARPAbet phonemes")
    func testInventorySize() {
        #expect(PhonemeInventory.all.count == 39)
        #expect(PhonemeInventory.vowels.count == 15)
        #expect(PhonemeInventory.consonants.count == 24)
    }

    @Test("TXT-024: ARPAbet and IPA symbols are unique")
    func testSymbolsUnique() {
        let arpabet = PhonemeInventory.all.map(\.arpabet)
        let ipa = PhonemeInventory.all.map(\.ipa)
        #expect(Set(arpabet).count == arpabet.count)
        #expect(Set(ipa).count == ipa.count)
    }

    @Test("TXT-024: the mapping round-trips both ways")
    func testMappingRoundTrip() {
        for entry in PhonemeInventory.all {
            #expect(PhonemeInventory.ipa(forARPAbet: entry.arpabet) == entry.ipa)
            #expect(PhonemeInventory.arpabet(forIPA: entry.ipa) == entry.arpabet)
        }
    }

    @Test("TXT-024: stress digits are stripped and reported")
    func testStressParsing() {
        #expect(PhonemeInventory.stripStress("AA1").symbol == "AA")
        #expect(PhonemeInventory.stripStress("AA1").stress == .primary)
        #expect(PhonemeInventory.stripStress("AA2").stress == .secondary)
        #expect(PhonemeInventory.stripStress("AA0").stress == .none)
        #expect(PhonemeInventory.stripStress("K").stress == .none)
        #expect(PhonemeInventory.stripStress("K").symbol == "K")
    }

    @Test("TXT-024: stress applies only where CMUdict marks it")
    func testStressCarriedThrough() {
        let phonemes = PhonemeInventory.phonemes(fromARPAbet: "HH AH0 L OW1")
        #expect(phonemes.count == 4)
        #expect(phonemes[3].stress == StressLevel.primary.rawValue)
        #expect(phonemes[0].stress == StressLevel.none.rawValue)
    }

    @Test("TXT-024: unknown symbols are skipped, not fatal")
    func testUnknownSymbolsSkipped() {
        let phonemes = PhonemeInventory.phonemes(fromARPAbet: "HH QQ AH0 ZZZ")
        #expect(phonemes.count == 2, "expected the two valid symbols")
    }

    @Test("TXT-024: IPA validation gates the pre-phonemized path")
    func testValidation() {
        #expect(PhonemeInventory.isValidIPA("ɑ"))
        #expect(PhonemeInventory.isValidIPA("tʃ"))
        #expect(!PhonemeInventory.isValidIPA("Q"))
        #expect(PhonemeInventory.isVowel(ipa: "ɑ"))
        #expect(!PhonemeInventory.isVowel(ipa: "k"))
    }

    @Test("TXT-024: the mapping table is publishable")
    func testMappingTable() {
        let table = PhonemeInventory.mappingTable
        #expect(table.contains("ARPAbet"))
        #expect(table.contains("AA"))
        #expect(table.contains("ZH"))
        // One header, one separator, 39 rows.
        #expect(table.split(separator: "\n").count == 41)
    }
}

/// SRS TXT-020 (MUST) — built-in pronunciation lexicon.
///
/// "The front end shall include a built-in pronunciation lexicon of at least
/// 120,000 English word forms with primary/secondary stress."
@Suite("SRS TXT-020 — built-in lexicon")
struct BuiltInLexiconTests {

    @Test("TXT-020: at least 120,000 word forms")
    func testLexiconSize() {
        let count = BuiltInLexicon.shared.count
        #expect(count >= 120_000, "lexicon has only \(count) entries")
    }

    @Test("TXT-020: common words resolve")
    func testCommonWords() {
        for word in ["hello", "world", "the", "synthesis", "voice", "scripture"] {
            let phonemes = BuiltInLexicon.shared.phonemes(for: word)
            #expect(phonemes?.isEmpty == false, "no pronunciation for \(word)")
        }
    }

    @Test("TXT-020: lookup is case-insensitive")
    func testCaseInsensitive() {
        let lower = BuiltInLexicon.shared.phonemes(for: "hello")
        let upper = BuiltInLexicon.shared.phonemes(for: "HELLO")
        #expect(lower?.map(\.symbol) == upper?.map(\.symbol))
    }

    @Test("TXT-020: entries carry primary and secondary stress")
    func testStressPresent() {
        // "elaborate" carries both a primary and a secondary stress.
        guard let phonemes = BuiltInLexicon.shared.phonemes(for: "elaborate") else {
            Issue.record("elaborate missing from lexicon")
            return
        }
        let stresses = Set(phonemes.map(\.stress))
        #expect(stresses.contains(StressLevel.primary.rawValue), "no primary stress")

        // Across a sample of long words, secondary stress must appear somewhere.
        var sawSecondary = false
        for word in ["elaborate", "understand", "celebration", "organization", "necessary"] {
            if let p = BuiltInLexicon.shared.phonemes(for: word),
               p.contains(where: { $0.stress == StressLevel.secondary.rawValue }) {
                sawSecondary = true
                break
            }
        }
        #expect(sawSecondary, "no secondary stress anywhere in the sample")
    }

    @Test("TXT-020: unknown words return nil rather than guessing")
    func testUnknownWord() {
        #expect(BuiltInLexicon.shared.phonemes(for: "zzzqqqxxnotaword") == nil)
    }

    @Test("TXT-020: every produced symbol is in the documented inventory")
    func testSymbolsAreInInventory() {
        for word in ["hello", "world", "beautiful", "synthesis", "question", "measure"] {
            guard let phonemes = BuiltInLexicon.shared.phonemes(for: word) else { continue }
            for phoneme in phonemes {
                #expect(PhonemeInventory.isValidIPA(phoneme.symbol),
                        "\(word): '\(phoneme.symbol)' is outside the inventory")
            }
        }
    }

    @Test("TXT-020: variant spellings are not indexed as words")
    func testVariantsExcluded() {
        #expect(BuiltInLexicon.shared.arpabet(for: "read(2)") == nil)
    }

    @Test("TXT-020: an injected lexicon is usable for testing")
    func testInjectedLexicon() {
        let lexicon = BuiltInLexicon(entries: ["frobnicate": "F R AA1 B N IH0 K EY2 T"])
        #expect(lexicon.count == 1)
        let phonemes = lexicon.phonemes(for: "Frobnicate")
        #expect(phonemes?.isEmpty == false)
    }

    @Test("TXT-020: the phonemizer prefers the lexicon over rules")
    func testPhonemizerUsesLexicon() {
        let withLexicon = Phonemizer().phonemize("colonel")
        let rulesOnly = Phonemizer(builtInLexicon: nil).phonemize("colonel")

        // "colonel" is pronounced "kernel"; no letter-to-sound rule finds that.
        #expect(withLexicon.map(\.symbol) != rulesOnly.map(\.symbol),
                "the lexicon made no difference for an irregular word")
    }
}

/// SRS TXT-021 (MUST) — heteronym disambiguation.
@Suite("SRS TXT-021 — heteronyms")
struct HeteronymTests {
    let resolver = HeteronymResolver()

    /// TXT-021 requires "at minimum a documented list of >= 60 heteronyms".
    @Test("TXT-021: at least 60 documented heteronyms")
    func testCount() {
        #expect(HeteronymResolver.words.count >= 60,
                "only \(HeteronymResolver.words.count) heteronyms")
    }

    /// Every word the specification names must be covered.
    @Test("TXT-021: the words named in the requirement are present")
    func testNamedWords() {
        for word in ["read", "lead", "tear", "bass", "bow", "wind",
                     "live", "wound", "minute", "row"] {
            #expect(resolver.isHeteronym(word), "missing \(word)")
        }
    }

    @Test("TXT-021: part of speech changes the pronunciation")
    func testDisambiguation() {
        for word in ["read", "lead", "tear", "wind", "live", "wound",
                     "record", "present", "object", "subject"] {
            let noun = resolver.arpabet(for: word, partOfSpeech: .noun)
            let verb = resolver.arpabet(for: word, partOfSpeech: .verb)
            #expect(noun != nil && verb != nil, "\(word) missing a reading")
            #expect(noun != verb, "\(word) reads identically as noun and verb")
        }
    }

    @Test("TXT-021: the phonemizer honours part of speech")
    func testPhonemizerDisambiguates() {
        let asNoun = Phonemizer().phonemize("record", partOfSpeech: .noun)
        let asVerb = Phonemizer().phonemize("record", partOfSpeech: .verb)
        #expect(asNoun.map(\.symbol) != asVerb.map(\.symbol) ||
                asNoun.map(\.stress) != asVerb.map(\.stress),
                "record sounded the same as noun and verb")
    }

    @Test("TXT-021: unknown part of speech falls back to the nominal reading")
    func testUnknownFallsBack() {
        let unknown = resolver.phonemes(for: "record", partOfSpeech: .unknown)
        let noun = resolver.phonemes(for: "record", partOfSpeech: .noun)
        #expect(unknown?.map(\.symbol) == noun?.map(\.symbol))
    }

    @Test("TXT-021: non-heteronyms are not claimed")
    func testNonHeteronym() {
        #expect(!resolver.isHeteronym("hello"))
        #expect(resolver.phonemes(for: "hello", partOfSpeech: .noun) == nil)
    }

    @Test("TXT-021: every reading uses inventory symbols")
    func testReadingsValid() {
        for word in HeteronymResolver.words {
            for pos in [PartOfSpeech.noun, .verb] {
                guard let phonemes = resolver.phonemes(for: word, partOfSpeech: pos) else {
                    Issue.record("\(word) has no \(pos) reading")
                    continue
                }
                #expect(!phonemes.isEmpty, "\(word)/\(pos) produced nothing")
                for phoneme in phonemes {
                    #expect(PhonemeInventory.isValidIPA(phoneme.symbol),
                            "\(word)/\(pos): '\(phoneme.symbol)' outside the inventory")
                }
            }
        }
    }

    @Test("TXT-021: the user lexicon still wins over heteronyms")
    func testUserLexiconPrecedence() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "record", phonemes: ["z", "æ", "p"])
        let snapshot = await lexicon.snapshot()

        let result = Phonemizer(userLexicon: snapshot)
            .phonemize("record", partOfSpeech: .verb)
        #expect(result.map(\.symbol) == ["z", "æ", "p"])
    }
}

/// SRS TXT-023 (SHOULD) — biblical and theological proper-noun supplement.
///
/// The requirement asks for at least 2,500 entries; this is a partial
/// supplement. These tests pin what it does cover, and in particular the
/// interaction with TXT-011 that motivated it.
@Suite("SRS TXT-023 — theological supplement")
struct TheologicalLexiconTests {

    @Test("TXT-023: the supplement is loaded and non-trivial")
    func testSupplementPresent() {
        #expect(TheologicalLexicon.count >= 100)
    }

    /// Every book name ScriptureNormalizer can emit must be pronounceable,
    /// or TXT-011's expansion hands the phonemizer a word it must guess at.
    @Test("TXT-023: every canonical book name resolves in the lexicon")
    func testBookNamesResolve() {
        let lexicon = BuiltInLexicon.shared
        for spoken in ScriptureNormalizer.canonicalBookNames {
            // Ordinal prefixes are ordinary words; check the book word itself.
            let bookWord = spoken
                .replacingOccurrences(of: "first ", with: "")
                .replacingOccurrences(of: "second ", with: "")
                .replacingOccurrences(of: "third ", with: "")

            for word in bookWord.split(separator: " ") {
                #expect(lexicon.contains(String(word)),
                        "'\(word)' from book '\(spoken)' is not in the lexicon")
            }
        }
    }

    /// The specific gap that prompted the supplement.
    @Test("TXT-023: names CMUdict lacks are now covered")
    func testGapsCovered() {
        let lexicon = BuiltInLexicon.shared
        for word in ["ecclesiastes", "deuteronomy", "thessalonians", "habakkuk",
                     "zephaniah", "athanasius", "socinus", "crellius",
                     "nebuchadnezzar", "septuagint", "tetragrammaton"] {
            #expect(lexicon.contains(word), "missing \(word)")
        }
    }

    @Test("TXT-023: supplement pronunciations use inventory symbols")
    func testSupplementSymbolsValid() {
        for (word, arpabet) in TheologicalLexicon.entries {
            let phonemes = PhonemeInventory.phonemes(fromARPAbet: arpabet)
            #expect(!phonemes.isEmpty, "\(word) produced no phonemes")

            let tokens = arpabet.split(separator: " ").count
            #expect(phonemes.count == tokens,
                    "\(word): \(tokens - phonemes.count) symbol(s) outside the inventory")
        }
    }

    @Test("TXT-023: the supplement overrides CMUdict where both have a word")
    func testSupplementPrecedence() {
        // "melchizedek" is in both; the curated reading must win.
        let arpabet = BuiltInLexicon.shared.arpabet(for: "melchizedek")
        #expect(arpabet == TheologicalLexicon.entries["melchizedek"])
    }

    /// End to end: a Scripture reference expands and every word phonemizes
    /// from the lexicon rather than by rule.
    @Test("TXT-011 + TXT-023: expanded references are fully pronounceable")
    func testScriptureEndToEnd() {
        let normalizer = TextNormalizer()
        let lexicon = BuiltInLexicon.shared

        for reference in ["Eccl. 3:1", "Deut. 6:5", "1 Thess. 5:16", "Hab. 2:4", "Zeph. 3:17"] {
            let spoken = normalizer.normalize(reference)
            for word in spoken.split(whereSeparator: { $0 == " " || $0 == "," }) {
                let cleaned = String(word).trimmingCharacters(in: .punctuationCharacters)
                guard !cleaned.isEmpty else { continue }
                #expect(lexicon.contains(cleaned),
                        "'\(cleaned)' from '\(reference)' -> '\(spoken)' is not in the lexicon")
            }
        }
    }
}
