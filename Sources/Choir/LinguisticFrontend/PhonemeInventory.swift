import Foundation

/// Lexical stress on a vowel (SRS TXT-020).
public enum StressLevel: Int, Sendable, Equatable, Codable, CaseIterable {
    case none = 0
    case primary = 1
    case secondary = 2
}

/// The documented, stable phoneme inventory (SRS TXT-024).
///
/// TXT-024 requires the inventory to be documented as an ARPAbet-to-IPA
/// mapping table, stable across versions, and exposed publicly for the
/// pre-phonemized input path of TXT-050.
///
/// The inventory is the 39 phonemes of General American English as used by
/// CMUdict, plus schwa, which the rule-based fallback emits directly and which
/// CMUdict writes as unstressed AH. Each entry pairs the ARPAbet symbol with
/// the IPA symbol CHOIR uses internally.
///
/// - Important: These symbols are part of the public API. Per TXT-024 they are
///   stable across versions: symbols may be added in a minor release, but an
///   existing symbol will never change meaning or be removed within a major
///   version.
public enum PhonemeInventory {

    /// One phoneme of the inventory.
    public struct Entry: Sendable, Equatable, Hashable, Codable {
        /// ARPAbet symbol, e.g. `"AA"`.
        public let arpabet: String

        /// IPA symbol as used internally by CHOIR, e.g. `"ɑ"`.
        public let ipa: String

        /// Whether the phoneme is a vowel, and so can carry stress.
        public let isVowel: Bool

        /// A word illustrating the sound, e.g. `"odd"` for `AA`.
        public let example: String

        public init(arpabet: String, ipa: String, isVowel: Bool, example: String) {
            self.arpabet = arpabet
            self.ipa = ipa
            self.isVowel = isVowel
            self.example = example
        }
    }

    /// The complete inventory: 16 vowels and 24 consonants.
    public static let all: [Entry] = [
        // Vowels and diphthongs
        Entry(arpabet: "AA", ipa: "ɑ",  isVowel: true, example: "odd"),
        Entry(arpabet: "AE", ipa: "æ",  isVowel: true, example: "at"),
        Entry(arpabet: "AH", ipa: "ʌ",  isVowel: true, example: "hut"),
        // Schwa is ARPAbet AH at stress 0. Listed separately because the
        // rule-based fallback produces it directly, and TXT-024 requires every
        // symbol the engine can emit to belong to the documented inventory.
        Entry(arpabet: "AX", ipa: "ə",  isVowel: true, example: "about"),
        Entry(arpabet: "AO", ipa: "ɔ",  isVowel: true, example: "ought"),
        Entry(arpabet: "AW", ipa: "aʊ", isVowel: true, example: "cow"),
        Entry(arpabet: "AY", ipa: "aɪ", isVowel: true, example: "hide"),
        Entry(arpabet: "EH", ipa: "ɛ",  isVowel: true, example: "Ed"),
        Entry(arpabet: "ER", ipa: "ɝ",  isVowel: true, example: "hurt"),
        Entry(arpabet: "EY", ipa: "eɪ", isVowel: true, example: "ate"),
        Entry(arpabet: "IH", ipa: "ɪ",  isVowel: true, example: "it"),
        Entry(arpabet: "IY", ipa: "iː", isVowel: true, example: "eat"),
        Entry(arpabet: "OW", ipa: "oʊ", isVowel: true, example: "oat"),
        Entry(arpabet: "OY", ipa: "ɔɪ", isVowel: true, example: "toy"),
        Entry(arpabet: "UH", ipa: "ʊ",  isVowel: true, example: "hood"),
        Entry(arpabet: "UW", ipa: "uː", isVowel: true, example: "two"),

        // Consonants
        Entry(arpabet: "B",  ipa: "b",  isVowel: false, example: "be"),
        Entry(arpabet: "CH", ipa: "tʃ", isVowel: false, example: "cheese"),
        Entry(arpabet: "D",  ipa: "d",  isVowel: false, example: "dee"),
        Entry(arpabet: "DH", ipa: "ð",  isVowel: false, example: "thee"),
        Entry(arpabet: "F",  ipa: "f",  isVowel: false, example: "fee"),
        Entry(arpabet: "G",  ipa: "ɡ",  isVowel: false, example: "green"),
        Entry(arpabet: "HH", ipa: "h",  isVowel: false, example: "he"),
        Entry(arpabet: "JH", ipa: "dʒ", isVowel: false, example: "gee"),
        Entry(arpabet: "K",  ipa: "k",  isVowel: false, example: "key"),
        Entry(arpabet: "L",  ipa: "l",  isVowel: false, example: "lee"),
        Entry(arpabet: "M",  ipa: "m",  isVowel: false, example: "me"),
        Entry(arpabet: "N",  ipa: "n",  isVowel: false, example: "knee"),
        Entry(arpabet: "NG", ipa: "ŋ",  isVowel: false, example: "ping"),
        Entry(arpabet: "P",  ipa: "p",  isVowel: false, example: "pee"),
        Entry(arpabet: "R",  ipa: "r",  isVowel: false, example: "read"),
        Entry(arpabet: "S",  ipa: "s",  isVowel: false, example: "sea"),
        Entry(arpabet: "SH", ipa: "ʃ",  isVowel: false, example: "she"),
        Entry(arpabet: "T",  ipa: "t",  isVowel: false, example: "tea"),
        Entry(arpabet: "TH", ipa: "θ",  isVowel: false, example: "theta"),
        Entry(arpabet: "V",  ipa: "v",  isVowel: false, example: "vee"),
        Entry(arpabet: "W",  ipa: "w",  isVowel: false, example: "we"),
        Entry(arpabet: "Y",  ipa: "j",  isVowel: false, example: "yield"),
        Entry(arpabet: "Z",  ipa: "z",  isVowel: false, example: "zee"),
        Entry(arpabet: "ZH", ipa: "ʒ",  isVowel: false, example: "seizure"),
    ]

