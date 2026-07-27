import Foundation

/// Custom pronunciation dictionary for word and phrase overrides.
///
/// Allows applications to define custom pronunciations for specific words,
/// proper nouns, technical terms, and brand names.
public struct PronunciationDictionary: Sendable {
    /// Entry in the pronunciation dictionary.
    public struct Entry: Sendable {
        /// The word or phrase to match.
        public let word: String

        /// Phonemic transcription (IPA).
        public let phonemes: [Phoneme]

        /// Optional part of speech for context-aware selection.
        public let partOfSpeech: String?

        /// Usage note or example.
        public let note: String?

        public init(
            word: String,
            phonemes: [Phoneme],
            partOfSpeech: String? = nil,
            note: String? = nil
        ) {
            self.word = word.lowercased()
            self.phonemes = phonemes
            self.partOfSpeech = partOfSpeech
            self.note = note
        }
    }

    /// Internal dictionary storage.
    private var entries: [String: [Entry]] = [:]

    public init() {}

    /// Adds a custom pronunciation entry.
    ///
    /// - Parameter entry: The pronunciation entry to add.
    public mutating func add(_ entry: Entry) {
        let key = entry.word.lowercased()
        if entries[key] == nil {
            entries[key] = []
        }
        entries[key]?.append(entry)
    }

    /// Adds multiple entries at once.
    public mutating func addEntries(_ entries: [Entry]) {
        for entry in entries {
            add(entry)
        }
    }

    /// Retrieves a pronunciation for a word.
    ///
    /// - Parameters:
    ///   - word: The word to look up.
    ///   - partOfSpeech: Optional part of speech for disambiguation.
    /// - Returns: The phoneme transcription, or nil if not found.
    public func lookup(_ word: String, partOfSpeech: String? = nil) -> [Phoneme]? {
        let key = word.lowercased()
        guard let candidates = entries[key] else { return nil }

        // If POS is specified, prefer matching entries
        if let pos = partOfSpeech {
            if let match = candidates.first(where: { $0.partOfSpeech == pos }) {
                return match.phonemes
            }
        }

        // Return first entry if no POS match
        return candidates.first?.phonemes
    }

    /// Checks if a word has a custom pronunciation.
    public func contains(_ word: String) -> Bool {
        entries[word.lowercased()] != nil
    }

    /// Clears all entries.
    public mutating func clear() {
        entries.removeAll()
    }

    /// Returns the number of entries.
    public var count: Int {
        entries.values.reduce(0) { $0 + $1.count }
    }

    /// Predefined dictionary with common proper nouns and technical terms.
    public static let standard: PronunciationDictionary = {
        var dict = PronunciationDictionary()

        // Technology terms
        dict.add(Entry(
            word: "iOS",
            phonemes: [Phoneme("aɪ"), Phoneme("oʊ"), Phoneme("ɛ"), Phoneme("s")],
            partOfSpeech: "noun",
            note: "Apple's mobile operating system"
        ))

        dict.add(Entry(
            word: "macOS",
            phonemes: [Phoneme("m"), Phoneme("æ"), Phoneme("k"), Phoneme("oʊ"), Phoneme("ɛ"), Phoneme("s")],
            partOfSpeech: "noun",
            note: "Apple's desktop operating system"
        ))

        dict.add(Entry(
            word: "synthesis",
            phonemes: [Phoneme("s"), Phoneme("ɪ"), Phoneme("n"), Phoneme("θ"), Phoneme("ə"), Phoneme("s"), Phoneme("ɪ"), Phoneme("s")],
            partOfSpeech: "noun"
        ))

        // Brand names
        dict.add(Entry(
            word: "choir",
            phonemes: [Phoneme("k"), Phoneme("w"), Phoneme("aɪ"), Phoneme("ə"), Phoneme("r")],
            partOfSpeech: "noun"
        ))

        // Names
        dict.add(Entry(
            word: "claude",
            phonemes: [Phoneme("k"), Phoneme("l"), Phoneme("oʊ"), Phoneme("d")],
            partOfSpeech: "noun",
            note: "Name"
        ))

        return dict
    }()
}
