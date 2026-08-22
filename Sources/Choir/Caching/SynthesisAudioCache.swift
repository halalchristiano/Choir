import Foundation

/// A stable SHA-256 cache key over every input that can change rendered audio.
public struct SynthesisCacheKey: Sendable, Equatable, Hashable, Codable, CustomStringConvertible {
    public let digest: String

    public var description: String { digest }

    /// Creates a key from typed CHOIR synthesis inputs. Floating-point values
    /// are hashed by their canonical IEEE-754 bit patterns, avoiding unstable
    /// textual JSON formatting.
    public init(
        text: String,
        voice: Voice,
        parameters: SynthesisParameters,
        audioFormat: AudioFormat = AudioFormat(),
        engineVersion: UInt64 = Choir.engineVersion
    ) {
        self.init(
            input: .markup(text),
            voice: voice,
            parameters: parameters,
            audioFormat: audioFormat,
            engineVersion: engineVersion)
    }

    /// Creates a key that distinguishes explicit input interpretation and PCM
    /// output format in addition to every synthesis control.
    public init(
        input: SynthesisInput,
        voice: Voice,
        parameters: SynthesisParameters,
        audioFormat: AudioFormat = AudioFormat(),
        engineVersion: UInt64 = Choir.engineVersion
    ) {
        let parameters = parameters.validated()
        var canonical = Data()
        switch input {
        case .plainText(let text):
            Self.appendComponent(Data("plain-text".utf8), to: &canonical)
            Self.appendComponent(Data(text.utf8), to: &canonical)
        case .markup(let text):
            Self.appendComponent(Data("markup".utf8), to: &canonical)
            Self.appendComponent(Data(text.utf8), to: &canonical)
        case .phonemes(let phonemes):
            Self.appendComponent(Data("phonemes".utf8), to: &canonical)
            canonical.append(UInt64(phonemes.count).littleEndianData)
            for phoneme in phonemes {
                Self.appendComponent(Data(phoneme.symbol.utf8), to: &canonical)
                canonical.append(UInt64(bitPattern: Int64(phoneme.stress)).littleEndianData)
            }
        }
        Self.appendComponent(Data(voice.identifier.utf8), to: &canonical)
        canonical.append(UInt64(bitPattern: Int64(audioFormat.sampleRate)).littleEndianData)
        canonical.append(UInt64(bitPattern: Int64(audioFormat.channels)).littleEndianData)
        canonical.append(UInt64(bitPattern: Int64(audioFormat.bitDepth)).littleEndianData)
        canonical.append(parameters.pitchShift.bitPattern.littleEndianData)
        canonical.append(parameters.rate.bitPattern.littleEndianData)
        canonical.append(parameters.emotionalIntensity.bitPattern.littleEndianData)
        canonical.append(parameters.breathiness.bitPattern.littleEndianData)
        canonical.append(parameters.ageShift.bitPattern.littleEndianData)
        canonical.append(parameters.genderShift.bitPattern.littleEndianData)
        if let seed = parameters.seed {
            canonical.append(1)
            canonical.append(seed.littleEndianData)
        } else {
            canonical.append(0)
            // Unseeded synthesis intentionally varies. A nonce prevents two
            // unrelated outputs from aliasing as a reusable deterministic hit.
            Self.appendComponent(Data(UUID().uuidString.utf8), to: &canonical)
        }
        canonical.append(engineVersion.littleEndianData)
        self.digest = SHA256Digest.hexDigest(canonical)
    }

