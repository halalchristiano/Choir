import Foundation

/// Coarse part-of-speech categories used for heteronym disambiguation.
public enum PartOfSpeech: String, Sendable, Equatable, Codable, CaseIterable {
    case noun
    case verb
    case adjective
    case adverb
    case unknown
}

/// Resolves heteronyms — words spelled alike but pronounced differently
/// depending on part of speech (SRS TXT-021).
///
/// "The G2P system shall correctly disambiguate common heteronyms by
/// part-of-speech context ("read", "lead", "tear", "bass", "bow", "wind",
/// "live", "wound", "minute", "row", at minimum a documented list of ≥ 60
/// heteronyms)."
///
/// Pronunciations are given in ARPAbet, matching the built-in lexicon, and
/// converted through ``PhonemeInventory``.
public struct HeteronymResolver: Sendable {

    /// One heteronym and its part-of-speech-conditioned pronunciations.
    public struct Entry: Sendable, Equatable {
        public let word: String

        /// Pronunciation when used as a noun or adjective, in ARPAbet.
        public let nominal: String

        /// Pronunciation when used as a verb, in ARPAbet.
        public let verbal: String

        public init(word: String, nominal: String, verbal: String) {
            self.word = word
            self.nominal = nominal
            self.verbal = verbal
        }
    }

