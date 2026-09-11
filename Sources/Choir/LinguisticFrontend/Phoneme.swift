import Foundation

/// A phoneme representing a distinct sound in English.
public struct Phoneme: Equatable, Hashable, Sendable, Codable {
    /// The phoneme symbol (e.g., "ə", "ɪ", "s", "t").
    public let symbol: String

    /// Stress level: 0 (unstressed), 1 (primary), 2 (secondary).
    public var stress: Int = 0

    /// Whether this is a vowel.
    public var isVowel: Bool {
        vowelPhonemes.contains(symbol)
    }

    public init(_ symbol: String, stress: Int = 0) {
        // U+0261 LATIN SMALL LETTER SCRIPT G is the canonical IPA symbol.
        // Accept the visually similar ASCII "g" at API boundaries, but never
        // allow the two representations to split the model vocabulary.
        self.symbol = symbol == "g" ? "\u{0261}" : symbol
        self.stress = min(2, max(0, stress))
    }

    private enum CodingKeys: String, CodingKey { case symbol, stress }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(String.self, forKey: .symbol),
            stress: try container.decodeIfPresent(Int.self, forKey: .stress) ?? 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(stress, forKey: .stress)
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
    "b", "d", "f", "ɡ", "h", "j", "k", "l", "m", "n", "ŋ", "p", "r", "s", "t", "v", "w", "z",
    "θ", "ð", "ʃ", "ʒ", "tʃ", "dʒ",
])

let vowelPhonemes = Set([
    "ɑ", "æ", "ɛ", "ə", "ɪ", "ɔ", "ʊ", "ʌ",
    "iː", "uː", "oʊ", "eɪ", "aɪ", "ɔɪ", "aʊ", "ɪə", "ɛə", "ʊə",
])

/// A parsed `<mark>` anchored to the normalized word that follows it.
public struct TranscriptionMarkAnchor: Sendable, Equatable {
    public let name: String
    public let followingWordIndex: Int

    public init(name: String, followingWordIndex: Int) {
        self.name = name
        self.followingWordIndex = max(0, followingWordIndex)
    }
}

/// A parsed `<break>` anchored to the normalized word that follows it.
///
/// The duration remains in milliseconds until output preparation, where it is
/// quantized exactly once to the selected PCM sample rate (PRO-021).
public struct TranscriptionPauseAnchor: Sendable, Equatable {
    public let durationMs: Double
    public let followingWordIndex: Int

    public init(durationMs: Double, followingWordIndex: Int) {
        self.durationMs = durationMs.isFinite ? max(0, durationMs) : 0
        self.followingWordIndex = max(0, followingWordIndex)
    }
}

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

    /// Mark positions expressed after normalization, so an expansion such as
    /// `$1,250` advances by all spoken words rather than one raw token.
    public let markAnchors: [TranscriptionMarkAnchor]

    /// Explicit SSML-C pauses anchored after normalization (PRO-021).
    public let pauseAnchors: [TranscriptionPauseAnchor]

    /// Contextual natural-language analysis parallel to the normalized words.
    ///
    /// Pre-phonemized input and front ends with NLP disabled leave this `nil`.
    /// Consumers must therefore treat it as an enhancement, never as a
    /// prerequisite for synthesis.
    public let speechPlan: ContextualSpeechPlan?

    public init(
        phonemes: [Phoneme],
        originalText: String,
        wordBoundaries: [Int] = [],
        syllableBoundaries: [Int] = [],
        wordTexts: [String] = [],
        phraseBoundaries: [Int: PhraseBoundary] = [:],
        markAnchors: [TranscriptionMarkAnchor] = [],
        pauseAnchors: [TranscriptionPauseAnchor] = [],
        speechPlan: ContextualSpeechPlan? = nil
    ) {
        self.phraseBoundaries = phraseBoundaries
        self.markAnchors = markAnchors
        self.pauseAnchors = pauseAnchors
        self.speechPlan = speechPlan
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
