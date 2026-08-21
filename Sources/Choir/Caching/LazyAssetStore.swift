import Foundation

public struct LazyAssetStoreStatistics: Sendable, Equatable {
    public let loadedCount: Int
    public let loadingCount: Int
    public let loadCount: UInt64
    public let cacheHitCount: UInt64
    public let unloadCount: UInt64
}

/// Coalescing lazy loader for model or voice-family assets (CCH-011).
///
/// Concurrent requests for the same key share one load task. Unloaded assets
/// are automatically reloaded on their next access, and consumers can wire
/// ``handleMemoryPressure()`` directly to their platform memory-pressure
/// notification without changing synthesis call sites.
public actor LazyAssetStore<Key, Asset>: Sendable
where Key: Hashable & Sendable, Asset: Sendable {
    public typealias Loader = @Sendable (Key) async throws -> Asset

    private let loader: Loader
    private var loaded: [Key: Asset] = [:]
    private struct InFlight: Sendable {
        let token: UInt64
        let task: Task<Asset, Error>
    }

    private var inFlight: [Key: InFlight] = [:]
    private var loadCount: UInt64 = 0
    private var cacheHitCount: UInt64 = 0
    private var unloadCount: UInt64 = 0
    private var nextLoadToken: UInt64 = 0

    public init(loader: @escaping Loader) {
        self.loader = loader
    }

    /// Returns a loaded asset or lazily loads it. A failed load is never
    /// retained, so the next request can retry after the underlying condition
    /// is repaired.
    public func asset(for key: Key) async throws -> Asset {
        if let asset = loaded[key] {
            cacheHitCount &+= 1
            return asset
        }
        if let inFlight = inFlight[key] {
            cacheHitCount &+= 1
            return try await inFlight.task.value
        }

        let loader = self.loader
        nextLoadToken &+= 1
        let loadToken = nextLoadToken
        let task = Task<Asset, Error> { try await loader(key) }
        inFlight[key] = InFlight(token: loadToken, task: task)
        do {
            let asset = try await task.value
            if inFlight[key]?.token == loadToken {
                inFlight.removeValue(forKey: key)
                loaded[key] = asset
            }
            loadCount &+= 1
            return asset
        } catch {
            if inFlight[key]?.token == loadToken {
                inFlight.removeValue(forKey: key)
            }
            throw error
        }
    }

    /// Explicit warm-up for a voice family or other known asset group.
    public func warmUp(_ keys: [Key]) async throws {
        for key in keys { _ = try await asset(for: key) }
    }

    public func isLoaded(_ key: Key) -> Bool { loaded[key] != nil }

    @discardableResult
    public func unload(_ key: Key) -> Bool {
        let pending = inFlight.removeValue(forKey: key)
        pending?.task.cancel()
        let existed = loaded.removeValue(forKey: key) != nil || pending != nil
        if existed { unloadCount &+= 1 }
        return existed
    }

    /// Cancels unfinished loads and releases all resident assets. Subsequent
    /// `asset(for:)` calls reload transparently.
    @discardableResult
    public func unloadAll() -> Int {
        for load in inFlight.values { load.task.cancel() }
        inFlight.removeAll()
        let count = loaded.count
        loaded.removeAll()
        unloadCount &+= UInt64(count)
        return count
    }

    /// Entry point intended for OS memory-pressure callbacks.
    @discardableResult
    public func handleMemoryPressure() -> Int { unloadAll() }

    public func statistics() -> LazyAssetStoreStatistics {
        LazyAssetStoreStatistics(
            loadedCount: loaded.count,
            loadingCount: inFlight.count,
            loadCount: loadCount,
            cacheHitCount: cacheHitCount,
            unloadCount: unloadCount)
    }
}