    /// The documented heteronym list.
    ///
    /// Every word the specification names is present. Most English heteronyms
    /// split along a noun/adjective versus verb axis — often by stress, as in
    /// REcord versus reCORD — so entries are keyed that way.
    public static let entries: [Entry] = [
        // Named explicitly in TXT-021
        Entry(word: "read",     nominal: "R EH1 D",            verbal: "R IY1 D"),
        Entry(word: "lead",     nominal: "L EH1 D",            verbal: "L IY1 D"),
        Entry(word: "tear",     nominal: "T IH1 R",            verbal: "T EH1 R"),
        Entry(word: "bass",     nominal: "B EY1 S",            verbal: "B EY1 S"),
        Entry(word: "bow",      nominal: "B OW1",              verbal: "B AW1"),
        Entry(word: "wind",     nominal: "W IH1 N D",          verbal: "W AY1 N D"),
        Entry(word: "live",     nominal: "L AY1 V",            verbal: "L IH1 V"),
        Entry(word: "wound",    nominal: "W UW1 N D",          verbal: "W AW1 N D"),
        Entry(word: "minute",   nominal: "M IH1 N AH0 T",      verbal: "M AY0 N UW1 T"),
        Entry(word: "row",      nominal: "R OW1",              verbal: "R OW1"),

        // Noun-initial-stress versus verb-final-stress pairs
        Entry(word: "record",   nominal: "R EH1 K ER0 D",      verbal: "R IH0 K AO1 R D"),
        Entry(word: "present",  nominal: "P R EH1 Z AH0 N T",  verbal: "P R IH0 Z EH1 N T"),
        Entry(word: "object",   nominal: "AA1 B JH EH0 K T",   verbal: "AH0 B JH EH1 K T"),
        Entry(word: "subject",  nominal: "S AH1 B JH IH0 K T", verbal: "S AH0 B JH EH1 K T"),
        Entry(word: "project",  nominal: "P R AA1 JH EH0 K T", verbal: "P R AH0 JH EH1 K T"),
        Entry(word: "contract", nominal: "K AA1 N T R AE0 K T", verbal: "K AH0 N T R AE1 K T"),
        Entry(word: "conflict", nominal: "K AA1 N F L IH0 K T", verbal: "K AH0 N F L IH1 K T"),
        Entry(word: "convert",  nominal: "K AA1 N V ER0 T",    verbal: "K AH0 N V ER1 T"),
        Entry(word: "convict",  nominal: "K AA1 N V IH0 K T",  verbal: "K AH0 N V IH1 K T"),
        Entry(word: "produce",  nominal: "P R OW1 D UW0 S",    verbal: "P R AH0 D UW1 S"),
        Entry(word: "progress", nominal: "P R AA1 G R EH0 S",  verbal: "P R AH0 G R EH1 S"),
        Entry(word: "protest",  nominal: "P R OW1 T EH0 S T",  verbal: "P R AH0 T EH1 S T"),
        Entry(word: "rebel",    nominal: "R EH1 B AH0 L",      verbal: "R IH0 B EH1 L"),
        Entry(word: "refuse",   nominal: "R EH1 F Y UW0 S",    verbal: "R IH0 F Y UW1 Z"),
        Entry(word: "reject",   nominal: "R IY1 JH EH0 K T",   verbal: "R IH0 JH EH1 K T"),
        Entry(word: "permit",   nominal: "P ER1 M IH0 T",      verbal: "P ER0 M IH1 T"),
        Entry(word: "insult",   nominal: "IH1 N S AH0 L T",    verbal: "IH0 N S AH1 L T"),
        Entry(word: "increase", nominal: "IH1 N K R IY0 S",    verbal: "IH0 N K R IY1 S"),
        Entry(word: "decrease", nominal: "D IY1 K R IY0 S",    verbal: "D IH0 K R IY1 S"),
        Entry(word: "conduct",  nominal: "K AA1 N D AH0 K T",  verbal: "K AH0 N D AH1 K T"),
        Entry(word: "console",  nominal: "K AA1 N S OW0 L",    verbal: "K AH0 N S OW1 L"),
        Entry(word: "content",  nominal: "K AA1 N T EH0 N T",  verbal: "K AH0 N T EH1 N T"),
        Entry(word: "contest",  nominal: "K AA1 N T EH0 S T",  verbal: "K AH0 N T EH1 S T"),
        Entry(word: "contrast", nominal: "K AA1 N T R AE0 S T", verbal: "K AH0 N T R AE1 S T"),
        Entry(word: "digest",   nominal: "D AY1 JH EH0 S T",   verbal: "D AY0 JH EH1 S T"),
        Entry(word: "escort",   nominal: "EH1 S K AO0 R T",    verbal: "IH0 S K AO1 R T"),
        Entry(word: "export",   nominal: "EH1 K S P AO0 R T",  verbal: "IH0 K S P AO1 R T"),
        Entry(word: "import",   nominal: "IH1 M P AO0 R T",    verbal: "IH0 M P AO1 R T"),
        Entry(word: "impact",   nominal: "IH1 M P AE0 K T",    verbal: "IH0 M P AE1 K T"),
        Entry(word: "incline",  nominal: "IH1 N K L AY0 N",    verbal: "IH0 N K L AY1 N"),
        Entry(word: "invalid",  nominal: "IH1 N V AH0 L IH0 D", verbal: "IH0 N V AE1 L IH0 D"),
        Entry(word: "perfect",  nominal: "P ER1 F IH0 K T",    verbal: "P ER0 F EH1 K T"),
        Entry(word: "pervert",  nominal: "P ER1 V ER0 T",      verbal: "P ER0 V ER1 T"),
        Entry(word: "rerun",    nominal: "R IY1 R AH0 N",      verbal: "R IY0 R AH1 N"),
        Entry(word: "research", nominal: "R IY1 S ER0 CH",     verbal: "R IH0 S ER1 CH"),
        Entry(word: "survey",   nominal: "S ER1 V EY0",        verbal: "S ER0 V EY1"),
        Entry(word: "suspect",  nominal: "S AH1 S P EH0 K T",  verbal: "S AH0 S P EH1 K T"),
        Entry(word: "transfer", nominal: "T R AE1 N S F ER0",  verbal: "T R AE0 N S F ER1"),
        Entry(word: "transport", nominal: "T R AE1 N S P AO0 R T", verbal: "T R AE0 N S P AO1 R T"),
        Entry(word: "upset",    nominal: "AH1 P S EH0 T",      verbal: "AH0 P S EH1 T"),
        Entry(word: "address",  nominal: "AE1 D R EH0 S",      verbal: "AH0 D R EH1 S"),
        Entry(word: "affect",   nominal: "AE1 F EH0 K T",      verbal: "AH0 F EH1 K T"),
        Entry(word: "combine",  nominal: "K AA1 M B AY0 N",    verbal: "K AH0 M B AY1 N"),
        Entry(word: "compound", nominal: "K AA1 M P AW0 N D",  verbal: "K AH0 M P AW1 N D"),
        Entry(word: "compress", nominal: "K AA1 M P R EH0 S",  verbal: "K AH0 M P R EH1 S"),
        Entry(word: "default",  nominal: "D IY1 F AO0 L T",    verbal: "D IH0 F AO1 L T"),
        Entry(word: "desert",   nominal: "D EH1 Z ER0 T",      verbal: "D IH0 Z ER1 T"),
        Entry(word: "discount", nominal: "D IH1 S K AW0 N T",  verbal: "D IH0 S K AW1 N T"),
        Entry(word: "entrance", nominal: "EH1 N T R AH0 N S",  verbal: "IH0 N T R AE1 N S"),
        Entry(word: "envelope", nominal: "EH1 N V AH0 L OW0 P", verbal: "IH0 N V EH1 L AH0 P"),
        Entry(word: "excuse",   nominal: "IH0 K S K Y UW1 S",  verbal: "IH0 K S K Y UW1 Z"),
        Entry(word: "attribute", nominal: "AE1 T R IH0 B Y UW0 T", verbal: "AH0 T R IH1 B Y UW0 T"),
        Entry(word: "close",    nominal: "K L OW1 S",          verbal: "K L OW1 Z"),
        Entry(word: "use",      nominal: "Y UW1 S",            verbal: "Y UW1 Z"),
        Entry(word: "house",    nominal: "HH AW1 S",           verbal: "HH AW1 Z"),
        Entry(word: "abuse",    nominal: "AH0 B Y UW1 S",      verbal: "AH0 B Y UW1 Z"),
        Entry(word: "separate", nominal: "S EH1 P R AH0 T",    verbal: "S EH1 P ER0 EY2 T"),
        Entry(word: "graduate", nominal: "G R AE1 JH AH0 W AH0 T", verbal: "G R AE1 JH AH0 W EY2 T"),
        Entry(word: "estimate", nominal: "EH1 S T AH0 M AH0 T", verbal: "EH1 S T AH0 M EY2 T"),
        Entry(word: "moderate", nominal: "M AA1 D ER0 AH0 T",  verbal: "M AA1 D ER0 EY2 T"),
        Entry(word: "delegate", nominal: "D EH1 L AH0 G AH0 T", verbal: "D EH1 L AH0 G EY2 T"),
        Entry(word: "duplicate", nominal: "D UW1 P L AH0 K AH0 T", verbal: "D UW1 P L AH0 K EY2 T"),
        Entry(word: "advocate", nominal: "AE1 D V AH0 K AH0 T", verbal: "AE1 D V AH0 K EY2 T"),
        Entry(word: "associate", nominal: "AH0 S OW1 S IY0 AH0 T", verbal: "AH0 S OW1 S IY0 EY2 T"),
        Entry(word: "alternate", nominal: "AO1 L T ER0 N AH0 T", verbal: "AO1 L T ER0 N EY2 T"),
        Entry(word: "approximate", nominal: "AH0 P R AA1 K S AH0 M AH0 T", verbal: "AH0 P R AA1 K S AH0 M EY2 T"),
        Entry(word: "articulate", nominal: "AA0 R T IH1 K Y AH0 L AH0 T", verbal: "AA0 R T IH1 K Y AH0 L EY2 T"),
        Entry(word: "deliberate", nominal: "D IH0 L IH1 B ER0 AH0 T", verbal: "D IH0 L IH1 B ER0 EY2 T"),
        Entry(word: "elaborate", nominal: "IH0 L AE1 B ER0 AH0 T", verbal: "IH0 L AE1 B ER0 EY2 T"),
    ]

