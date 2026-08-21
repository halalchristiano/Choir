import Foundation

/// The main Choir synthesis engine for on-device text-to-speech.
///
/// ChoirEngine provides both streaming (incremental) and batch (offline) synthesis modes,
/// with full parametric control over prosody, emotion, and expression.
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
    private let audioFormat: AudioFormat
    private var pipeline: SynthesisPipeline?

    /// Creates a new Choir synthesis engine.
    ///
    /// - Parameter audioFormat: The audio format for all synthesis output. Default is 48kHz mono 16-bit.
    public init(audioFormat: AudioFormat = AudioFormat()) {
        self.audioFormat = audioFormat
    }

    /// Initializes the engine, loading necessary models and resources.
    ///
    /// This must be called before any synthesis operations. Can be called multiple times;
    /// subsequent calls are no-ops if already initialized.
    ///
    /// - Throws: `ChoirError` if model loading fails.
    public func initialize() async throws {
        guard case .uninitialized = state else { return }

        // Initialize synthesis pipeline with default components
        self.pipeline = SynthesisPipeline(audioFormat: audioFormat)

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
        parameters: SynthesisParameters = SynthesisParameters()
    ) async throws -> AudioBuffer {
        try validateState()
        try validateText(text)

        guard let pipeline = pipeline else {
            throw ChoirError.notInitialized
        }

        // SYN-007 requires cancellation to leave the model "in a reusable
        // state". The engine holds no per-request mutable state, so restoring
        // `state` on every exit path — including a throw from a cancellation
        // check partway through a stage — is the whole guarantee.
        let savedState = state
        self.state = .synthesizing
        defer { self.state = savedState }

        return try await pipeline.synthesize(text: text, voice: voice, parameters: parameters)
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
        policy: PartialFailurePolicy = .failFast
    ) async throws -> BatchResult {
        try validateState()
        guard let pipeline = pipeline else { throw ChoirError.notInitialized }

        var outcomes: [BatchItemOutcome] = []
        outcomes.reserveCapacity(texts.count)

        for (index, text) in texts.enumerated() {
            // Checked before each item so a cancelled batch stops without
            // starting work it will discard.
            try Cancellation.check()

            do {
                let audio = try await pipeline.synthesize(
                    text: text, voice: voice, parameters: parameters)
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
        parameters: SynthesisParameters = SynthesisParameters()
    ) async throws -> SynthesisResult {
        try validateState()

        guard !input.isEmpty else {
            throw ChoirError.textProcessingFailed(reason: "Input is empty")
        }
        let unknown = input.unknownPhonemeSymbols
        guard unknown.isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "input",
                reason: "Phonemes outside the documented inventory: \(unknown.joined(separator: ", "))")
        }

        guard let pipeline = pipeline else { throw ChoirError.notInitialized }

        switch input {
        case .markup(let text):
            return try await pipeline.synthesizeMultiVoice(
                text: text, defaultVoice: voice, parameters: parameters)
        case .plainText(let text):
            let escaped = text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return try await pipeline.synthesizeWithMetadata(
                text: escaped, voice: voice, parameters: parameters)
        case .phonemes:
            throw ChoirError.synthesisError(
                reason: "Pre-phonemized synthesis requires an acoustic model; the front-end path is available via LinguisticFrontend.process(_:)")
        }
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
        parameters: SynthesisParameters = SynthesisParameters()
    ) async throws -> SynthesisResult {
        try validateState()
        try validateText(text)

        guard let pipeline = pipeline else {
            throw ChoirError.notInitialized
        }

        return try await pipeline.synthesizeWithMetadata(
            text: text,
            voice: voice,
            parameters: parameters
        )
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
        onChunk: @Sendable (AudioChunk) async throws -> Void
    ) async throws {
        try validateState()
        try validateText(text)

        guard let pipeline = pipeline else {
            throw ChoirError.notInitialized
        }

        let savedState = state
        self.state = .synthesizing
        defer { self.state = savedState }

        let streamPipeline = StreamingSynthesisPipeline(
            pipeline: pipeline,
            chunkSize: options.chunkSize
        )

        try await streamPipeline.streamSynthesis(
            text: text,
            voice: voice,
            parameters: parameters,
            onChunk: onChunk
        )
    }

    /// Exports audio to a specific format.
    ///
    /// - Parameters:
    ///   - audio: The audio buffer to export.
    ///   - format: The desired output format (.wav, .mp3, .aac, etc).
    /// - Returns: `AudioOutput` in the requested format.
    /// - Throws: `ChoirError` if encoding fails.
    public func exportAudio(_ audio: AudioBuffer, format: AudioOutputFormat) throws -> AudioOutput {
        // TODO: Implement audio encoding to WAV, MP3, AAC
        throw ChoirError.unknown("Audio export not yet implemented")
    }

    /// Clears cached models and resources to free memory.
    public func clearCache() {
        // TODO: Implement cache clearing
    }

    // MARK: - Private Helpers

    private func validateState() throws {
        guard case .ready = state else {
            throw ChoirError.notInitialized
        }
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
}

/// Supported audio export formats.
public enum AudioOutputFormat: Sendable {
    case wav
    case mp3
    case aac
    case flac
}
