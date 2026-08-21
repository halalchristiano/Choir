import Foundation

/// The built-in pronunciation lexicon (SRS TXT-020).
///
/// TXT-020 requires "a built-in pronunciation lexicon of at least 120,000
/// English word forms with primary/secondary stress". The data is CMUdict,
/// carrying CMU's stress digits, redistributed under its BSD-2-Clause licence.
///
/// ## Why the file is sorted and memory-mapped
///
/// The first implementation parsed 3.6 MB of text into a `[String: String]` at
/// first use. The PRF-040 harness measured that at roughly **one second** —
/// two-thirds of the entire 1.5 s cold-start budget PRF-011 allows on R3, and
/// spent before an acoustic model has loaded anything.
///
/// The cost was never the I/O. It was allocating a quarter of a million Swift
/// strings and hashing them into a dictionary, all to answer lookups for the
/// few hundred words a given request actually contains.
///
/// The lexicon now ships pre-sorted by word, is mapped rather than read, and is
/// searched by comparing raw bytes. Loading builds only an array of line
/// offsets — one pass over the bytes, no string allocation at all — and a
/// lookup is a binary search that materializes exactly one string.
public final class BuiltInLexicon: @unchecked Sendable {
    /// The shared instance backed by the bundled dictionary.
    public static let shared = BuiltInLexicon()

    /// How the entries are held.
    private enum Backing {
        /// The mapped resource, with the byte offset of each line start.
        case mapped(data: Data, lineStarts: [Int])

        /// Entries supplied directly, for tests.
        case memory([String: String])
    }

    private let lock = NSLock()
    private var backing: Backing?
    private var converted: [String: [Phoneme]] = [:]
    private let loader: @Sendable () -> Backing

    /// Curated overrides consulted before the mapped file (TXT-023).
    ///
    /// Small enough to hold in memory, and checked first so the supplement
    /// keeps precedence without needing to be merged into the resource.
    private let supplement: [String: String]

    /// Creates a lexicon over the bundled resource.
    public init() {
        self.loader = BuiltInLexicon.loadBundled
        self.supplement = TheologicalLexicon.entries
    }

    /// Creates a lexicon over supplied ARPAbet entries, for testing.
    public init(entries: [String: String]) {
        self.loader = { .memory(entries) }
        self.supplement = [:]
    }

    /// Loads the dictionary if it has not been loaded yet.
    ///
    /// Safe to call repeatedly and from any thread. Far cheaper than it used
    /// to be, but still worth calling at launch rather than at the user's first
    /// tap (SYN-009).
    public func preload() {
        _ = resolvedBacking()
    }

    /// Whether the dictionary has been loaded.
    public var isLoaded: Bool {
        lock.lock(); defer { lock.unlock() }
        return backing != nil
    }

    /// The number of word forms available.
    public var count: Int {
        switch resolvedBacking() {
        case .mapped(_, let lineStarts):
            // Supplement entries already present in the file are not additional.
            let extra = supplement.keys.filter { lookupMapped($0) == nil }.count
            return lineStarts.count + extra
        case .memory(let entries):
            return entries.count
        }
    }

