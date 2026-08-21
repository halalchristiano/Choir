import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// Tier-2 synthesis request (SRS API-001).
///
/// It carries the explicitly selected input interpretation, voice, parameters,
/// and scheduling intent as one reusable value. The expert phoneme+prosody
/// overload remains available directly on ``ChoirEngine``.
public struct SynthesisRequest: Sendable, Equatable {
    public let input: SynthesisInput
    public let voice: Voice
    public let parameters: SynthesisParameters
    public let priority: SynthesisExecutionPriority

    /// Creates a markup-capable text request, matching the historical
    /// `synthesize(text:voice:)` behavior.
    public init(
        text: String,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        priority: SynthesisExecutionPriority = .automatic
    ) {
        self.input = .markup(text)
        self.voice = voice
        self.parameters = parameters
        self.priority = priority
    }

    /// Creates a request whose interpretation is explicit.
    public init(
        input: SynthesisInput,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        priority: SynthesisExecutionPriority = .automatic
    ) {
        self.input = input
        self.voice = voice
        self.parameters = parameters
        self.priority = priority
    }
}

/// One utterance in the expert-tier dialogue queue (STR-006/API-001).
public struct DialogueUtterance: Sendable, Equatable {
    public static let maximumGapMilliseconds = 3_600_000.0
    public let request: SynthesisRequest
    public let gapAfterMs: Double

    public init(request: SynthesisRequest, gapAfterMs: Double = 0) {
        self.request = request
        self.gapAfterMs = gapAfterMs.isFinite ? max(0, gapAfterMs) : 0
    }

    public init(
        text: String,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        gapAfterMs: Double = 0,
        priority: SynthesisExecutionPriority = .interactive
    ) {
        self.init(
            request: SynthesisRequest(
                text: text,
                voice: voice,
                parameters: parameters,
                priority: priority),
            gapAfterMs: gapAfterMs)
    }
}

/// Ordered utterances streamed on one continuous request-wide timeline.
public struct DialogueQueue: Sendable, Equatable {
    public let utterances: [DialogueUtterance]

    public init(_ utterances: [DialogueUtterance]) {
        self.utterances = utterances
    }

    public var isEmpty: Bool { utterances.isEmpty }
}

private actor DialogueProgress {
    private var endMs = 0.0
    private var completedSentenceCount = 0

    func record(endMs: Double, completedSentenceCount: Int) {
        self.endMs = max(self.endMs, endMs)
        self.completedSentenceCount = max(
            self.completedSentenceCount, completedSentenceCount)
    }

    func value() -> (endMs: Double, completedSentenceCount: Int) {
        (endMs, completedSentenceCount)
    }
}

/// A bounded, acknowledged handoff between synthesis and AsyncSequence.
/// Unlike AsyncThrowingStream's drop policies, a full queue suspends the
/// producer, so normal slow consumers neither lose PCM nor grow memory.
fileprivate actor BoundedSynthesisChannel {
    private struct PendingSend {
        let element: SynthesisStreamChunk
        let continuation: CheckedContinuation<Result<Void, ChoirError>, Never>
    }

    private enum State {
        case active
        case finished(ChoirError?)
    }

    private let capacity: Int
    private var queue: [SynthesisStreamChunk] = []
    private var pendingSends: [PendingSend] = []
    private var pendingReceives: [
        CheckedContinuation<Result<SynthesisStreamChunk?, ChoirError>, Never>
    ] = []
    private var state: State = .active

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    func send(_ element: SynthesisStreamChunk) async throws {
        try Cancellation.check()
        guard case .active = state else { throw ChoirError.cancelled }
        if !pendingReceives.isEmpty {
            let receiver = pendingReceives.removeFirst()
            receiver.resume(returning: .success(element))
            return
        }
        if queue.count < capacity {
            queue.append(element)
            return
        }

        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingSends.append(PendingSend(
                    element: element,
                    continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancel() }
        }
        try outcome.get()
    }

    func next() async throws -> SynthesisStreamChunk? {
        try Cancellation.check()
        if !queue.isEmpty {
            let element = queue.removeFirst()
            promoteWaitingSender()
            return element
        }
        switch state {
        case .finished(let error):
            if let error { throw error }
            return nil
        case .active:
            break
        }

        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pendingReceives.append(continuation)
            }
        } onCancel: {
            Task { await self.cancel() }
        }
        return try outcome.get()
    }

    func finish(error: ChoirError? = nil) {
        guard case .active = state else { return }
        state = .finished(error)
        let senders = pendingSends
        pendingSends.removeAll()
        for sender in senders {
            sender.continuation.resume(returning: .failure(error ?? .cancelled))
        }
        guard queue.isEmpty else { return }
        let receivers = pendingReceives
        pendingReceives.removeAll()
        for receiver in receivers {
            if let error {
                receiver.resume(returning: .failure(error))
            } else {
                receiver.resume(returning: .success(nil))
            }
        }
    }

    func cancel() {
        state = .finished(.cancelled)
        queue.removeAll(keepingCapacity: false)
        let senders = pendingSends
        pendingSends.removeAll()
        for sender in senders {
            sender.continuation.resume(returning: .failure(.cancelled))
        }
        let receivers = pendingReceives
        pendingReceives.removeAll()
        for receiver in receivers {
            receiver.resume(returning: .failure(.cancelled))
        }
    }

    private func promoteWaitingSender() {
        guard case .active = state, !pendingSends.isEmpty else { return }
        let sender = pendingSends.removeFirst()
        queue.append(sender.element)
        sender.continuation.resume(returning: .success(()))
    }
}