    /// Creates a key for expert phoneme-plus-prosody input, including every
    /// aligned contour and word-boundary value that can affect output.
    public init(
        phonemeProsody: PhonemeProsodySequence,
        voice: Voice,
        parameters: SynthesisParameters,
        audioFormat: AudioFormat = AudioFormat(),
        engineVersion: UInt64 = Choir.engineVersion
    ) {
        let parameters = parameters.validated()
        var canonical = Data()
        Self.appendComponent(Data("phoneme-prosody".utf8), to: &canonical)
        canonical.append(UInt64(phonemeProsody.phonemes.count).littleEndianData)
        for phoneme in phonemeProsody.phonemes {
            Self.appendComponent(Data(phoneme.symbol.utf8), to: &canonical)
            canonical.append(UInt64(bitPattern: Int64(phoneme.stress)).littleEndianData)
        }
        if let durations = phonemeProsody.durationsMs {
            canonical.append(1)
            canonical.append(UInt64(durations.count).littleEndianData)
            durations.forEach { canonical.append($0.bitPattern.littleEndianData) }
        } else {
            canonical.append(0)
        }
        if let pitches = phonemeProsody.pitchTargetsHz {
            canonical.append(1)
            canonical.append(UInt64(pitches.count).littleEndianData)
            pitches.forEach { canonical.append($0.bitPattern.littleEndianData) }
        } else {
            canonical.append(0)
        }
        canonical.append(UInt64(phonemeProsody.wordBoundaries.count).littleEndianData)
        phonemeProsody.wordBoundaries.forEach {
            canonical.append(UInt64(bitPattern: Int64($0)).littleEndianData)
        }
        canonical.append(UInt64(phonemeProsody.wordTexts.count).littleEndianData)
        for word in phonemeProsody.wordTexts {
            Self.appendComponent(Data(word.utf8), to: &canonical)
        }
        canonical.append(parameters.pitchShift.bitPattern.littleEndianData)
        canonical.append(parameters.rate.bitPattern.littleEndianData)
        canonical.append(parameters.emotionalIntensity.bitPattern.littleEndianData)
        canonical.append(parameters.breathiness.bitPattern.littleEndianData)
        canonical.append(parameters.ageShift.bitPattern.littleEndianData)
        canonical.append(parameters.genderShift.bitPattern.littleEndianData)
        self.init(
            text: "",
            voiceID: voice.identifier,
            canonicalParameters: canonical,
            seed: parameters.seed,
            audioFormat: audioFormat,
            engineVersion: engineVersion)
    }

    /// Creates a key when a caller owns additional parameter types. The
    /// caller is responsible for making `canonicalParameters` deterministic.
    public init(
        text: String,
        voiceID: String,
        canonicalParameters: Data,
        seed: UInt64?,
        audioFormat: AudioFormat = AudioFormat(),
        engineVersion: UInt64 = Choir.engineVersion
    ) {
        var canonical = Data()
        Self.appendComponent(Data(text.utf8), to: &canonical)
        Self.appendComponent(Data(voiceID.utf8), to: &canonical)
        Self.appendComponent(canonicalParameters, to: &canonical)
        canonical.append(UInt64(bitPattern: Int64(audioFormat.sampleRate)).littleEndianData)
        canonical.append(UInt64(bitPattern: Int64(audioFormat.channels)).littleEndianData)
        canonical.append(UInt64(bitPattern: Int64(audioFormat.bitDepth)).littleEndianData)
        if let seed {
            canonical.append(1)
            canonical.append(seed.littleEndianData)
        } else {
            canonical.append(0)
            Self.appendComponent(Data(UUID().uuidString.utf8), to: &canonical)
        }
        canonical.append(engineVersion.littleEndianData)
        self.digest = SHA256Digest.hexDigest(canonical)
    }

    /// Rehydrates a persisted key only when it is a valid SHA-256 hex digest.
    public init?(digest: String) {
        let normalized = digest.lowercased()
        guard normalized.utf8.count == 64,
              normalized.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }) else { return nil }
        self.digest = normalized
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let digest = try container.decode(String.self)
        guard let validated = Self(digest: digest) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected a 64-character SHA-256 digest")
        }
        self = validated
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(digest)
    }

    private static func appendComponent(_ component: Data, to data: inout Data) {
        data.append(UInt64(component.count).littleEndianData)
        data.append(component)
    }
}

