import Foundation

/// A phoneme representing a distinct sound in English.
public struct Phoneme: Equatable, Hashable, Sendable {
    /// The phoneme symbol (e.g., "ə", "ɪ", "s", "t").
    public let symbol: String

    /// Stress level: 0 (unstressed), 1 (primary), 2 (secondary).
    public var stress: Int = 0

    /// Whether this is a vowel.
    public var isVowel: Bool {
        vowelPhonemes.contains(symbol)
    }

    public init(_ symbol: String, stress: Int = 0) {
        self.symbol = symbol
        self.stress = min(2, max(0, stress))
    }

    public var description: String {
        let stressMarker = stress == 1 ? "ˈ" : stress == 2 ? "ˌ" : ""
        return stressMarker + symbol
    }
}

/// All English phoneme symbols (IPA).
let englishPhonemes = Set([
    // Vowels
    "ɑ", "æ", "ɛ", "ə", "ɪ", "ɔ", "ʊ", "ʌ",
    "iː", "uː", "oʊ", "eɪ", "aɪ", "ɔɪ", "aʊ", "ɪə", "ɛə", "ʊə",
    // Consonants
    "b", "d", "f", "g", "h", "j", "k", "l", "m", "n", "ŋ", "p", "r", "s", "t", "v", "w", "z",
    "θ", "ð", "ʃ", "ʒ", "tʃ", "dʒ",
])

let vowelPhonemes = Set([
    "ɑ", "æ", "ɛ", "ə", "ɪ", "ɔ", "ʊ", "ʌ",
    "iː", "uː", "oʊ", "eɪ", "aɪ", "ɔɪ", "aʊ", "ɪə", "ɛə", "ʊə",
])

/// A sequence of phonemes with timing and prosodic information.
public struct PhoneticTranscription: Sendable {
    /// The phonemes in sequence.
    public let phonemes: [Phoneme]

    /// Original orthographic text.
    public let originalText: String

    /// Word boundaries (indices where new words begin).
    public let wordBoundaries: [Int]

    /// Syllable boundaries (indices where new syllables begin).
    public let syllableBoundaries: [Int]

    /// The normalized text of each word, parallel to ``wordBoundaries``.
    ///
    /// Carried so that SYN-005 per-word timing can report *what* is being
    /// spoken, not merely when.
    public let wordTexts: [String]

    /// The prosodic boundary following each word, where one falls (TXT-030).
    ///
    /// Keyed by word index. Carried so the prosody model can lengthen pauses
    /// and reset pitch at structural breaks (TXT-032) — a paragraph break that
    /// reads exactly like a comma is the difference between a chapter and a
    /// run-on.
    public let phraseBoundaries: [Int: PhraseBoundary]

    public init(
        phonemes: [Phoneme],
        originalText: String,
        wordBoundaries: [Int] = [],
        syllableBoundaries: [Int] = [],
        wordTexts: [String] = [],
        phraseBoundaries: [Int: PhraseBoundary] = [:]
    ) {
        self.phraseBoundaries = phraseBoundaries
        self.phonemes = phonemes
        self.originalText = originalText
        self.wordBoundaries = wordBoundaries
        self.syllableBoundaries = syllableBoundaries
        self.wordTexts = wordTexts
    }

    /// Reconstructs the phonetic representation as a string.
    public var description: String {
        phonemes.map { $0.description }.joined()
    }

    /// Returns words split by word boundaries.
    public var words: [[Phoneme]] {
        let boundaries = wordBoundaries + [phonemes.count]
        var result: [[Phoneme]] = []
        var start = 0

        for boundary in boundaries.sorted() {
            guard boundary > start else { continue }
            result.append(Array(phonemes[start..<boundary]))
            start = boundary
        }

        return result
    }
}