fileprivate final class StreamCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    init(_ handler: @escaping @Sendable () -> Void) {
        self.handler = handler
    }

    func cancel() {
        lock.lock()
        let action = handler
        handler = nil
        lock.unlock()
        action?()
    }

    deinit { cancel() }
}

/// Pull-based public stream whose iterator owns producer cancellation.
/// Leaving a `for await` loop destroys the iterator and promptly releases the
/// engine permit, even when the sequence value itself remains in scope.
public struct SynthesisChunkStream: AsyncSequence, Sendable {
    public typealias Element = SynthesisStreamChunk
    private let iteratorFactory: @Sendable () -> Iterator

    fileprivate init(iteratorFactory: @escaping @Sendable () -> Iterator) {
        self.iteratorFactory = iteratorFactory
    }

    public func makeAsyncIterator() -> Iterator { iteratorFactory() }

    public final class Iterator: AsyncIteratorProtocol, @unchecked Sendable {
        private let channel: BoundedSynthesisChannel
        private let cancellation: StreamCancellation

        fileprivate init(
            channel: BoundedSynthesisChannel,
            cancellation: StreamCancellation
        ) {
            self.channel = channel
            self.cancellation = cancellation
        }

        public func next() async throws -> SynthesisStreamChunk? {
            do {
                let element = try await channel.next()
                if element == nil { cancellation.cancel() }
                return element
            } catch {
                cancellation.cancel()
                throw error
            }
        }
    }
}

extension ChoirEngine {
    /// Tier-2 standard request API: audio and complete metadata in one result.
    public func synthesize(_ request: SynthesisRequest) async throws -> SynthesisResult {
        try await synthesize(
            input: request.input,
            voice: request.voice,
            parameters: request.parameters,
            priority: request.priority)
    }

    /// Tier-3 AsyncSequence surface over incremental PCM and timing updates.
    /// Terminating iteration cancels the producer task and underlying model
    /// work through structured cancellation.
    public nonisolated func streamChunks(
        _ request: SynthesisRequest,
        options: StreamingOptions = StreamingOptions()
    ) -> SynthesisChunkStream {
        SynthesisChunkStream {
            let channel = BoundedSynthesisChannel(capacity: 8)
            let producer = Task {
                do {
                    var effectiveOptions = options
                    effectiveOptions.priority = request.priority == .automatic
                        ? options.priority
                        : request.priority
                    try await self.streamSynthesisWithMetadata(
                        input: request.input,
                        voice: request.voice,
                        parameters: request.parameters,
                        options: effectiveOptions
                    ) { delivery in
                        try await channel.send(delivery)
                    }
                    await channel.finish()
                } catch let error as ChoirError {
                    await channel.finish(error: error)
                } catch {
                    await channel.finish(error: .unknown(error.localizedDescription))
                }
            }
            let cancellation = StreamCancellation {
                producer.cancel()
                Task { await channel.cancel() }
            }
            return SynthesisChunkStream.Iterator(
                channel: channel,
                cancellation: cancellation)
        }
    }