public struct SynthesisAudioCacheConfiguration: Sendable, Equatable {
    public var maximumSizeBytes: Int
    public var cacheDirectory: URL?
    public var applicationSupportDirectory: URL?
    public var pinnedItemsAreBackedUp: Bool

    public init(
        maximumSizeBytes: Int = 500 * 1_024 * 1_024,
        cacheDirectory: URL? = nil,
        applicationSupportDirectory: URL? = nil,
        pinnedItemsAreBackedUp: Bool = true
    ) {
        self.maximumSizeBytes = maximumSizeBytes
        self.cacheDirectory = cacheDirectory
        self.applicationSupportDirectory = applicationSupportDirectory
        self.pinnedItemsAreBackedUp = pinnedItemsAreBackedUp
    }
}

public struct SynthesisAudioCacheStatistics: Sendable, Equatable {
    public let itemCount: Int
    public let pinnedItemCount: Int
    public let currentSizeBytes: Int
    public let maximumSizeBytes: Int
    public let hitCount: UInt64
    public let missCount: UInt64

    public var remainingCapacityBytes: Int {
        max(0, maximumSizeBytes - currentSizeBytes)
    }

    public var hitRate: Double {
        let requests = hitCount + missCount
        guard requests > 0 else { return 0 }
        return Double(hitCount) / Double(requests)
    }
}

/// Typed persistent-cache failures; callers can distinguish capacity,
/// corruption, and storage failures without matching message text.
public enum SynthesisAudioCacheError: Error, Sendable, Equatable {
    case invalidConfiguration(String)
    case capacityExceeded(requiredBytes: Int, maximumBytes: Int)
    case corruptEntry(key: String, reason: String)
    case storageFailure(String)
}

extension SynthesisAudioCacheError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason): return reason
        case .capacityExceeded(let required, let maximum):
            return "Cache needs \(required) bytes but its limit is \(maximum) bytes"
        case .corruptEntry(let key, let reason):
            return "Corrupt cache entry \(key): \(reason)"
        case .storageFailure(let reason):
            return "Cache storage failed: \(reason)"
        }
    }
}

