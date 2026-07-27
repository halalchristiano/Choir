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
    private let maxCacheSize: Int

    /// Current cache size in bytes.
    private var currentCacheSize: Int = 0

    /// Creation and last-access timestamps for LRU eviction.
    private var accessTimes: [String: Date] = [:]

    public init(maxCacheSize: Int = 100 * 1024 * 1024) {
        self.maxCacheSize = maxCacheSize
    }

    /// Stores acoustic features in cache.
    public func cacheAcousticFeatures(_ features: AcousticFeatures, for key: String) {
        let size = features.frameCount * features.frequencyBins * MemoryLayout<Float>.size
        ensureSpace(size)

        featureCache[key] = features
        currentCacheSize += size
        accessTimes[key] = Date()
    }

    /// Retrieves cached acoustic features.
    public func getAcousticFeatures(for key: String) -> AcousticFeatures? {
        accessTimes[key] = Date()
        return featureCache[key]
    }

    /// Stores transcription in cache.
    public func cacheTranscription(_ transcript: PhoneticTranscription, for key: String) {
        let size = transcript.phonemes.count * 64  // Rough estimate
        ensureSpace(size)

        transcriptionCache[key] = transcript
        currentCacheSize += size
        accessTimes[key] = Date()
    }

    /// Retrieves cached transcription.
    public func getTranscription(for key: String) -> PhoneticTranscription? {
        accessTimes[key] = Date()
        return transcriptionCache[key]
    }

    /// Stores prosody prediction in cache.
    public func cacheProsody(_ prosody: ProsodyDescription, for key: String) {
        let size = prosody.phonemes.count * 128  // Rough estimate
        ensureSpace(size)

        prosodyCache[key] = prosody
        currentCacheSize += size
        accessTimes[key] = Date()
    }

    /// Retrieves cached prosody prediction.
    public func getProsody(for key: String) -> ProsodyDescription? {
        accessTimes[key] = Date()
        return prosodyCache[key]
    }

    /// Clears all caches.
    public func clear() {
        featureCache.removeAll()
        transcriptionCache.removeAll()
        prosodyCache.removeAll()
        accessTimes.removeAll()
        currentCacheSize = 0
    }

    /// Returns cache statistics.
    public func getStatistics() -> CacheStatistics {
        CacheStatistics(
            featureCount: featureCache.count,
            transcriptionCount: transcriptionCache.count,
            prosodyCount: prosodyCache.count,
            currentSizeBytes: currentCacheSize,
            maxSizeBytes: maxCacheSize
        )
    }

    /// Ensures there's enough space for new data using LRU eviction.
    private func ensureSpace(_ requiredBytes: Int) {
        guard requiredBytes > 0 else { return }

        while currentCacheSize + requiredBytes > maxCacheSize && !featureCache.isEmpty {
            evictLRUItem()
        }
    }

    /// Evicts the least recently used item.
    private func evictLRUItem() {
        guard let lruKey = accessTimes.min(by: { $0.value < $1.value })?.key else { return }

        // Remove from all caches
        if let features = featureCache.removeValue(forKey: lruKey) {
            currentCacheSize -= features.frameCount * features.frequencyBins * MemoryLayout<Float>.size
        }
        if let transcript = transcriptionCache.removeValue(forKey: lruKey) {
            currentCacheSize -= transcript.phonemes.count * 64
        }
        if let prosody = prosodyCache.removeValue(forKey: lruKey) {
            currentCacheSize -= prosody.phonemes.count * 128
        }

        accessTimes.removeValue(forKey: lruKey)
    }
}

/// Cache statistics.
public struct CacheStatistics: Sendable {
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

    /// Cache utilization as percentage.
    public var utilizationPercent: Double {
        guard maxSizeBytes > 0 else { return 0 }
        return Double(currentSizeBytes) / Double(maxSizeBytes) * 100
    }
}
