import Foundation

/// The main Choir synthesis engine for on-device text-to-speech.
///
/// ChoirEngine provides phrase-progressive and batch synthesis APIs plus
/// validated control inputs. Audible production behavior remains dependent on
/// caller-injected models until trained assets ship.
public actor ChoirEngine {
    /// The current state of the engine.
    public enum State: Sendable, Equatable {
        case uninitialized
        case initializing
        case ready
        case synthesizing
        case error(ChoirError)
    }

    private var state: State = .uninitialized
    /// Module-visible so same-module API adapters can preserve custom formats.
    let audioFormat: AudioFormat
    private let configuredPipeline: SynthesisPipeline?
    private var pipeline: SynthesisPipeline?
    public nonisolated let maximumConcurrentJobs: Int
    private var activeSynthesisJobs = 0
    private var permitWaiters: [PermitWaiter] = []
    private var isPipelineWarmedUp = false
    private var warmUpTask: Task<Void, Error>?

    private struct PermitWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Result<Void, ChoirError>, Never>
    }

    /// Creates a new Choir synthesis engine.
    ///
    /// - Parameters:
    ///   - audioFormat: The audio format for synthesis output.
    ///   - pipeline: An explicitly configured pipeline. Supply this to inject
    ///     production models or test doubles; `nil` uses the package's current
    ///     mock-backed development pipeline.
    public init(
        audioFormat: AudioFormat = AudioFormat(),
        pipeline: SynthesisPipeline? = nil,
        maximumConcurrentJobs: Int = 2
    ) {
        self.audioFormat = audioFormat
        self.configuredPipeline = pipeline
        self.maximumConcurrentJobs = max(2, maximumConcurrentJobs)
    }

    /// Initializes the engine, loading necessary models and resources.
    ///
    /// This must be called before any synthesis operations. Can be called multiple times;
    /// subsequent calls are no-ops if already initialized.
    ///
    /// - Throws: `ChoirError` if model loading fails.
    public func initialize() async throws {
        switch state {
        case .ready:
            return
        case .initializing, .synthesizing:
            throw ChoirError.engineBusy
        case .error(let error):
            throw error
        case .uninitialized:
            break
        }

        state = .initializing
        do {
            try audioFormat.validate()
        } catch let error as ChoirError {
            state = .error(error)
            throw error
        }
        // The default components are explicitly test scaffolding until model
        // assets are integrated; public documentation must not call this a
        // production neural path.
        self.pipeline = configuredPipeline ?? SynthesisPipeline(audioFormat: audioFormat)
        self.isPipelineWarmedUp = false

        state = .ready
    }

    /// Returns the current engine state.
    public func getState() -> State {
        state
    }

    /// Synthesizes text to audio in batch mode.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voice: The voice to use.
    ///   - parameters: Optional synthesis parameters (prosody, emotion, etc).
    /// - Returns: An `AudioBuffer` containing the synthesized audio.
    /// - Throws: `ChoirError` if synthesis fails.
    public func synthesize(
        text: String,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        priority: SynthesisExecutionPriority = .automatic
    ) async throws -> AudioBuffer {
        let result = try await synthesize(
            input: .markup(text),
            voice: voice,
            parameters: parameters,
            priority: priority)
        return result.audio
    }

    /// Synthesizes many items, with a caller-selected failure policy
    /// (SRS REL-002).
    ///
    /// "Partial-failure policy for batch/multi-item jobs shall be
    /// caller-selectable: fail-fast, or continue-and-report (result carries
    /// per-item success/error list)."
    ///
    /// The choice is not cosmetic. When the items form one artifact — the
    /// chapters of an audiobook — half a result is worthless and `.failFast`
    /// is right. When they are independent, such as a table of game lines, one
    /// unpronounceable name should not cost the other four hundred, and
    /// `.continueAndReport` is right.
    ///
    /// Cancellation is honoured between items as well as inside them
    /// (CON-002), so a long batch stops promptly.
    public func synthesizeBatch(
        texts: [String],
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        policy: PartialFailurePolicy = .failFast,
        priority: SynthesisExecutionPriority = .utility
    ) async throws -> BatchResult {
        try validateSynthesisState()
        guard let pipeline = pipeline else { throw ChoirError.notInitialized }

        try await acquireSynthesisPermit()
        defer { releaseSynthesisPermit() }

        var outcomes: [BatchItemOutcome] = []
        outcomes.reserveCapacity(texts.count)

        for (index, text) in texts.enumerated() {
            // Checked before each item so a cancelled batch stops without
            // starting work it will discard.
            try Cancellation.check()

            do {
                let audio = try await pipeline.synthesize(
                    text: text,
                    voice: voice,
                    parameters: parameters,
                    priority: priority)
                outcomes.append(BatchItemOutcome(index: index, text: text, audio: audio))
            } catch let error as ChoirError {
                // Cancellation is not an item failure: it ends the whole job
                // regardless of policy, or a cancelled batch would be reported
                // as a batch of failures.
                if case .cancelled = error { throw error }

                switch policy {
                case .failFast:
                    throw error
                case .continueAndReport:
                    outcomes.append(BatchItemOutcome(index: index, text: text, error: error))
                }
            }
        }

        return BatchResult(outcomes: outcomes, policy: policy)
    }

    /// The outcome of a start-up self-check (SRS REL-003).
    public struct VerificationResult: Sendable, Equatable {
        /// Whether the installation is usable.
        public let isHealthy: Bool

        /// Individual checks, in the order they ran.
        public let checks: [Check]

        public struct Check: Sendable, Equatable {
            public let name: String
            public let passed: Bool
            public let detail: String
        }

        public var failures: [Check] { checks.filter { !$0.passed } }

        public var summary: String {
            isHealthy
                ? "Installation healthy: \(checks.count) checks passed"
                : "Installation broken: \(failures.map(\.name).joined(separator: ", "))"
        }
    }

    /// Runs a start-up self-check (SRS REL-003).
    ///
    /// "The engine shall run a start-up self-check (asset hashes, model load,
    /// 0.5 s silent smoke synthesis) exposed as `engine.verify()`, so consuming
    /// apps can detect a broken installation deterministically rather than
    /// failing at first user request."
    ///
    /// The point is the word *deterministically*: an app can call this at
    /// launch and know, rather than discovering at the moment a user taps
    /// speak that a voice pack is missing.
    public func verify() async -> VerificationResult {
        var checks: [VerificationResult.Check] = []

        // The lexicon is a shipped asset, so its absence is a broken install.
        let lexicon = BuiltInLexicon.shared
        let lexiconCount = lexicon.count
        checks.append(.init(
            name: "lexicon",
            passed: lexiconCount >= 120_000,
            detail: "\(lexiconCount) word forms (TXT-020 requires at least 120,000)"))

        // Every voice must resolve to a complete profile.
        let incomplete = Voice.allCases.filter {
            $0.profile.identifier.isEmpty || $0.profile.medianF0 <= 0
        }
        checks.append(.init(
            name: "voices",
            passed: incomplete.isEmpty,
            detail: incomplete.isEmpty
                ? "\(Voice.allCases.count) voice profiles complete"
                : "incomplete: \(incomplete.map(\.displayName).joined(separator: ", "))"))

        // Engine state.
        checks.append(.init(
            name: "initialization",
            passed: pipeline != nil,
            detail: pipeline != nil ? "engine initialized" : "engine not initialized"))

        // Smoke synthesis: the end-to-end path must produce audio.
        if pipeline != nil {
            do {
                let audio = try await synthesize(text: "Verification.", voice: .isla)
                checks.append(.init(
                    name: "smoke synthesis",
                    passed: !audio.samples.isEmpty,
                    detail: audio.samples.isEmpty
                        ? "produced no samples"
                        : "produced \(audio.samples.count) samples"))
            } catch {
                checks.append(.init(
                    name: "smoke synthesis",
                    passed: false,
                    detail: "failed: \(error.localizedDescription)"))
            }
        }

        return VerificationResult(
            isHealthy: checks.allSatisfy(\.passed),
            checks: checks)
    }

    /// Synthesizes input whose interpretation the caller has stated (TXT-003).
    ///
    /// The mode is never inferred: `.plainText` speaks markup characters
    /// literally, `.markup` parses them, `.phonemes` bypasses the front end.
    public func synthesize(
        input: SynthesisInput,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        priority: SynthesisExecutionPriority = .automatic
    ) async throws -> SynthesisResult {
        try validateSynthesisState()

        try validateInput(input)
        let unknown = input.unknownPhonemeSymbols
        guard unknown.isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "input",
                reason: "Phonemes outside the documented inventory: \(unknown.joined(separator: ", "))")
        }

        guard let pipeline = pipeline else { throw ChoirError.notInitialized }
        try await acquireSynthesisPermit()
        defer { releaseSynthesisPermit() }

        switch input {
        case .markup(let text):
            return try await pipeline.synthesizeMultiVoice(
                text: text,
                defaultVoice: voice,
                parameters: parameters,
                priority: priority)
        case .plainText, .phonemes:
            return try await pipeline.synthesizeWithMetadata(
                input: input,
                voice: voice,
                parameters: parameters,
                priority: priority)
        }
    }

    /// Synthesizes caller-specified phonemes with optional aligned duration
    /// and pitch targets, bypassing the linguistic front end (TXT-050).
    public func synthesize(
        phonemeProsody: PhonemeProsodySequence,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        priority: SynthesisExecutionPriority = .automatic
    ) async throws -> SynthesisResult {
        try validateSynthesisState()
        try phonemeProsody.validate()
        guard let pipeline = pipeline else { throw ChoirError.notInitialized }

        try await acquireSynthesisPermit()
        defer { releaseSynthesisPermit() }
        return try await pipeline.synthesizeWithMetadata(
            phonemeProsody: phonemeProsody,
            voice: voice,
            parameters: parameters,
            priority: priority)
    }

    /// Estimates how long `text` takes to speak, without synthesizing it
    /// (SRS SYN-010).
    ///
    /// Intended for layout, pagination and video planning, where a fast answer
    /// matters more than an exact one; the requirement's tolerance is ±10%.
    /// Does not require the engine to be initialized, since it runs no model.
    public nonisolated func estimateDuration(
        text: String,
        voice: Voice,
        rate: Double = 1.0
    ) -> DurationEstimate {
        DurationEstimator().estimate(text: text, voice: voice, rate: rate)
    }

    /// Synthesizes `text` and returns the audio together with the timing
    /// metadata SYN-005 requires.
    ///
    /// Use this wherever the caller needs to know *when* something is spoken:
    /// verse highlighting, subtitle and caption sync, lip-sync, and timeline
    /// placement. ``synthesize(text:voice:parameters:)`` remains for callers
    /// that only want audio.
    public func synthesizeWithMetadata(
        text: String,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        priority: SynthesisExecutionPriority = .automatic
    ) async throws -> SynthesisResult {
        try await synthesize(
            input: .markup(text),
            voice: voice,
            parameters: parameters,
            priority: priority)
    }

    /// Synthesizes text to audio in streaming mode, yielding audio chunks as they are produced.
    ///
    /// - Parameters:
    ///   - text: The text to synthesize.
    ///   - voice: The voice to use.
    ///   - parameters: Optional synthesis parameters.
    ///   - options: Optional streaming options.
    ///   - onChunk: Called for each audio chunk produced.
    /// - Throws: `ChoirError` if streaming fails.
    public func streamSynthesis(
        text: String,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        options: StreamingOptions = StreamingOptions(),
        onChunk: @escaping @Sendable (AudioChunk) async throws -> Void
    ) async throws {
        try validateSynthesisState()
        try validateText(text)
        try options.validate()

        guard let pipeline = pipeline else {
            throw ChoirError.notInitialized
        }

        if options.preloadModel, !isPipelineWarmedUp {
            try await warmUp(voice: voice, priority: options.priority)
        }

        try await acquireSynthesisPermit()
        defer { releaseSynthesisPermit() }

        let streamPipeline = StreamingSynthesisPipeline(
            pipeline: pipeline,
            chunkSize: options.chunkSize
        )

        try await streamPipeline.streamSynthesis(
            text: text,
            voice: voice,
            parameters: parameters,
            priority: options.priority,
            onChunk: onChunk
        )
    }

    /// Streams PCM and synchronized word/phoneme/mark updates (STR-001/004).
    public func streamSynthesisWithMetadata(
        input: SynthesisInput,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        options: StreamingOptions = StreamingOptions(),
        onChunk: @escaping @Sendable (SynthesisStreamChunk) async throws -> Void
    ) async throws {
        try validateSynthesisState()
        try validateInput(input)
        try options.validate()
        guard let pipeline = pipeline else { throw ChoirError.notInitialized }

        if options.preloadModel, !isPipelineWarmedUp {
            try await warmUp(voice: voice, priority: options.priority)
        }

        try await acquireSynthesisPermit()
        defer { releaseSynthesisPermit() }
        let streamPipeline = StreamingSynthesisPipeline(
            pipeline: pipeline,
            chunkSize: options.chunkSize)
        try await streamPipeline.streamSynthesisWithMetadata(
            input: input,
            voice: voice,
            parameters: parameters,
            priority: options.priority,
            onChunk: onChunk)
    }

    /// Streams fully specified phoneme/prosody input (TXT-050/STR-004).
    public func streamSynthesisWithMetadata(
        phonemeProsody: PhonemeProsodySequence,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        options: StreamingOptions = StreamingOptions(),
        onChunk: @escaping @Sendable (SynthesisStreamChunk) async throws -> Void
    ) async throws {
        try validateSynthesisState()
        try phonemeProsody.validate()
        try options.validate()
        guard let pipeline = pipeline else { throw ChoirError.notInitialized }

        if options.preloadModel, !isPipelineWarmedUp {
            try await warmUp(voice: voice, priority: options.priority)
        }

        try await acquireSynthesisPermit()
        defer { releaseSynthesisPermit() }
        let streamPipeline = StreamingSynthesisPipeline(
            pipeline: pipeline,
            chunkSize: options.chunkSize)
        try await streamPipeline.streamSynthesisWithMetadata(
            phonemeProsody: phonemeProsody,
            voice: voice,
            parameters: parameters,
            priority: options.priority,
            onChunk: onChunk)
    }

    /// Preloads the built-in lexicon and executes a tiny model/vocoder pass so
    /// lazy model loading and compute-graph compilation happen before the
    /// user's first requested utterance (SYN-009).
    public func warmUp(
        voice: Voice = .isla,
        priority: SynthesisExecutionPriority = .utility
    ) async throws {
        if case .uninitialized = state {
            try await initialize()
        }
        try validateSynthesisState()
        guard let pipeline = pipeline else { throw ChoirError.notInitialized }
        if isPipelineWarmedUp { return }
        if let warmUpTask {
            try await warmUpTask.value
            try Cancellation.check()
            return
        }

        let task = Task {
            try await self.performWarmUp(
                pipeline: pipeline, voice: voice, priority: priority)
        }
        warmUpTask = task
        do {
            try await task.value
            isPipelineWarmedUp = true
            warmUpTask = nil
            try Cancellation.check()
        } catch {
            warmUpTask = nil
            throw error
        }
    }

    /// Whether ``warmUp(voice:priority:)`` has completed successfully.
    public func isWarmedUp() -> Bool { isPipelineWarmedUp }

    /// Exports audio to a specific format.
    ///
    /// - Parameters:
    ///   - audio: The audio buffer to export.
    ///   - format: The desired output format (.wav, .mp3, .aac, etc).
    /// - Returns: `AudioOutput` in the requested format.
    /// - Throws: `ChoirError` if encoding fails.
    public func exportAudio(_ audio: AudioBuffer, format: AudioOutputFormat) throws -> AudioOutput {
        let encoder = AudioEncoder()
        switch format {
        case .wav:
            return .wav(try encoder.encodeWAV(audio))
        case .mp3:
            return .mp3(try encoder.encodeMP3(audio))
        case .aac:
            return .aac(try encoder.encodeAAC(audio))
        case .flac:
            _ = try encoder.encodeFLAC(audio)
            throw ChoirError.audioEncodingFailed(
                reason: "FLAC has no AudioOutput representation in this API version")
        }
    }

    /// Releases the initialized pipeline and any model resources it owns.
    ///
    /// The engine must be initialized again before its next synthesis. An
    /// active request keeps its pipeline until it completes; calling this
    /// while synthesis is active is therefore a no-op.
    public func clearCache() {
        guard activeSynthesisJobs == 0 else { return }
        guard permitWaiters.isEmpty else { return }
        guard warmUpTask == nil else { return }
        pipeline = nil
        isPipelineWarmedUp = false
        state = .uninitialized
    }

    // MARK: - Private Helpers

    private func performWarmUp(
        pipeline: SynthesisPipeline,
        voice: Voice,
        priority: SynthesisExecutionPriority
    ) async throws {
        try await acquireSynthesisPermit()
        defer { releaseSynthesisPermit() }
        BuiltInLexicon.shared.preload()
        try await pipeline.warmUp(voice: voice, priority: priority)
    }

    private func validateSynthesisState() throws {
        switch state {
        case .ready, .synthesizing:
            return
        case .initializing:
            throw ChoirError.engineBusy
        case .error(let error):
            throw error
        case .uninitialized:
            throw ChoirError.notInitialized
        }
    }

    /// Acquires one of the engine's FIFO synthesis slots. The actor remains
    /// reentrant while model inference awaits, so two granted jobs can execute
    /// concurrently even though slot accounting itself is isolated.
    private func acquireSynthesisPermit() async throws {
        try Cancellation.check()
        if activeSynthesisJobs < maximumConcurrentJobs {
            activeSynthesisJobs += 1
            state = .synthesizing
            return
        }

        let id = UUID()
        let result: Result<Void, ChoirError> = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: .failure(.cancelled))
                } else {
                    self.permitWaiters.append(PermitWaiter(
                        id: id,
                        continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelPermitWaiter(id) }
        }
        try result.get()
    }

    /// Transfers a released slot directly to the oldest waiter. Keeping the
    /// active count unchanged during a transfer prevents a later arrival from
    /// jumping the queue.
    private func releaseSynthesisPermit() {
        guard activeSynthesisJobs > 0 else { return }
        if !permitWaiters.isEmpty {
            let waiter = permitWaiters.removeFirst()
            waiter.continuation.resume(returning: .success(()))
            return
        }

        activeSynthesisJobs -= 1
        if activeSynthesisJobs == 0 { state = .ready }
    }

    private func cancelPermitWaiter(_ id: UUID) {
        guard let index = permitWaiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = permitWaiters.remove(at: index)
        waiter.continuation.resume(returning: .failure(.cancelled))
    }

    /// The largest input accepted, per SRS TXT-001.
    ///
    /// "The engine shall accept arbitrary Unicode (UTF-8) input strings from 1
    /// character to at least 1,000,000 characters per request, subject only to
    /// documented memory-based limits per platform."
    ///
    /// This was 5,000 — two orders of magnitude below the requirement, and
    /// small enough to reject a single chapter of the audiobooks the
    /// specification names as a primary workload. The ceiling exists to turn
    /// an unbounded allocation into a typed error rather than to cap ordinary
    /// use, so it sits at the documented figure rather than below it.
    static let maximumInputCharacters = 1_000_000

    private func validateText(_ text: String) throws {
        guard !text.isEmpty else {
            throw ChoirError.invalidParameter(parameter: "text", reason: "Text cannot be empty")
        }
        guard text.count <= Self.maximumInputCharacters else {
            throw ChoirError.invalidParameter(
                parameter: "text",
                reason: "Text exceeds the maximum of \(Self.maximumInputCharacters) characters (TXT-001)")
        }
    }

    private func validateInput(_ input: SynthesisInput) throws {
        guard !input.isEmpty else {
            throw ChoirError.textProcessingFailed(reason: "Input is empty")
        }
        switch input {
        case .plainText(let text), .markup(let text):
            try validateText(text)
        case .phonemes(let phonemes):
            guard phonemes.count <= Self.maximumInputCharacters else {
                throw ChoirError.invalidParameter(
                    parameter: "input",
                    reason: "Phoneme input exceeds the maximum of \(Self.maximumInputCharacters) symbols")
            }
        }
    }
}

/// Supported audio export formats.
public enum AudioOutputFormat: Sendable {
    case wav
    case mp3
    case aac
    case flac
}