/// Disk-backed, content-addressed rendered-audio cache.
///
/// Unpinned entries live in Caches and are excluded from backup. Pinned
/// entries live in Application Support and are never selected for LRU
/// eviction. Neither path includes the package version; output compatibility
/// is governed solely by the engine-version component of ``SynthesisCacheKey``.
public actor SynthesisAudioCache: Sendable {
    private let manager: FileManager
    private let cacheDirectory: URL
    private let pinnedDirectory: URL
    private let directoryLock: NSRecursiveLock
    private let maximumSizeBytes: Int
    private var entries: [String: CacheEntryRecord]
    private var hitCount: UInt64 = 0
    private var missCount: UInt64 = 0
    private var lastAccessDate: Date

    public init(configuration: SynthesisAudioCacheConfiguration = .init()) throws {
        guard configuration.maximumSizeBytes >= 0 else {
            throw SynthesisAudioCacheError.invalidConfiguration(
                "Maximum cache size must not be negative")
        }
        let manager = FileManager.default
        let ordinaryBase = configuration.cacheDirectory
            ?? manager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let pinnedBase = configuration.applicationSupportDirectory
            ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? manager.temporaryDirectory
        let cacheDirectory = ordinaryBase
            .appendingPathComponent("Choir", isDirectory: true)
            .appendingPathComponent("Synthesis", isDirectory: true)
        let pinnedDirectory = pinnedBase
            .appendingPathComponent("Choir", isDirectory: true)
            .appendingPathComponent("PinnedSynthesis", isDirectory: true)
        let directoryLock = CacheDirectoryLockRegistry.shared.lock(
            ordinaryDirectory: cacheDirectory,
            pinnedDirectory: pinnedDirectory)

        directoryLock.lock()
        defer { directoryLock.unlock() }
        do {
            try manager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            try manager.createDirectory(at: pinnedDirectory, withIntermediateDirectories: true)
            Self.configureBackupExclusion(cacheDirectory, excluded: true)
            Self.configureBackupExclusion(
                pinnedDirectory, excluded: !configuration.pinnedItemsAreBackedUp)
            let scannedRecords = try Self.scan(
                manager: manager,
                ordinaryDirectory: cacheDirectory,
                pinnedDirectory: pinnedDirectory)
            let records = try Self.enforceCapacity(
                scannedRecords,
                maximumSizeBytes: configuration.maximumSizeBytes,
                manager: manager,
                ordinaryDirectory: cacheDirectory,
                pinnedDirectory: pinnedDirectory)
            self.manager = manager
            self.cacheDirectory = cacheDirectory
            self.pinnedDirectory = pinnedDirectory
            self.directoryLock = directoryLock
            self.maximumSizeBytes = configuration.maximumSizeBytes
            self.entries = records
            self.lastAccessDate = records.values.map(\.lastAccess).max() ?? .distantPast
        } catch let error as SynthesisAudioCacheError {
            throw error
        } catch {
            throw SynthesisAudioCacheError.storageFailure(error.localizedDescription)
        }
    }

    /// Returns cached PCM and refreshes its persistent LRU timestamp.
    public func audio(for key: SynthesisCacheKey) throws -> AudioBuffer? {
        try withDirectoryLock {
            try refreshEntriesLocked()
            guard var record = entries[key.digest] else {
                missCount &+= 1
                return nil
            }
            let storedAudioURL = audioURL(for: record)
            guard manager.fileExists(atPath: storedAudioURL.path) else {
                // The OS may purge Caches independently of this actor. Treat
                // that as an ordinary stale miss so the caller can recompute.
                entries.removeValue(forKey: key.digest)
                try? manager.removeItem(at: metadataURL(for: record))
                missCount &+= 1
                return nil
            }
            do {
                let data = try Data(contentsOf: storedAudioURL)
                guard data.count == record.byteCount else {
                    throw SynthesisAudioCacheError.corruptEntry(
                        key: key.digest,
                        reason: "Stored byte count does not match metadata")
                }
                let audio = try AudioCacheCodec.decode(data, key: key.digest)
                record.lastAccess = nextAccessDate()
                try writeMetadata(record)
                entries[key.digest] = record
                hitCount &+= 1
                return audio
            } catch let error as SynthesisAudioCacheError {
                throw error
            } catch {
                throw SynthesisAudioCacheError.storageFailure(error.localizedDescription)
            }
        }
    }

    /// Stores or replaces one render, evicting the oldest unpinned values as
    /// necessary. The write is atomic at the individual-file level.
    public func store(
        _ audio: AudioBuffer,
        for key: SynthesisCacheKey,
        pinned: Bool = false
    ) throws {
        let encoded = try AudioCacheCodec.encode(audio)
        try withDirectoryLock {
            try refreshEntriesLocked()
            let existing = entries[key.digest]
            try ensureCapacity(
                resultingByteCount: encoded.count,
                replacing: existing,
                preserving: key.digest)
            let targetPinned = pinned || existing?.isPinned == true
            let accessDate = nextAccessDate()
            let record = CacheEntryRecord(
                digest: key.digest,
                byteCount: encoded.count,
                createdAt: existing?.createdAt ?? accessDate,
                lastAccess: accessDate,
                isPinned: targetPinned)
            do {
                let destinationAudioURL = audioURL(for: record)
                try encoded.write(to: destinationAudioURL, options: .atomic)
                try writeMetadata(record)
                if let existing, existing.isPinned != record.isPinned {
                    try? manager.removeItem(at: audioURL(for: existing))
                    try? manager.removeItem(at: metadataURL(for: existing))
                }
                entries[key.digest] = record
            } catch let error as SynthesisAudioCacheError {
                throw error
            } catch {
                throw SynthesisAudioCacheError.storageFailure(error.localizedDescription)
            }
        }
    }

    public func contains(_ key: SynthesisCacheKey) -> Bool {
        withDirectoryLockBestEffort {
            try refreshEntriesLocked()
            return entries[key.digest] != nil
        } fallback: {
            entries[key.digest] != nil
        }
    }

    public var cachedDigests: [String] {
        withDirectoryLockBestEffort {
            try refreshEntriesLocked()
            return entries.keys.sorted()
        } fallback: {
            entries.keys.sorted()
        }
    }

    /// Moves a value between Caches and Application Support without changing
    /// its content-addressed identity.
    @discardableResult
    public func setPinned(_ shouldPin: Bool, for key: SynthesisCacheKey) throws -> Bool {
        try withDirectoryLock {
            try refreshEntriesLocked()
            guard var record = entries[key.digest] else { return false }
            guard record.isPinned != shouldPin else { return true }
            let oldRecord = record
            do {
                let data = try Data(contentsOf: audioURL(for: oldRecord))
                record.isPinned = shouldPin
                record.lastAccess = nextAccessDate()
                try data.write(to: audioURL(for: record), options: .atomic)
                try writeMetadata(record)
                try? manager.removeItem(at: audioURL(for: oldRecord))
                try? manager.removeItem(at: metadataURL(for: oldRecord))
                entries[key.digest] = record
                return true
            } catch {
                throw SynthesisAudioCacheError.storageFailure(error.localizedDescription)
            }
        }
    }

    @discardableResult
    public func remove(_ key: SynthesisCacheKey) throws -> Bool {
        try withDirectoryLock {
            try refreshEntriesLocked()
            guard let record = entries[key.digest] else { return false }
            try remove(record)
            return true
        }
    }

    /// Selective purge for a set of known content keys.
    @discardableResult
    public func remove(_ keys: [SynthesisCacheKey]) throws -> Int {
        try withDirectoryLock {
            try refreshEntriesLocked()
            var removed = 0
            for key in keys {
                guard let record = entries[key.digest] else { continue }
                try remove(record)
                removed += 1
            }
            return removed
        }
    }

    /// Full purge. Callers can retain app-critical pinned audio when desired.
    @discardableResult
    public func removeAll(includingPinned: Bool = true) throws -> Int {
        try withDirectoryLock {
            try refreshEntriesLocked()
            let victims = entries.values.filter { includingPinned || !$0.isPinned }
            for record in victims { try remove(record) }
            return victims.count
        }
    }

    public func statistics() -> SynthesisAudioCacheStatistics {
        withDirectoryLockBestEffort {
            try refreshEntriesLocked()
            return makeStatistics()
        } fallback: {
            makeStatistics()
        }
    }

    private func makeStatistics() -> SynthesisAudioCacheStatistics {
        SynthesisAudioCacheStatistics(
            itemCount: entries.count,
            pinnedItemCount: entries.values.filter(\.isPinned).count,
            currentSizeBytes: entries.values.reduce(0) { $0 + $1.byteCount },
            maximumSizeBytes: maximumSizeBytes,
            hitCount: hitCount,
            missCount: missCount)
    }

    private func refreshEntriesLocked() throws {
        let scanned = try Self.scan(
            manager: manager,
            ordinaryDirectory: cacheDirectory,
            pinnedDirectory: pinnedDirectory)
        entries = try Self.enforceCapacity(
            scanned,
            maximumSizeBytes: maximumSizeBytes,
            manager: manager,
            ordinaryDirectory: cacheDirectory,
            pinnedDirectory: pinnedDirectory)
        if let latest = entries.values.map(\.lastAccess).max(), latest > lastAccessDate {
            lastAccessDate = latest
        }
    }

    private func withDirectoryLock<T>(_ body: () throws -> T) throws -> T {
        directoryLock.lock()
        defer { directoryLock.unlock() }
        return try body()
    }

    private func withDirectoryLockBestEffort<T>(
        _ body: () throws -> T,
        fallback: () -> T
    ) -> T {
        directoryLock.lock()
        defer { directoryLock.unlock() }
        return (try? body()) ?? fallback()
    }

    private func ensureCapacity(
        resultingByteCount: Int,
        replacing existing: CacheEntryRecord?,
        preserving digest: String
    ) throws {
        guard resultingByteCount <= maximumSizeBytes else {
            throw SynthesisAudioCacheError.capacityExceeded(
                requiredBytes: resultingByteCount, maximumBytes: maximumSizeBytes)
        }
        var resultingTotal = entries.values.reduce(0) { $0 + $1.byteCount }
            - (existing?.byteCount ?? 0) + resultingByteCount
        let candidates = entries.values
            .filter { !$0.isPinned && $0.digest != digest }
            .sorted {
                if $0.lastAccess == $1.lastAccess { return $0.digest < $1.digest }
                return $0.lastAccess < $1.lastAccess
            }
        for candidate in candidates where resultingTotal > maximumSizeBytes {
            try remove(candidate)
            resultingTotal -= candidate.byteCount
        }
        guard resultingTotal <= maximumSizeBytes else {
            throw SynthesisAudioCacheError.capacityExceeded(
                requiredBytes: resultingTotal, maximumBytes: maximumSizeBytes)
        }
    }

    private func remove(_ record: CacheEntryRecord) throws {
        do {
            let audio = audioURL(for: record)
            let metadata = metadataURL(for: record)
            if manager.fileExists(atPath: audio.path) { try manager.removeItem(at: audio) }
            if manager.fileExists(atPath: metadata.path) { try manager.removeItem(at: metadata) }
            entries.removeValue(forKey: record.digest)
        } catch {
            throw SynthesisAudioCacheError.storageFailure(error.localizedDescription)
        }
    }

    private func audioURL(for record: CacheEntryRecord) -> URL {
        directory(for: record).appendingPathComponent(record.digest + ".choirpcm")
    }

    private func metadataURL(for record: CacheEntryRecord) -> URL {
        directory(for: record).appendingPathComponent(record.digest + ".json")
    }

    private func directory(for record: CacheEntryRecord) -> URL {
        record.isPinned ? pinnedDirectory : cacheDirectory
    }

    private func writeMetadata(_ record: CacheEntryRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: metadataURL(for: record), options: .atomic)
    }

    private func nextAccessDate() -> Date {
        let now = Date()
        let next = now > lastAccessDate ? now : lastAccessDate.addingTimeInterval(0.000_001)
        lastAccessDate = next
        return next
    }

    private static func scan(
        manager: FileManager,
        ordinaryDirectory: URL,
        pinnedDirectory: URL
    ) throws -> [String: CacheEntryRecord] {
        var records: [String: CacheEntryRecord] = [:]
        let decoder = JSONDecoder()
        for (directory, expectedPinned) in [(ordinaryDirectory, false), (pinnedDirectory, true)] {
            let urls = try manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles])
            var retainedAudioNames: Set<String> = []
            for url in urls where url.pathExtension == "json" {
                let fileDigest = url.deletingPathExtension().lastPathComponent
                guard let record = try? decoder.decode(
                    CacheEntryRecord.self, from: Data(contentsOf: url)),
                      record.digest == fileDigest,
                      record.isPinned == expectedPinned,
                      SynthesisCacheKey(digest: record.digest) != nil else {
                    try? manager.removeItem(at: url)
                    if SynthesisCacheKey(digest: fileDigest) != nil {
                        try? manager.removeItem(at: directory.appendingPathComponent(
                            fileDigest + ".choirpcm"))
                    }
                    continue
                }
                let audioName = record.digest + ".choirpcm"
                let audio = directory.appendingPathComponent(audioName)
                guard manager.fileExists(atPath: audio.path),
                      let attributes = try? manager.attributesOfItem(atPath: audio.path),
                      let actualSize = attributes[.size] as? NSNumber,
                      actualSize.intValue == record.byteCount else {
                    try? manager.removeItem(at: url)
                    try? manager.removeItem(at: audio)
                    continue
                }
                retainedAudioNames.insert(audioName)
                // Startup reads only small metadata and filesystem sizes.
                // Payload bytes and codec/header integrity are checked lazily
                // by audio(for:), avoiding a synchronous read of the entire
                // cache (which may be hundreds of megabytes) in init.
                if let prior = records[record.digest] {
                    records[record.digest] = prior.lastAccess >= record.lastAccess ? prior : record
                } else {
                    records[record.digest] = record
                }
            }
            // Interrupted atomic writes and external purges can leave payloads
            // without metadata. They can never be addressed safely, so reclaim
            // them during the same coordinated scan.
            for url in urls where url.pathExtension == "choirpcm"
                && !retainedAudioNames.contains(url.lastPathComponent) {
                try? manager.removeItem(at: url)
            }
        }
        return records
    }

    private static func configureBackupExclusion(_ directory: URL, excluded: Bool) {
#if canImport(Darwin)
        var mutableDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        try? mutableDirectory.setResourceValues(values)
#else
        _ = directory
        _ = excluded
#endif
    }

    private static func enforceCapacity(
        _ records: [String: CacheEntryRecord],
        maximumSizeBytes: Int,
        manager: FileManager,
        ordinaryDirectory: URL,
        pinnedDirectory: URL
    ) throws -> [String: CacheEntryRecord] {
        let pinnedBytes = records.values
            .filter(\.isPinned)
            .reduce(0) { $0 + $1.byteCount }
        guard pinnedBytes <= maximumSizeBytes else {
            throw SynthesisAudioCacheError.capacityExceeded(
                requiredBytes: pinnedBytes, maximumBytes: maximumSizeBytes)
        }
        var retained = records
        var total = records.values.reduce(0) { $0 + $1.byteCount }
        let candidates = records.values.filter { !$0.isPinned }.sorted {
            if $0.lastAccess == $1.lastAccess { return $0.digest < $1.digest }
            return $0.lastAccess < $1.lastAccess
        }
        for candidate in candidates where total > maximumSizeBytes {
            let directory = candidate.isPinned ? pinnedDirectory : ordinaryDirectory
            let audio = directory.appendingPathComponent(candidate.digest + ".choirpcm")
            let metadata = directory.appendingPathComponent(candidate.digest + ".json")
            if manager.fileExists(atPath: audio.path) { try manager.removeItem(at: audio) }
            if manager.fileExists(atPath: metadata.path) { try manager.removeItem(at: metadata) }
            retained.removeValue(forKey: candidate.digest)
            total -= candidate.byteCount
        }
        return retained
    }
}

