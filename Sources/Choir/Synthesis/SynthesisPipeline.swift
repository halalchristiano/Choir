import Foundation

/// Complete synthesis pipeline orchestrating all stages from text to audio.
public struct SynthesisPipeline: Sendable {
    /// Linguistic front end for text processing.
    private let linguisticFrontend: LinguisticFrontend

    /// Prosody prediction.
    private let prosodyPredictor: ProsodyPredictor

    /// Acoustic model for feature generation.
    private let acousticModel: any AcousticModelProtocol

    /// Vocoder for waveform generation.
    private let vocoder: any VocoderProtocol

    /// Phoneme encoder for model input.
    private let phonemeEncoder: PhonemeEncoder

    /// Audio format specifications.
    private let audioFormat: AudioFormat

    public init(
        linguisticFrontend: LinguisticFrontend = LinguisticFrontend(),
        prosodyPredictor: ProsodyPredictor = ProsodyPredictor(),
        acousticModel: any AcousticModelProtocol = MockAcousticModel(),
        vocoder: any VocoderProtocol = MockVocoder(),
        phonemeEncoder: PhonemeEncoder = PhonemeEncoder(),
        audioFormat: AudioFormat = AudioFormat()
    ) {
        self.linguisticFrontend = linguisticFrontend
        self.prosodyPredictor = prosodyPredictor
        self.acousticModel = acousticModel
        self.vocoder = vocoder
        self.phonemeEncoder = phonemeEncoder
        self.audioFormat = audioFormat
    }

    /// Executes the complete synthesis pipeline.
    ///
    /// Pipeline stages:
    /// 1. Text processing (normalization, phonemization, stress)
    /// 2. Prosody prediction (pitch, duration, energy)
    /// 3. Acoustic modeling (acoustic features)
    /// 4. Vocoding (PCM waveform)
    ///
    /// - Parameters:
    ///   - text: Input text with optional SSML markup.
    ///   - voice: Voice selection.
    ///   - parameters: Synthesis parameters (pitch, rate, emotion, etc).
    /// - Returns: Synthesized audio buffer.
    /// - Throws: `ChoirError` if any pipeline stage fails.
    public func synthesize(
        text: String,
        voice: Voice,
        parameters: SynthesisParameters
    ) async throws -> AudioBuffer {
        // Stage 1: Text processing
        let transcript = try linguisticFrontend.process(text)

        // Stage 2: Prosody prediction
        let prosody = prosodyPredictor.predictProsody(for: transcript, with: parameters)

        // Stage 3: Acoustic modeling
        let acousticInput = createAcousticInput(from: prosody, voice: voice)
        let acousticFeatures = try await acousticModel.predict(input: acousticInput)

        // Stage 4: Vocoding
        let pcmSamples = try await vocoder.synthesize(
            features: acousticFeatures,
            sampleRate: audioFormat.sampleRate
        )

        return AudioBuffer(samples: pcmSamples, format: audioFormat)
    }

    /// Creates acoustic model input from prosody prediction.
    private func createAcousticInput(
        from prosody: ProsodyDescription,
        voice: Voice
    ) -> AcousticModelInput {
        let phonemeIndices = phonemeEncoder.encode(prosody.phonemes.map { $0.phoneme })

        let durations = prosody.phonemes.map { $0.prosody.duration }
        let fundamentalFrequency = prosody.phonemes.map { $0.prosody.fundamentalFrequency }
        let energy = prosody.phonemes.map { $0.prosody.energy }
        let stress = prosody.phonemes.map { Int($0.phoneme.stress) }
        let voicing = prosody.phonemes.map { $0.prosody.voicing }

        // Map voice to voice ID
        let voiceID = voice.ageBand

        return AcousticModelInput(
            phonemeIndices: phonemeIndices,
            durations: durations,
            fundamentalFrequency: fundamentalFrequency,
            energy: energy,
            stress: stress,
            voicing: voicing,
            voiceID: voiceID
        )
    }
}

/// Streaming synthesis pipeline for real-time synthesis.
public struct StreamingSynthesisPipeline: Sendable {
    /// Underlying synthesis pipeline.
    private let pipeline: SynthesisPipeline

    /// Chunk size in samples.
    private let chunkSize: Int

    public init(
        pipeline: SynthesisPipeline = SynthesisPipeline(),
        chunkSize: Int = 2400  // 50ms at 48kHz
    ) {
        self.pipeline = pipeline
        self.chunkSize = chunkSize
    }

    /// Streams synthesis output in chunks.
    ///
    /// - Parameters:
    ///   - text: Input text.
    ///   - voice: Voice selection.
    ///   - parameters: Synthesis parameters.
    ///   - onChunk: Called for each audio chunk produced.
    /// - Throws: `ChoirError` if synthesis fails.
    public func streamSynthesis(
        text: String,
        voice: Voice,
        parameters: SynthesisParameters,
        onChunk: @Sendable (AudioChunk) async throws -> Void
    ) async throws {
        // Synthesize complete audio first
        let audio = try await pipeline.synthesize(text: text, voice: voice, parameters: parameters)

        // Stream in chunks
        let samples = audio.samples
        var offset = 0
        var timestamp = 0.0

        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            let chunk = Array(samples[offset..<end])
            let isFinal = end >= samples.count

            let audioChunk = AudioChunk(samples: chunk, isFinal: isFinal, timestamp: timestamp)
            try await onChunk(audioChunk)

            offset = end
            timestamp += Double(chunk.count) / Double(audio.format.sampleRate)
        }
    }
}
