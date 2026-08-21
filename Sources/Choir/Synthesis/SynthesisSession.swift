import Foundation

/// Manages a synthesis session with configuration and state.
///
/// Encapsulates synthesis parameters, caching, and job tracking
/// for a particular synthesis task or batch.
public actor SynthesisSession {
    /// Session identifier.
    public let id: UUID

    /// Session creation time.
    public let createdAt: Date

    /// Synthesis parameters.
    public var parameters: SynthesisParameters

    /// Voice to use.
    public var voice: Voice

    /// Audio processing effects.
    public var effectChain: AudioEffectChain?

    /// Custom pronunciation dictionary.
    public var pronunciationDictionary: PronunciationDictionary

    /// Session state.
    public enum State: Sendable, Equatable {
        case idle
        case synthesizing
        case completed
        case failed(String)
    }

    private var state: State = .idle
    private var lastSynthesizedText: String?
    private var lastAudioByteCount: Int = 0
    private var synthesisCaches: [String: AudioBuffer] = [:]

    /// Creates a new synthesis session.
    public init(
        voice: Voice = .isla,
        parameters: SynthesisParameters = SynthesisParameters(),
        effectChain: AudioEffectChain? = nil,
        pronunciationDictionary: PronunciationDictionary = .standard
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.voice = voice
        self.parameters = parameters
        self.effectChain = effectChain
        self.pronunciationDictionary = pronunciationDictionary
    }

    /// Returns current session state.
    public func getState() -> State {
        state
    }

    /// Begins a synthesis only when the session is not already busy.
    @discardableResult
    public func beginSynthesis() -> Bool {
        guard state != .synthesizing else { return false }
        state = .synthesizing
        return true
    }

    /// Returns the session to idle without discarding configuration or cache.
    public func resetState() {
        state = .idle
    }

    public func getLastSynthesizedText() -> String? { lastSynthesizedText }

    /// Caches audio under a key.
    public func cacheAudio(_ audio: AudioBuffer, for key: String) {
        synthesisCaches[key] = audio
    }

    /// Retrieves cached audio.
    public func getCachedAudio(for key: String) -> AudioBuffer? {
        synthesisCaches[key]
    }

    public func containsCachedAudio(for key: String) -> Bool {
        synthesisCaches[key] != nil
    }

    @discardableResult
    public func removeCachedAudio(for key: String) -> Bool {
        synthesisCaches.removeValue(forKey: key) != nil
    }

    public var cachedKeys: [String] { synthesisCaches.keys.sorted() }

    /// Clears all cached audio.
    public func clearCache() {
        synthesisCaches.removeAll()
    }

    /// Records synthesis completion.
    public func recordSynthesis(text: String, audio: AudioBuffer) {
        lastSynthesizedText = text
        lastAudioByteCount = audio.byteCount
        state = .completed
    }

    /// Records synthesis failure.
    public func recordFailure(_ message: String) {
        state = .failed(message)
    }

    /// Returns session statistics.
    public func getStatistics() -> SessionStatistics {
        SessionStatistics(
            id: id,
            createdAt: createdAt,
            elapsedTime: Date().timeIntervalSince(createdAt),
            state: state,
            cacheSize: synthesisCaches.values.reduce(0) { $0 + $1.samples.count * 2 },
            cachedItemCount: synthesisCaches.count,
            lastSynthesizedText: lastSynthesizedText,
            lastAudioByteCount: lastAudioByteCount
        )
    }
}

/// Statistics for a synthesis session.
public struct SessionStatistics: Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let elapsedTime: TimeInterval
    public let state: SynthesisSession.State
    public let cacheSize: Int
    public let cachedItemCount: Int
    public let lastSynthesizedText: String?
    public let lastAudioByteCount: Int

    public var elapsedSeconds: Double {
        elapsedTime
    }

    public var cacheInfo: String {
        "\(cachedItemCount) items, \(cacheSize / 1024)KB"
    }

    public var hasCachedAudio: Bool { cachedItemCount > 0 }
}

/// Manager for multiple synthesis sessions.
public actor SynthesisSessionManager {
    private var sessions: [UUID: SynthesisSession] = [:]
    private var activeSessions: Set<UUID> = []

    public init() {}

    /// Creates a new synthesis session.
    public func createSession(
        voice: Voice = .isla,
        parameters: SynthesisParameters = SynthesisParameters(),
        effectChain: AudioEffectChain? = nil
    ) -> SynthesisSession {
        let session = SynthesisSession(
            voice: voice,
            parameters: parameters,
            effectChain: effectChain
        )

        sessions[session.id] = session
        activeSessions.insert(session.id)

        return session
    }

    /// Retrieves an existing session.
    public func getSession(_ id: UUID) -> SynthesisSession? {
        sessions[id]
    }

    /// Marks a session as complete.
    public func completeSession(_ id: UUID) {
        activeSessions.remove(id)
    }

    /// Returns all active sessions.
    public func getActiveSessions() -> [SynthesisSession] {
        activeSessions
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { sessions[$0] }
    }

    /// Returns all sessions.
    public func getAllSessions() -> [SynthesisSession] {
        sessions.keys
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { sessions[$0] }
    }

    /// Clears a session and its cache.
    public func clearSession(_ id: UUID) {
        sessions[id] = nil
        activeSessions.remove(id)
    }

    /// Clears all sessions.
    public func clearAllSessions() {
        sessions.removeAll()
        activeSessions.removeAll()
    }

    /// Returns manager statistics.
    ///
    /// Note: totalCacheSize requires async access to session actors.
    /// For accurate cache statistics, call `getSession()` then `getStatistics()` on each session.
    public func getStatistics() -> ManagerStatistics {
        ManagerStatistics(
            totalSessions: sessions.count,
            activeSessions: activeSessions.count,
            totalCacheSize: 0
        )
    }

    /// Accurate aggregate statistics, including actor-isolated session caches.
    public func getDetailedStatistics() async -> ManagerStatistics {
        var cacheBytes = 0
        for session in sessions.values {
            cacheBytes += (await session.getStatistics()).cacheSize
        }
        return ManagerStatistics(
            totalSessions: sessions.count,
            activeSessions: activeSessions.count,
            totalCacheSize: cacheBytes)
    }
}

/// Statistics for session manager.
public struct ManagerStatistics: Sendable, Equatable {
    public let totalSessions: Int
    public let activeSessions: Int
    public let totalCacheSize: Int

    public var completedSessions: Int { max(0, totalSessions - activeSessions) }
}