/// Coordinates cache actors that target the same pair of directories inside
/// one process. The lock covers refresh, LRU selection, and mutation as one
/// transaction so independently-created actors cannot overwrite one another's
/// view or exceed the shared capacity between scans.
private final class CacheDirectoryLockRegistry: @unchecked Sendable {
    static let shared = CacheDirectoryLockRegistry()

    private let registryLock = NSLock()
    private var locks: [String: NSRecursiveLock] = [:]

    func lock(ordinaryDirectory: URL, pinnedDirectory: URL) -> NSRecursiveLock {
        let key = ordinaryDirectory.standardizedFileURL.path + "\0"
            + pinnedDirectory.standardizedFileURL.path
        registryLock.lock()
        defer { registryLock.unlock() }
        if let existing = locks[key] { return existing }
        let created = NSRecursiveLock()
        locks[key] = created
        return created
    }
}

private struct CacheEntryRecord: Codable {
    let digest: String
    let byteCount: Int
    var createdAt: Date
    var lastAccess: Date
    var isPinned: Bool
}

private enum AudioCacheCodec {
    private static let magic = Array("CHOIRPCM".utf8)
    private static let version: UInt16 = 1
    private static let headerSize = 28

    static func encode(_ audio: AudioBuffer) throws -> Data {
        try audio.validate()
        let byteCount = audio.samples.count.multipliedReportingOverflow(by: 2)
        guard !byteCount.overflow else {
            throw SynthesisAudioCacheError.storageFailure("PCM sample count overflow")
        }
        var data = Data()
        data.reserveCapacity(headerSize + byteCount.partialValue)
        data.append(contentsOf: magic)
        data.append(version.littleEndianData)
        data.append(UInt16(0).littleEndianData)
        data.append(UInt32(audio.format.sampleRate).littleEndianData)
        data.append(UInt16(audio.format.channels).littleEndianData)
        data.append(UInt16(audio.format.bitDepth).littleEndianData)
        data.append(UInt64(audio.samples.count).littleEndianData)
        for sample in audio.samples { data.append(sample.littleEndianData) }
        return data
    }