    /// Every word form in the lexicon.
    ///
    /// Materializes every key, so it is for tooling — the G2P evaluation
    /// harness — rather than the synthesis path.
    public var allWords: [String] {
        switch resolvedBacking() {
        case .mapped(let data, let lineStarts):
            var words: [String] = []
            words.reserveCapacity(lineStarts.count)
            data.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                for start in lineStarts {
                    guard let tab = Self.tabIndex(in: bytes, from: start) else { continue }
                    words.append(Self.string(bytes, start, tab))
                }
            }
            return words + supplement.keys.filter { lookupMapped($0) == nil }
        case .memory(let entries):
            return Array(entries.keys)
        }
    }

    /// The pronunciation of `word`, or `nil` when it is not in the lexicon.
    ///
    /// Lookup is case-insensitive. CMUdict's stress digits are carried through
    /// onto the resulting vowels.
    public func phonemes(for word: String) -> [Phoneme]? {
        let key = word.lowercased()

        lock.lock()
        if let cached = converted[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let arpabet = arpabet(for: key) else { return nil }
        let phonemes = PhonemeInventory.phonemes(fromARPAbet: arpabet)

        lock.lock()
        converted[key] = phonemes
        lock.unlock()
        return phonemes
    }

    /// Whether `word` appears in the lexicon.
    public func contains(_ word: String) -> Bool {
        arpabet(for: word) != nil
    }

    /// The raw ARPAbet string for `word`.
    public func arpabet(for word: String) -> String? {
        let key = word.lowercased()
        // TXT-023: the curated supplement wins over CMUdict.
        if let curated = supplement[key] { return curated }

        switch resolvedBacking() {
        case .mapped:
            return lookupMapped(key)
        case .memory(let entries):
            return entries[key]
        }
    }

    // MARK: - Mapped lookup

    /// Binary search over the sorted, mapped file.
    private func lookupMapped(_ key: String) -> String? {
        guard case .mapped(let data, let lineStarts) = resolvedBacking() else { return nil }
        let needle = Array(key.utf8)

        return data.withUnsafeBytes { raw -> String? in
            let bytes = raw.bindMemory(to: UInt8.self)
            var low = 0
            var high = lineStarts.count - 1

            while low <= high {
                let mid = (low + high) / 2
                let start = lineStarts[mid]
                guard let tab = Self.tabIndex(in: bytes, from: start) else { return nil }

                switch Self.compare(bytes, start, tab, needle) {
                case .orderedSame:
                    let end = Self.lineEnd(in: bytes, from: tab + 1)
                    return Self.string(bytes, tab + 1, end)
                case .orderedAscending:
                    low = mid + 1
                case .orderedDescending:
                    high = mid - 1
                }
            }
            return nil
        }
    }

    /// Compares the word field of a line against `needle`, byte by byte.
    private static func compare(
        _ bytes: UnsafeBufferPointer<UInt8>,
        _ start: Int,
        _ tab: Int,
        _ needle: [UInt8]
    ) -> ComparisonResult {
        let length = tab - start
        let shared = min(length, needle.count)
        var index = 0
        while index < shared {
            let lhs = bytes[start + index]
            let rhs = needle[index]
            if lhs != rhs { return lhs < rhs ? .orderedAscending : .orderedDescending }
            index += 1
        }
        if length == needle.count { return .orderedSame }
        return length < needle.count ? .orderedAscending : .orderedDescending
    }

    private static func tabIndex(in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int? {
        var index = start
        while index < bytes.count, bytes[index] != 0x0A {
            if bytes[index] == 0x09 { return index }
            index += 1
        }
        return nil
    }

    private static func lineEnd(in bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0x0A { index += 1 }
        return index
    }

    private static func string(
        _ bytes: UnsafeBufferPointer<UInt8>,
        _ start: Int,
        _ end: Int
    ) -> String {
        guard end > start, let base = bytes.baseAddress else { return "" }
        return String(decoding: UnsafeBufferPointer(start: base + start, count: end - start),
                      as: UTF8.self)
    }

    // MARK: - Loading

    private func resolvedBacking() -> Backing {
        lock.lock()
        if let backing {
            lock.unlock()
            return backing
        }
        lock.unlock()

        // Load outside the lock so a slow first load cannot block readers of an
        // already-loaded index.
        let loaded = loader()

        lock.lock()
        if let existing = backing {
            // Another thread finished first; keep its result so callers never
            // observe two different dictionaries.
            lock.unlock()
            return existing
        }
        backing = loaded
        lock.unlock()
        return loaded
    }

    /// Maps the bundled resource and indexes its line starts.
    ///
    /// One pass over the bytes, allocating a single array of offsets. No string
    /// is created here at all — that is the whole point.
    private static func loadBundled() -> Backing {
        guard let url = Bundle.module.url(forResource: "cmudict", withExtension: "lex"),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
        else {
            return .memory([:])
        }

        var lineStarts: [Int] = []
        lineStarts.reserveCapacity(130_000)

        data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var start = 0
            for index in 0..<bytes.count where bytes[index] == 0x0A {
                if index > start { lineStarts.append(start) }
                start = index + 1
            }
            if start < bytes.count { lineStarts.append(start) }
        }

        return .mapped(data: data, lineStarts: lineStarts)
    }
}