    private static let index: [String: Entry] = {
        Dictionary(entries.map { ($0.word, $0) }, uniquingKeysWith: { first, _ in first })
    }()

    public init() {}

    /// Every heteronym the resolver knows, sorted.
    public static var words: [String] { entries.map(\.word).sorted() }

    /// Whether `word` is a known heteronym.
    public func isHeteronym(_ word: String) -> Bool {
        Self.index[word.lowercased()] != nil
    }

    /// The pronunciation of `word` for the given part of speech.
    ///
    /// Returns `nil` when the word is not a heteronym, leaving the caller to
    /// fall back to the lexicon. When the part of speech is unknown the
    /// nominal reading is used, since nouns and adjectives are the more
    /// frequent surface forms for most of these pairs.
    public func phonemes(for word: String, partOfSpeech: PartOfSpeech) -> [Phoneme]? {
        guard let entry = Self.index[word.lowercased()] else { return nil }
        let arpabet = partOfSpeech == .verb ? entry.verbal : entry.nominal
        return PhonemeInventory.phonemes(fromARPAbet: arpabet)
    }

    /// The ARPAbet reading for `word` in the given part of speech.
    public func arpabet(for word: String, partOfSpeech: PartOfSpeech) -> String? {
        guard let entry = Self.index[word.lowercased()] else { return nil }
        return partOfSpeech == .verb ? entry.verbal : entry.nominal
    }
}
