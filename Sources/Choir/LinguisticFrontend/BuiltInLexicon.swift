import Foundation

/// The built-in pronunciation lexicon (SRS TXT-020).
///
/// TXT-020 requires "a built-in pronunciation lexicon of at least 120,000
/// English word forms with primary/secondary stress". The data is CMUdict,
/// which carries 135,166 entries with CMU's stress digits, redistributed under
/// its BSD-2-Clause licence.
///
/// The dictionary is stored as distributed, in ARPAbet, and converted to
/// CHOIR's IPA inventory on lookup rather than up front. Converting 135,000
/// entries eagerly would cost time and memory for words a given request never
/// asks about; converting per lookup, with results cached, keeps the cost
/// proportional to what is actually spoken.
///
/// Loading is lazy and happens once. Callers that want the cost paid at launch
/// rather than at the user's first tap should call ``preload()`` (SYN-009).
public final class BuiltInLexicon: @unchecked Sendable {
    /// The shared instance backed by the bundled dictionary.
    public static let shared = BuiltInLexicon()

    private let lock = NSLock()
    private var index: [String: String]?
    private var converted: [String: [Phoneme]] = [:]
    private let loader: @Sendable () -> [String: String]

    /// Creates a lexicon over the bundled CMUdict resource.
    public init() {
        self.loader = BuiltInLexicon.loadBundledIndex
    }

    /// Creates a lexicon over supplied ARPAbet entries, for testing.
    public init(entries: [String: String]) {
        self.loader = { entries }
    }

    /// Loads the dictionary if it has not been loaded yet.
    ///
    /// Safe to call repeatedly and from any thread.
    public func preload() {
        _ = resolvedIndex()
    }

    /// Whether the dictionary has been loaded.
    public var isLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        return index != nil
    }

    /// The number of word forms available.
    public var count: Int {
        resolvedIndex().count
    }

    /// The pronunciation of `word`, or `nil` when it is not in the lexicon.
    ///
    /// Lookup is case-insensitive. Stress digits from CMUdict are carried
    /// through onto the resulting vowels.
    public func phonemes(for word: String) -> [Phoneme]? {
        let key = word.lowercased()

        lock.lock()
        if let cached = converted[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let arpabet = resolvedIndex()[key] else { return nil }
        let phonemes = PhonemeInventory.phonemes(fromARPAbet: arpabet)

        lock.lock()
        converted[key] = phonemes
        lock.unlock()
        return phonemes
    }

    /// Whether `word` appears in the lexicon.
    public func contains(_ word: String) -> Bool {
        resolvedIndex()[word.lowercased()] != nil
    }

    /// Every word form in the lexicon.
    ///
    /// Used by the G2P evaluation harness to draw a held-out sample.
    public var allWords: [String] {
        Array(resolvedIndex().keys)
    }

    /// The raw ARPAbet string for `word`, for diagnostics and tooling.
    public func arpabet(for word: String) -> String? {
        resolvedIndex()[word.lowercased()]
    }

    // MARK: - Loading

    private func resolvedIndex() -> [String: String] {
        lock.lock()
        if let index {
            lock.unlock()
            return index
        }
        lock.unlock()

        // Load outside the lock: parsing is slow and must not block readers of
        // an already-loaded index.
        let loaded = loader()

        lock.lock()
        if let existing = index {
            // Another thread finished first; keep its result so that callers
            // never observe two different dictionaries.
            lock.unlock()
            return existing
        }
        index = loaded
        lock.unlock()
        return loaded
    }

    /// Parses the bundled dictionary into `word -> ARPAbet` entries.
    ///
    /// CMUdict lists pronunciation variants as `word(2)`. Only the first,
    /// unnumbered form is indexed: variant selection needs part-of-speech
    /// context, which is TXT-021's job, not the lexicon's.
    private static func loadBundledIndex() -> [String: String] {
        guard let url = Bundle.module.url(forResource: "cmudict", withExtension: "dict"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return [:]
        }

        var result: [String: String] = [:]
        result.reserveCapacity(140_000)

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let space = line.firstIndex(of: " ") else { continue }
            let word = String(line[line.startIndex..<space])
            // Skip variant spellings such as "read(2)".
            guard !word.hasSuffix(")") else { continue }

            let pronunciation = String(line[line.index(after: space)...])
                .trimmingCharacters(in: .whitespaces)
            guard !pronunciation.isEmpty else { continue }
            result[word.lowercased()] = pronunciation
        }

        // TXT-023: the curated theological supplement wins over CMUdict, and
        // supplies the many canonical book names CMUdict lacks entirely.
        result.merge(TheologicalLexicon.entries) { _, curated in curated }
        return result
    }
}