    static func decode(_ data: Data, key: String) throws -> AudioBuffer {
        let bytes = [UInt8](data)
        guard bytes.count >= headerSize,
              Array(bytes[0..<magic.count]) == magic else {
            throw SynthesisAudioCacheError.corruptEntry(key: key, reason: "Invalid PCM header")
        }
        let version = readUInt16(bytes, at: 8)
        guard version == Self.version else {
            throw SynthesisAudioCacheError.corruptEntry(
                key: key, reason: "Unsupported PCM cache version \(version)")
        }
        let sampleRate = Int(readUInt32(bytes, at: 12))
        let channels = Int(readUInt16(bytes, at: 16))
        let bitDepth = Int(readUInt16(bytes, at: 18))
        let sampleCount64 = readUInt64(bytes, at: 20)
        guard sampleCount64 <= UInt64((Int.max - headerSize) / 2) else {
            throw SynthesisAudioCacheError.corruptEntry(key: key, reason: "PCM length overflow")
        }
        let sampleCount = Int(sampleCount64)
        guard bytes.count == headerSize + sampleCount * 2 else {
            throw SynthesisAudioCacheError.corruptEntry(
                key: key, reason: "PCM payload length does not match header")
        }
        var samples: [Int16] = []
        samples.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let offset = headerSize + index * 2
            let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
            samples.append(Int16(bitPattern: bits))
        }
        let audio = AudioBuffer(
            samples: samples,
            format: AudioFormat(sampleRate: sampleRate, channels: channels, bitDepth: bitDepth))
        do {
            try audio.validate()
            return audio
        } catch {
            throw SynthesisAudioCacheError.corruptEntry(
                key: key, reason: "Cached PCM format is invalid")
        }
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    private static func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for shift in 0..<8 { value |= UInt64(bytes[offset + shift]) << UInt64(shift * 8) }
        return value
    }
}