    /// Vowels, which are the phonemes that carry stress.
    public static let vowels: [Entry] = all.filter(\.isVowel)

    /// Consonants.
    public static let consonants: [Entry] = all.filter { !$0.isVowel }

    private static let byARPAbet: [String: Entry] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.arpabet, $0) })
    }()

    private static let byIPA: [String: Entry] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0.ipa, $0) })
    }()

    /// The IPA symbol for an ARPAbet symbol, ignoring any trailing stress digit.
    ///
    /// `"AA1"` and `"AA"` both resolve to `"ɑ"`.
    public static func ipa(forARPAbet symbol: String) -> String? {
        byARPAbet[stripStress(symbol).symbol]?.ipa
    }

    /// The ARPAbet symbol for an IPA symbol.
    public static func arpabet(forIPA symbol: String) -> String? {
        byIPA[symbol]?.arpabet
    }

    /// Whether `symbol` is part of the documented inventory.
    ///
    /// Used to validate the pre-phonemized input path (TXT-050).
    public static func isValidIPA(_ symbol: String) -> Bool {
        byIPA[symbol] != nil
    }

    /// Whether an IPA symbol is a vowel, and so may carry stress.
    public static func isVowel(ipa symbol: String) -> Bool {
        byIPA[symbol]?.isVowel ?? false
    }

    /// Splits an ARPAbet symbol into its base and stress digit.
    ///
    /// CMUdict marks stress by appending 0, 1 or 2 to a vowel: `"AA1"` is a
    /// primary-stressed `AA`.
    public static func stripStress(_ symbol: String) -> (symbol: String, stress: StressLevel) {
        guard let last = symbol.last, last.isNumber,
              let raw = Int(String(last)),
              let level = StressLevel(rawValue: raw)
        else {
            return (symbol, .none)
        }
        return (String(symbol.dropLast()), level)
    }

    /// Converts a whitespace-separated ARPAbet string to CHOIR phonemes.
    ///
    /// Unknown symbols are skipped rather than trapping, per TXT-002.
    public static func phonemes(fromARPAbet line: String) -> [Phoneme] {
        line.split(whereSeparator: \.isWhitespace).compactMap { token in
            let (base, stress) = stripStress(String(token))
            guard let entry = byARPAbet[base] else { return nil }
            // CMUdict writes unstressed AH where English has schwa. Mapping
            // both to /ʌ/ conflates two audibly different vowels and would
            // make "about" rhyme with "hut".
            if base == "AH", stress == .none {
                return Phoneme("ə", stress: 0)
            }
            return Phoneme(entry.ipa, stress: stress.rawValue)
        }
    }

    /// The mapping table as documentation, one row per phoneme.
    ///
    /// TXT-024 requires the table to be published; this renders it so that
    /// documentation cannot drift from the code.
    public static var mappingTable: String {
        let header = "ARPAbet | IPA | Type       | Example\n--------|-----|------------|--------"
        let rows = all.map {
            String(format: "%-7@ | %-3@ | %-10@ | %@",
                   $0.arpabet as NSString,
                   $0.ipa as NSString,
                   ($0.isVowel ? "vowel" : "consonant") as NSString,
                   $0.example as NSString)
        }
        return ([header] + rows).joined(separator: "\n")
    }
}
