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

        let savedState = state
        self.state = .synthesizing
        defer { self.state = savedState }

        return try await pipeline.synthesize(text: text, voice: voice, parameters: parameters)
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

    private func validateText(_ text: String) throws {
        guard !text.isEmpty else {
            throw ChoirError.invalidParameter(parameter: "text", reason: "Text cannot be empty")
        }
        guard text.count <= 5000 else {
            throw ChoirError.invalidParameter(parameter: "text", reason: "Text exceeds maximum length of 5000 characters")
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