private enum SHA256Digest {
    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hexDigest(_ data: Data) -> String {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var hash: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        var words = [UInt32](repeating: 0, count: 64)
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for index in 0..<16 {
                let offset = chunkStart + index * 4
                words[index] = UInt32(message[offset]) << 24
                    | UInt32(message[offset + 1]) << 16
                    | UInt32(message[offset + 2]) << 8
                    | UInt32(message[offset + 3])
            }
            for index in 16..<64 {
                let s0 = rotateRight(words[index - 15], by: 7)
                    ^ rotateRight(words[index - 15], by: 18)
                    ^ (words[index - 15] >> 3)
                let s1 = rotateRight(words[index - 2], by: 17)
                    ^ rotateRight(words[index - 2], by: 19)
                    ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]
            for index in 0..<64 {
                let sum1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let choice = (e & f) ^ ((~e) & g)
                let temporary1 = h &+ sum1 &+ choice &+ constants[index] &+ words[index]
                let sum0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temporary2 = sum0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temporary1
                d = c
                c = b
                b = a
                a = temporary1 &+ temporary2
            }
            hash[0] &+= a
            hash[1] &+= b
            hash[2] &+= c
            hash[3] &+= d
            hash[4] &+= e
            hash[5] &+= f
            hash[6] &+= g
            hash[7] &+= h
        }
        return hash.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotateRight(_ value: UInt32, by count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }
}
