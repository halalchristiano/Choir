import Foundation

/// Cache for model assets and synthesis data.
public actor AssetCache: Sendable {
    /// Cached acoustic features by text hash.
    private var featureCache: [String: AcousticFeatures] = [:]

    /// Cached phonetic transcriptions by text hash.
    private var transcriptionCache: [String: PhoneticTranscription] = [:]

    /// Cached prosody predictions.
    private var prosodyCache: [String: ProsodyDescription] = [:]

    /// Maximum cache size in bytes (100 MB default).
    private var maxCacheSize: Int

    /// Current cache size in bytes.
    private var currentCacheSize: Int = 0

    /// Exact estimated sizes for replacement-safe accounting.
    private var featureSizes: [String: Int] = [:]
    private var transcriptionSizes: [String: Int] = [:]
    private var prosodySizes: [String: Int] = [:]

    /// Monotonic access sequence for deterministic LRU eviction.
    private var accessOrder: [String: UInt64] = [:]
    private var accessSequence: UInt64 = 0

    /// App-critical values are never selected for automatic eviction.
    private var pinned: Set<String> = []

    public init(maxCacheSize: Int = 100 * 1024 * 1024) {
        self.maxCacheSize = max(0, maxCacheSize)
    }

    /// Stores acoustic features in cache.
    public func cacheAcousticFeatures(_ features: AcousticFeatures, for key: String) {
        let size = features.frameCount * features.frequencyBins * MemoryLayout<Float>.size
        let replacedBytes = featureSizes[key] ?? 0
        guard ensureSpace(size, replacing: replacedBytes, preserving: key) else { return }
        removeFeature(for: key)

        featureCache[key] = features
        featureSizes[key] = size
        currentCacheSize += size
        touch(key)
    }

    /// Retrieves cached acoustic features.
    public func getAcousticFeatures(for key: String) -> AcousticFeatures? {
        guard let value = featureCache[key] else { return nil }
        touch(key)
        return value
    }

    /// Stores transcription in cache.
    public func cacheTranscription(_ transcript: PhoneticTranscription, for key: String) {
        let size = transcript.phonemes.count * 64  // Rough estimate
        let replacedBytes = transcriptionSizes[key] ?? 0
        guard ensureSpace(size, replacing: replacedBytes, preserving: key) else { return }
        removeTranscription(for: key)

        transcriptionCache[key] = transcript
        transcriptionSizes[key] = size
        currentCacheSize += size
        touch(key)
    }

    /// Retrieves cached transcription.
    public func getTranscription(for key: String) -> PhoneticTranscription? {
        guard let value = transcriptionCache[key] else { return nil }
        touch(key)
        return value
    }

    /// Stores prosody prediction in cache.
    public func cacheProsody(_ prosody: ProsodyDescription, for key: String) {
        let size = prosody.phonemes.count * 128  // Rough estimate
        let replacedBytes = prosodySizes[key] ?? 0
        guard ensureSpace(size, replacing: replacedBytes, preserving: key) else { return }
        removeProsody(for: key)

        prosodyCache[key] = prosody
        prosodySizes[key] = size
        currentCacheSize += size
        touch(key)
    }

    /// Retrieves cached prosody prediction.
    public func getProsody(for key: String) -> ProsodyDescription? {
        guard let value = prosodyCache[key] else { return nil }
        touch(key)
        return value
    }

    public func containsAcousticFeatures(for key: String) -> Bool {
        featureCache[key] != nil
    }

    public func containsTranscription(for key: String) -> Bool {
        transcriptionCache[key] != nil
    }

    public func containsProsody(for key: String) -> Bool {
        prosodyCache[key] != nil
    }

    /// Removes every cached representation stored under `key`.
    @discardableResult
    public func removeValue(for key: String) -> Bool {
        let existed = featureCache[key] != nil || transcriptionCache[key] != nil || prosodyCache[key] != nil
        removeFeature(for: key)
        removeTranscription(for: key)
        removeProsody(for: key)
        accessOrder.removeValue(forKey: key)
        pinned.remove(key)
        return existed
    }

    /// Prevents an existing key from being selected by LRU eviction.
    @discardableResult
    public func pin(_ key: String) -> Bool {
        guard isStored(key) else { return false }
        pinned.insert(key)
        touch(key)
        return true
    }

    /// Makes a pinned key eligible for LRU eviction again.
    @discardableResult
    public func unpin(_ key: String) -> Bool {
        pinned.remove(key) != nil
    }

    public func isPinned(_ key: String) -> Bool { pinned.contains(key) }

    public var pinnedKeys: [String] { pinned.sorted() }

    /// Changes the byte cap without silently discarding pinned values.
    public func setMaximumCacheSize(_ bytes: Int) throws {
        guard bytes >= 0 else {
            throw ChoirError.invalidParameter(
                parameter: "bytes", reason: "Cache size must not be negative")
        }
        let pinnedBytes = pinned.reduce(0) { $0 + size(for: $1) }
        guard pinnedBytes <= bytes else {
            throw ChoirError.invalidParameter(
                parameter: "bytes", reason: "The new limit is smaller than pinned cache data")
        }
        maxCacheSize = bytes
        while currentCacheSize > maxCacheSize {
            guard evictLRUItem() else { break }
        }
    }

    /// Keys currently represented in at least one cache, in stable order.
    public var cachedKeys: [String] {
        Set(featureCache.keys)
            .union(transcriptionCache.keys)
            .union(prosodyCache.keys)
            .sorted()
    }

    /// Clears all caches.
    public func clear() {
        featureCache.removeAll()
        transcriptionCache.removeAll()
        prosodyCache.removeAll()
        featureSizes.removeAll()
        transcriptionSizes.removeAll()
        prosodySizes.removeAll()
        accessOrder.removeAll()
        pinned.removeAll()
        accessSequence = 0
        currentCacheSize = 0
    }

    /// Returns cache statistics.
    public func getStatistics() -> CacheStatistics {
        CacheStatistics(
            featureCount: featureCache.count,
            transcriptionCount: transcriptionCache.count,
            prosodyCount: prosodyCache.count,
            currentSizeBytes: currentCacheSize,
            maxSizeBytes: maxCacheSize,
            pinnedKeyCount: pinned.count
        )
    }

    /// Ensures there's enough space for new data using LRU eviction.
    private func ensureSpace(
        _ requiredBytes: Int,
        replacing replacedBytes: Int,
        preserving key: String
    ) -> Bool {
        guard requiredBytes >= 0, requiredBytes <= maxCacheSize else { return false }

        while currentCacheSize - replacedBytes + requiredBytes > maxCacheSize {
            guard evictLRUItem(excluding: key) else { return false }
        }
        return currentCacheSize - replacedBytes + requiredBytes <= maxCacheSize
    }

    /// Evicts the least recently used item.
    @discardableResult
    private func evictLRUItem(excluding protectedKey: String? = nil) -> Bool {
        guard let lruKey = accessOrder
            .filter({ !pinned.contains($0.key) && $0.key != protectedKey })
            .min(by: { $0.value < $1.value })?.key else { return false }

        // Remove from all caches
        removeFeature(for: lruKey)
        removeTranscription(for: lruKey)
        removeProsody(for: lruKey)

        accessOrder.removeValue(forKey: lruKey)
        return true
    }

    private func removeFeature(for key: String) {
        featureCache.removeValue(forKey: key)
        currentCacheSize -= featureSizes.removeValue(forKey: key) ?? 0
        currentCacheSize = max(0, currentCacheSize)
    }

    private func removeTranscription(for key: String) {
        transcriptionCache.removeValue(forKey: key)
        currentCacheSize -= transcriptionSizes.removeValue(forKey: key) ?? 0
        currentCacheSize = max(0, currentCacheSize)
    }

    private func removeProsody(for key: String) {
        prosodyCache.removeValue(forKey: key)
        currentCacheSize -= prosodySizes.removeValue(forKey: key) ?? 0
        currentCacheSize = max(0, currentCacheSize)
    }

    private func isStored(_ key: String) -> Bool {
        featureCache[key] != nil || transcriptionCache[key] != nil || prosodyCache[key] != nil
    }

    private func size(for key: String) -> Int {
        (featureSizes[key] ?? 0)
            + (transcriptionSizes[key] ?? 0)
            + (prosodySizes[key] ?? 0)
    }

    private func touch(_ key: String) {
        accessSequence &+= 1
        if accessSequence == 0 {
            // Overflow is fantastically unlikely, but rebuilding the order is
            // safer than allowing newly accessed values to appear oldest.
            let ordered = accessOrder.sorted { $0.value < $1.value }.map(\.key)
            accessOrder.removeAll(keepingCapacity: true)
            for (index, existingKey) in ordered.enumerated() {
                accessOrder[existingKey] = UInt64(index + 1)
            }
            accessSequence = UInt64(ordered.count + 1)
        }
        accessOrder[key] = accessSequence
    }
}