    /// Source-compatible AsyncThrowingStream adapter for Tier-3 callers.
    ///
    /// Its legacy, unbounded compatibility buffer is fed by
    /// ``streamChunks(_:options:)``. This preserves the lossless behavior of
    /// the existing API. New callers that need bounded memory and true
    /// producer backpressure should use `streamChunks` directly.
    public nonisolated func stream(
        _ request: SynthesisRequest,
        options: StreamingOptions = StreamingOptions()
    ) -> AsyncThrowingStream<SynthesisStreamChunk, Error> {
        let chunks = streamChunks(request, options: options)
        return AsyncThrowingStream { continuation in
            let bridge = Task {
                do {
                    for try await delivery in chunks {
                        try Cancellation.check()
                        switch continuation.yield(delivery) {
                        case .enqueued:
                            continue
                        case .dropped(_):
                            // The compatibility adapter is unbounded, so this
                            // is unreachable unless a future standard-library
                            // implementation changes that contract.
                            continuation.finish(throwing: ChoirError.synthesisError(
                                reason: "The compatibility stream could not enqueue PCM"))
                            return
                        case .terminated:
                            return
                        @unknown default:
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in bridge.cancel() }
        }
    }

    /// Streams a queue gaplessly, or inserts each requested silence, while
    /// preserving one monotonic timestamp/metadata timeline (STR-006).
    public func streamDialogue(
        _ queue: DialogueQueue,
        options: StreamingOptions = StreamingOptions(),
        onChunk: @escaping @Sendable (SynthesisStreamChunk) async throws -> Void
    ) async throws {
        guard !queue.isEmpty else { return }
        guard queue.utterances.allSatisfy({
            $0.gapAfterMs <= DialogueUtterance.maximumGapMilliseconds
        }) else {
            throw ChoirError.invalidParameter(
                parameter: "gapAfterMs", reason: "Dialogue gaps may not exceed one hour")
        }

        var timelineMs = 0.0
        var completedSentences = 0
        for (utteranceIndex, utterance) in queue.utterances.enumerated() {
            let progress = DialogueProgress()
            let timelineOffset = timelineMs
            let sentenceOffset = completedSentences
            var effectiveOptions = options
            effectiveOptions.priority = utterance.request.priority == .automatic
                ? options.priority
                : utterance.request.priority

            try await streamSynthesisWithMetadata(
                input: utterance.request.input,
                voice: utterance.request.voice,
                parameters: utterance.request.parameters,
                options: effectiveOptions
            ) { delivery in
                let shifted = Self.shift(
                    delivery,
                    by: timelineOffset,
                    completedSentenceOffset: sentenceOffset,
                    isFinal: utteranceIndex == queue.utterances.count - 1
                        && delivery.isFinal
                        && utterance.gapAfterMs == 0)
                await progress.record(
                    endMs: delivery.metadata.endMs,
                    completedSentenceCount: delivery.metadata.completedSentenceCount)
                try await onChunk(shifted)
            }

            let utteranceProgress = await progress.value()
            completedSentences += utteranceProgress.completedSentenceCount
            timelineMs += utteranceProgress.endMs

            if utterance.gapAfterMs > 0 {
                let isFinal = utteranceIndex == queue.utterances.count - 1
                let emittedGapMs = try await Self.streamSilence(
                    startMs: timelineMs,
                    durationMs: utterance.gapAfterMs,
                    completedSentenceCount: completedSentences,
                    isFinal: isFinal,
                    sampleRate: audioFormat.sampleRate,
                    channels: audioFormat.channels,
                    chunkSize: options.chunkSize,
                    onChunk: onChunk)
                timelineMs += emittedGapMs
            }
        }
    }

    private static func shift(
        _ delivery: SynthesisStreamChunk,
        by offsetMs: Double,
        completedSentenceOffset: Int,
        isFinal: Bool
    ) -> SynthesisStreamChunk {
        func span(_ value: TimedSpan) -> TimedSpan {
            TimedSpan(
                content: value.content,
                startMs: value.startMs + offsetMs,
                endMs: value.endMs + offsetMs)
        }
        let timing = StreamingMetadataUpdate(
            startMs: delivery.metadata.startMs + offsetMs,
            endMs: delivery.metadata.endMs + offsetMs,
            words: delivery.metadata.words.map(span),
            phonemes: delivery.metadata.phonemes.map(span),
            marks: delivery.metadata.marks.map {
                MarkPosition(name: $0.name, timeMs: $0.timeMs + offsetMs)
            },
            completedSentenceCount: completedSentenceOffset
                + delivery.metadata.completedSentenceCount)
        let audio = AudioChunk(
            samples: delivery.audio.samples,
            isFinal: isFinal,
            timestamp: (delivery.audio.timestamp ?? 0) + offsetMs / 1000)
        return SynthesisStreamChunk(audio: audio, metadata: timing)
    }

    private static func streamSilence(
        startMs: Double,
        durationMs: Double,
        completedSentenceCount: Int,
        isFinal: Bool,
        sampleRate: Int,
        channels: Int,
        chunkSize: Int,
        onChunk: @Sendable (SynthesisStreamChunk) async throws -> Void
    ) async throws -> Double {
        let requestedFrames = durationMs / 1000 * Double(sampleRate)
        guard requestedFrames.isFinite,
              requestedFrames >= 0,
              requestedFrames <= Double(Int.max / max(1, channels)) else {
            throw ChoirError.invalidParameter(
                parameter: "gapAfterMs", reason: "Dialogue gap is too large to render safely")
        }
        let totalFrames = max(1, Int(requestedFrames.rounded()))
        let framesPerChunk = max(1, chunkSize / channels)
        var emittedFrames = 0
        while emittedFrames < totalFrames {
            try Cancellation.check()
            let frameCount = min(framesPerChunk, totalFrames - emittedFrames)
            let capacity = frameCount.multipliedReportingOverflow(by: channels)
            guard !capacity.overflow else { throw ChoirError.outOfMemory }
            let chunkStartMs = startMs
                + Double(emittedFrames) / Double(sampleRate) * 1000
            let chunkEndMs = startMs
                + Double(emittedFrames + frameCount) / Double(sampleRate) * 1000
            let finalChunk = emittedFrames + frameCount == totalFrames
            try await onChunk(SynthesisStreamChunk(
                audio: AudioChunk(
                    samples: Array(repeating: 0, count: capacity.partialValue),
                    isFinal: isFinal && finalChunk,
                    timestamp: chunkStartMs / 1000),
                metadata: StreamingMetadataUpdate(
                    startMs: chunkStartMs,
                    endMs: chunkEndMs,
                    completedSentenceCount: completedSentenceCount)))
            emittedFrames += frameCount
        }
        return Double(totalFrames) / Double(sampleRate) * 1000
    }
}

extension SynthesisResult {
    /// Asynchronously encodes this result without performing file-scale work
    /// on the caller's executor (API-001/API-002/CON-001).
    public func exported(
        as format: AudioOutputFormat,
        priority: SynthesisExecutionPriority = .utility
    ) async throws -> AudioOutput {
        let audio = self.audio
        let task = Task.detached(priority: priority.taskPriority) {
            try Cancellation.check()
            let encoder = AudioEncoder()
            switch format {
            case .wav:
                return AudioOutput.wav(try encoder.encodeWAV(audio))
            case .mp3:
                return AudioOutput.mp3(try encoder.encodeMP3(audio))
            case .aac:
                return AudioOutput.aac(try encoder.encodeAAC(audio))
            case .flac:
                _ = try encoder.encodeFLAC(audio)
                throw ChoirError.audioEncodingFailed(
                    reason: "FLAC has no AudioOutput representation in this API version")
            }
        }
        return try await withTaskCancellationHandler {
            try await Cancellation.mapping { try await task.value }
        } onCancel: {
            task.cancel()
        }
    }
}

/// Tier 1 of the public API (SRS API-001).
///
/// "The API shall offer three concentric tiers, each complete for its use
/// level: **Tier 1 (one-liner):** `try await Choir.speak("text", voice: .maeve)`
/// — synthesize and play."
///
/// The point of a concentric API is that the simplest use costs one line and no
/// ceremony, while nothing is hidden: Tier 2 (``ChoirEngine``) and Tier 3
/// (streaming, metadata, phoneme input) stay directly available, and Tier 1 is
/// written in terms of them rather than beside them.
extension Choir {

    /// Synthesizes `text` and plays it.
    ///
    /// Creates and initializes an engine per call, so this is the convenient
    /// path rather than the efficient one. An app speaking repeatedly should
    /// hold a ``ChoirEngine`` and reuse it — that is Tier 2.
    ///
    /// - Returns: the synthesized audio, once playback has finished.
    @discardableResult
    public static func speak(
        _ text: String,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters()
    ) async throws -> AudioBuffer {
        let audio = try await synthesize(text, voice: voice, parameters: parameters)
        try await play(audio)
        return audio
    }

    /// Synthesizes `text` without playing it.
    ///
    /// The same one-line shape for callers that want the buffer — to write a
    /// file, or feed a mixer — rather than immediate playback.
    public static func synthesize(
        _ text: String,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters()
    ) async throws -> AudioBuffer {
        let engine = ChoirEngine()
        try await engine.initialize()
        return try await engine.synthesize(text: text, voice: voice, parameters: parameters)
    }

    /// Plays a synthesized buffer, returning when playback finishes.
    public static func play(_ audio: AudioBuffer) async throws {
        #if canImport(AVFoundation)
        guard !audio.samples.isEmpty else { return }

        // Played from encoded WAV rather than an AVAudioPCMBuffer so playback
        // goes through the package's own encoder: one audio format path rather
        // than two that can drift apart.
        let encoding = Task.detached(priority: .high) {
            try Cancellation.check()
            return try AudioEncoder().encodeWAV(audio)
        }
        let data = try await withTaskCancellationHandler {
            try await Cancellation.mapping { try await encoding.value }
        } onCancel: {
            encoding.cancel()
        }
        let completion = PlaybackCompletion()
        try completion.start(data: data)
        try await withTaskCancellationHandler {
            try await completion.wait()
        } onCancel: {
            completion.cancel()
        }
        #else
        throw ChoirError.synthesisError(
            reason: "Playback is unavailable on this platform; use Choir.synthesize(_:voice:) instead")
        #endif
    }
}

#if canImport(AVFoundation)
/// Bridges `AVAudioPlayer`'s delegate callback to an `await`.
private final class PlaybackCompletion: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<Void, ChoirError>, Never>?
    private var result: Result<Void, ChoirError>?
    private var player: AVAudioPlayer?

    func start(data: Data) throws {
        let newPlayer: AVAudioPlayer
        do {
            newPlayer = try AVAudioPlayer(data: data)
        } catch {
            throw ChoirError.audioEncodingFailed(
                reason: "Could not prepare audio for playback: \(error.localizedDescription)")
        }
        newPlayer.delegate = self
        lock.lock()
        player = newPlayer
        lock.unlock()
        guard newPlayer.play() else {
            complete(.failure(.synthesisError(reason: "Audio playback failed to start")))
            throw ChoirError.synthesisError(reason: "Audio playback failed to start")
        }
    }

    func wait() async throws {
        let outcome = await withCheckedContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
        try outcome.get()
    }

    func cancel() {
        lock.lock()
        let activePlayer = player
        lock.unlock()
        activePlayer?.stop()
        complete(.failure(.cancelled))
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        complete(flag
            ? .success(())
            : .failure(.synthesisError(reason: "Audio playback ended unsuccessfully")))
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        complete(.failure(.audioEncodingFailed(
            reason: error?.localizedDescription ?? "Audio playback decode failed")))
    }

    /// Resumes at most once: the delegate may fire either callback, and a
    /// continuation resumed twice traps.
    private func complete(_ outcome: Result<Void, ChoirError>) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = outcome
        player = nil
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: outcome)
    }
}
#endif
