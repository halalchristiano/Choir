import Foundation

/// A custom pronunciation registered by a consuming app.
public enum UserPronunciation: Sendable, Equatable, Codable {
    /// An explicit phoneme sequence, e.g. `["m", "ɛ", "l", "k", "ɪ", "z", "ə", "d", "ɛ", "k"]`.
    case phonemes([String])

    /// A respelling to be phonemized by the normal rules,
    /// e.g. `"mel KIZ uh dek"`.
    case respelling(String)
}

/// Where a ``UserLexicon`` keeps its entries between launches.
///
/// SRS TXT-022 requires registrations to persist per app. The protocol keeps
/// the storage mechanism replaceable so that a consuming app can supply its
/// own container, and so tests need not touch app-wide state.
public protocol UserLexiconStore: Sendable {
    func load() -> [String: UserPronunciation]
    func save(_ entries: [String: UserPronunciation])
}

/// Persists the lexicon in `UserDefaults`, scoped to the calling app.
///
/// Chosen because it is available on every platform CHOIR targets and requires
/// no file coordination. It makes no network calls, satisfying SEC-001.
public struct UserDefaultsLexiconStore: UserLexiconStore {
    /// Suite name rather than a `UserDefaults` instance: `UserDefaults` is
    /// thread-safe but not `Sendable` under Swift 6 strict concurrency, so the
    /// store resolves it on demand instead of holding one.
    private let suiteName: String?
    private let key: String

    public init(suiteName: String? = nil, key: String = "com.choir.userLexicon") {
        self.suiteName = suiteName
        self.key = key
    }

    private var defaults: UserDefaults {
        guard let suiteName, let suite = UserDefaults(suiteName: suiteName) else {
            return .standard
        }
        return suite
    }

    public func load() -> [String: UserPronunciation] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: UserPronunciation].self, from: data)
        else { return [:] }
        return decoded
    }

    public func save(_ entries: [String: UserPronunciation]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: key)
    }
}

/// An in-memory store, for tests and for apps that manage their own persistence.
public final class InMemoryLexiconStore: UserLexiconStore, @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String: UserPronunciation]

    public init(entries: [String: UserPronunciation] = [:]) {
        self.entries = entries
    }

    public func load() -> [String: UserPronunciation] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }

    public func save(_ entries: [String: UserPronunciation]) {
        lock.lock(); defer { lock.unlock() }
        self.entries = entries
    }
}

/// Runtime pronunciation overrides registered by the consuming app.
///
/// Implements SRS TXT-022 (MUST): consuming apps may register custom
/// pronunciations at runtime, persisting per app, taking precedence over the
/// built-in lexicon.
///
/// The specification's rationale is that theological names (Socinus, Crellius,
/// Athanasius, Melchizedek), invented game names, and brand names must be
/// pronounceable on day one without waiting for a package update.
///
/// An actor, because registration happens on whatever thread the app is on
/// while synthesis reads concurrently (SYN-006).
public actor UserLexicon {
    private var entries: [String: UserPronunciation]
    private let store: UserLexiconStore

    public init(store: UserLexiconStore = UserDefaultsLexiconStore()) {
        self.store = store
        self.entries = store.load()
    }

    /// Registers an explicit phoneme sequence for `word`.
    ///
    /// Replaces any existing registration. Lookup is case-insensitive, so
    /// "Melchizedek" and "melchizedek" resolve to the same entry.
    public func register(word: String, phonemes: [String]) {
        setEntry(word, .phonemes(phonemes))
    }

    /// Registers a respelling for `word`, phonemized by the normal rules.
    public func register(word: String, respelling: String) {
        setEntry(word, .respelling(respelling))
    }

    /// Registers several pronunciations at once.
    public func register(_ pronunciations: [String: UserPronunciation]) {
        for (word, pronunciation) in pronunciations {
            setEntry(word, pronunciation)
        }
    }

    /// Removes any registration for `word`. Returns whether one existed.
    @discardableResult
    public func remove(word: String) -> Bool {
        let key = Self.key(for: word)
        guard entries.removeValue(forKey: key) != nil else { return false }
        store.save(entries)
        return true
    }

    /// Removes every registration.
    public func removeAll() {
        entries.removeAll()
        store.save(entries)
    }

    /// The registered pronunciation for `word`, if any.
    public func pronunciation(for word: String) -> UserPronunciation? {
        entries[Self.key(for: word)]
    }

    /// Whether `word` has a registration.
    public func contains(_ word: String) -> Bool {
        entries[Self.key(for: word)] != nil
    }

    /// Every registered word, lowercased.
    public var registeredWords: [String] {
        entries.keys.sorted()
    }

    public var count: Int { entries.count }

    /// An immutable snapshot for use on the synthesis path, which must not
    /// await per word.
    public func snapshot() -> UserLexiconSnapshot {
        UserLexiconSnapshot(entries: entries)
    }

    private func setEntry(_ word: String, _ pronunciation: UserPronunciation) {
        entries[Self.key(for: word)] = pronunciation
        store.save(entries)
    }

    private static func key(for word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// A point-in-time copy of a ``UserLexicon``.
///
/// Synthesis resolves pronunciations synchronously for every word, so it takes
/// one snapshot per request rather than awaiting the actor per lookup.
public struct UserLexiconSnapshot: Sendable, Equatable {
    private let entries: [String: UserPronunciation]

    public init(entries: [String: UserPronunciation] = [:]) {
        self.entries = entries
    }

    /// The registered pronunciation for `word`, if any.
    public func pronunciation(for word: String) -> UserPronunciation? {
        entries[word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var count: Int { entries.count }

    /// An empty snapshot, the default on the synthesis path.
    public static let empty = UserLexiconSnapshot()
}