/// Cache statistics.
public struct CacheStatistics: Sendable, Equatable {
    /// Number of cached acoustic features.
    public let featureCount: Int

    /// Number of cached transcriptions.
    public let transcriptionCount: Int

    /// Number of cached prosody predictions.
    public let prosodyCount: Int

    /// Current cache size in bytes.
    public let currentSizeBytes: Int

    /// Maximum cache size in bytes.
    public let maxSizeBytes: Int

    /// Number of logical keys protected from LRU eviction.
    public let pinnedKeyCount: Int

    /// Cache utilization as percentage.
    public var utilizationPercent: Double {
        guard maxSizeBytes > 0 else { return 0 }
        return min(100, max(0, Double(currentSizeBytes) / Double(maxSizeBytes) * 100))
    }

    /// Capacity still available under the configured limit.
    public var remainingCapacityBytes: Int {
        max(0, maxSizeBytes - currentSizeBytes)
    }

    /// Whether no entries are currently cached.
    public var isEmpty: Bool {
        featureCount == 0 && transcriptionCount == 0 && prosodyCount == 0
    }

    /// Total values across the three typed caches.
    public var totalCount: Int {
        featureCount + transcriptionCount + prosodyCount
    }

    /// Utilization as a 0...1 fraction.
    public var utilizationFraction: Double {
        utilizationPercent / 100
    }

    /// Whether no additional byte can fit under the configured limit.
    public var isAtCapacity: Bool {
        maxSizeBytes == 0 || currentSizeBytes >= maxSizeBytes
    }
}
