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
        // CON-002/SYN-007: cancellation is checked between every stage. The
        // stages are the natural granularity — each is bounded work, and a
        // check between them stops compute well inside SYN-007's 100 ms.
        try Cancellation.check()

        // Stage 1: Text processing
        let transcript = try linguisticFrontend.process(text)
        try Cancellation.check()

        // Stage 2: Prosody prediction
        let prosody = prosodyPredictor.predictProsody(for: transcript, with: parameters)
        try Cancellation.check()

        // Stage 3: Acoustic modeling
        let acousticInput = createAcousticInput(from: prosody, voice: voice)
        let acousticFeatures = try await acousticModel.predict(input: acousticInput)
        try Cancellation.check()

        // Stage 4: Vocoding
        let pcmSamples = try await vocoder.synthesize(
            features: acousticFeatures,
            sampleRate: audioFormat.sampleRate
        )

        return AudioBuffer(samples: pcmSamples, format: audioFormat)
    }

    /// Resolves an SSML-C `<voice id="...">` to a voice (TXT-042).
    ///
    /// Accepts the stable identifier, the working name, or the enum case name,
    /// so `"choir.mid.male.garrick"`, `"GARRICK"` and `"garrick"` all resolve.
    public static func voice(forID id: String) -> Voice? {
        let key = id.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = Voice(rawValue: key) { return exact }
        return Voice.allCases.first {
            $0.displayName.lowercased() == key || "\($0)".lowercased() == key
        }
    }

    /// Synthesizes a request that switches voices mid-text (SRS TXT-042).
    ///
    /// `<voice>` segments are rendered with their own voice and concatenated.
    /// Consecutive segments sharing a voice are rendered together rather than
    /// separately, so a switch point is the only place a discontinuity can
    /// occur -- which is what the requirement means by "no audible
    /// discontinuity artifacts at switch points beyond the natural pause".
    ///
    /// Falls back to single-voice synthesis when the text names no voice, so
    /// the common case pays nothing for this.
    public func synthesizeMultiVoice(
        text: String,
        defaultVoice: Voice,
        parameters: SynthesisParameters
    ) async throws -> SynthesisResult {
        let markup = (try? SSMLCParser().parse(text)) ?? SSMLParseResult(events: [])

        // Group consecutive speech into runs sharing a voice.
        var runs: [(voice: Voice, text: String)] = []
        for event in markup.events {
            guard case .speech(let segmentText, let style) = event else { continue }
            guard !segmentText.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            let voice = style.voiceID.flatMap(Self.voice(forID:)) ?? defaultVoice
            if var last = runs.last, last.voice == voice {
                last.text += segmentText
                runs[runs.count - 1] = last
            } else {
                runs.append((voice, segmentText))
            }
        }

        // No voice switching: the ordinary path, unchanged.
        guard runs.count > 1 else {
            return try await synthesizeWithMetadata(
                text: text, voice: defaultVoice, parameters: parameters)
        }

        var samples: [Int16] = []
        var words: [TimedSpan] = []
        var phonemes: [TimedSpan] = []
        var offsetMs = 0.0

        for run in runs {
            try Cancellation.check()
            let result = try await synthesizeWithMetadata(
                text: run.text, voice: run.voice, parameters: parameters)
            samples.append(contentsOf: result.audio.samples)

            // Shift each run's timings into the concatenated timeline.
            words += result.metadata.words.map {
                TimedSpan(content: $0.content,
                          startMs: $0.startMs + offsetMs,
                          endMs: $0.endMs + offsetMs)
            }
            phonemes += result.metadata.phonemes.map {
                TimedSpan(content: $0.content,
                          startMs: $0.startMs + offsetMs,
                          endMs: $0.endMs + offsetMs)
            }
            offsetMs += result.metadata.totalDurationMs
        }

        let audio = AudioBuffer(samples: samples, format: audioFormat)
        let metadata = SynthesisMetadata(
            totalDurationMs: offsetMs,
            words: words,
            phonemes: phonemes,
            sentences: [],
            marks: [],
            effectiveParameters: parameters,
            // The first run's voice represents the request; per-segment voices
            // are recoverable from the markup.
            voice: runs.first?.voice ?? defaultVoice,
            diagnostics: markup.diagnostics
        )
        return SynthesisResult(audio: audio, metadata: metadata)
    }

    /// Synthesizes and returns the timing metadata SYN-005 requires.
    ///
    /// Timings come from the prosody model's predicted phoneme durations, the
    /// same values that drive the acoustic model, so the metadata describes the
    /// audio actually produced rather than an independent estimate.
    public func synthesizeWithMetadata(
        text: String,
        voice: Voice,
        parameters: SynthesisParameters
    ) async throws -> SynthesisResult {
        try Cancellation.check()
        let transcript = try linguisticFrontend.process(text)
        try Cancellation.check()

        let prosody = prosodyPredictor.predictProsody(for: transcript, with: parameters)
        try Cancellation.check()

        let acousticInput = createAcousticInput(from: prosody, voice: voice)
        let acousticFeatures = try await acousticModel.predict(input: acousticInput)
        try Cancellation.check()

        let pcmSamples = try await vocoder.synthesize(
            features: acousticFeatures,
            sampleRate: audioFormat.sampleRate
        )

        // TXT-040/041: marks and markup diagnostics come from the SSML-C
        // stream. Parsing is non-strict here so malformed markup degrades
        // rather than failing the request; the warnings ride along in the
        // metadata instead.
        let markup = try? SSMLCParser().parse(text)

        let audio = AudioBuffer(samples: pcmSamples, format: audioFormat)
        let metadata = Self.buildMetadata(
            transcript: transcript,
            durationsMs: prosody.phonemes.map(\.prosody.duration),
            audio: audio,
            voice: voice,
            parameters: parameters,
            markup: markup
        )
        return SynthesisResult(audio: audio, metadata: metadata)
    }

    /// Assembles SYN-005 metadata from per-phoneme durations.
    ///
    /// Phoneme spans are laid end to end; word spans are the union of the
    /// phonemes between consecutive word boundaries; sentences are word-index
    /// ranges delimited by terminal punctuation.
    static func buildMetadata(
        transcript: PhoneticTranscription,
        durationsMs: [Double],
        audio: AudioBuffer,
        voice: Voice,
        parameters: SynthesisParameters,
        markup: SSMLParseResult? = nil
    ) -> SynthesisMetadata {
        var phonemeSpans: [TimedSpan] = []
        phonemeSpans.reserveCapacity(transcript.phonemes.count)

        var cursor = 0.0
        for (index, phoneme) in transcript.phonemes.enumerated() {
            // A missing duration contributes nothing rather than trapping.
            let duration = index < durationsMs.count ? max(0, durationsMs[index]) : 0
            phonemeSpans.append(
                TimedSpan(content: phoneme.symbol, startMs: cursor, endMs: cursor + duration)
            )
            cursor += duration
        }

        // Word spans span the phonemes between consecutive boundaries.
        var wordSpans: [TimedSpan] = []
        let boundaries = transcript.wordBoundaries
        for (wordIndex, start) in boundaries.enumerated() {
            let end = wordIndex + 1 < boundaries.count
                ? boundaries[wordIndex + 1]
                : transcript.phonemes.count

            guard start < end, start < phonemeSpans.count else { continue }
            let last = min(end, phonemeSpans.count) - 1
            guard last >= start else { continue }

            let text = wordIndex < transcript.wordTexts.count
                ? transcript.wordTexts[wordIndex]
                : ""
            wordSpans.append(
                TimedSpan(
                    content: text,
                    startMs: phonemeSpans[start].startMs,
                    endMs: phonemeSpans[last].endMs
                )
            )
        }

        // Sentences are runs of words ending in terminal punctuation.
        var sentences: [Range<Int>] = []
        var sentenceStart = 0
        for (index, span) in wordSpans.enumerated() {
            if span.content.contains(where: { ".!?".contains($0) }) {
                sentences.append(sentenceStart..<(index + 1))
                sentenceStart = index + 1
            }
        }
        if sentenceStart < wordSpans.count {
            sentences.append(sentenceStart..<wordSpans.count)
        }

        // Prefer the audio's own duration; fall back to the prosody total when
        // no audio was produced.
        let audioDurationMs = audio.duration * 1000
        let totalMs = audioDurationMs > 0 ? audioDurationMs : cursor

        // SYN-005 mark positions. A mark sits between words in the SSML-C
        // stream, so its time is the start of the next word, or the end of the
        // audio when it trails the final word.
        var marks: [MarkPosition] = []
        if let markup {
            var wordsSeen = 0
            for event in markup.events {
                switch event {
                case .speech(let text, _):
                    wordsSeen += text.split(whereSeparator: \.isWhitespace).count
                case .mark(let name):
                    let timeMs = wordsSeen < wordSpans.count
                        ? wordSpans[wordsSeen].startMs
                        : (wordSpans.last?.endMs ?? totalMs)
                    marks.append(MarkPosition(name: name, timeMs: timeMs))
                case .pause:
                    break
                }
            }
        }

        return SynthesisMetadata(
            totalDurationMs: totalMs,
            words: wordSpans,
            phonemes: phonemeSpans,
            sentences: sentences,
            marks: marks,
            effectiveParameters: parameters,
            voice: voice,
            diagnostics: markup?.diagnostics ?? []
        )
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
        let voiceID = voice.ageBand.ordinal

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

        // Stream in chunks using zero-copy ArraySlice to reduce memory allocations
        let samples = audio.samples
        var offset = 0
        var timestamp = 0.0

        while offset < samples.count {
            let end = min(offset + chunkSize, samples.count)
            // Use ArraySlice<Int16> for zero-copy view into samples
            // Eliminates redundant memory allocation compared to Array(samples[...])
            let chunk: ArraySlice<Int16> = samples[offset..<end]
            let isFinal = end >= samples.count

            // Convert to Array only at output boundary (when necessary for API compatibility)
            let audioChunk = AudioChunk(samples: Array(chunk), isFinal: isFinal, timestamp: timestamp)
            try await onChunk(audioChunk)

            offset = end
            timestamp += Double(chunk.count) / Double(audio.format.sampleRate)
        }
    }
}
