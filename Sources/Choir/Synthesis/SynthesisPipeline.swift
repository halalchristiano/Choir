import Foundation

/// Complete synthesis pipeline orchestrating all stages from text to audio.
public struct SynthesisPipeline: Sendable {
    /// Batch results are retained in memory as `[Int16]`. Refuse a request
    /// before the aggregate grows beyond a documented, deterministic budget
    /// instead of relying on an allocator trap. Long-form callers should use
    /// streaming or a resumable file-backed job.
    static let maximumAccumulatedSamples = 50_000_000

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

    /// Format shared with the streaming adapter in this file.
    fileprivate var outputFormat: AudioFormat { audioFormat }

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
        parameters: SynthesisParameters,
        priority: SynthesisExecutionPriority = .automatic
    ) async throws -> AudioBuffer {
        let result = try await synthesizeMultiVoice(
            text: text,
            defaultVoice: voice,
            parameters: parameters,
            priority: priority)
        return result.audio
    }

    /// Synthesizes an explicitly selected input mode and returns complete
    /// timing metadata. This is the common implementation for plain text,
    /// markup, and pre-phonemized Tier-3 input.
    public func synthesizeWithMetadata(
        input: SynthesisInput,
        voice: Voice,
        parameters: SynthesisParameters,
        priority: SynthesisExecutionPriority = .automatic
    ) async throws -> SynthesisResult {
        try await SynthesisExecutor.run(priority: priority) {
            let prepared = try self.prepare(
                input: input, voice: voice, parameters: parameters)
            return try await self.render(prepared: prepared, voice: voice)
        }
    }

    /// Synthesizes a fully specified phoneme/prosody sequence (TXT-050).
    /// Optional duration and pitch tensors override prediction independently.
    public func synthesizeWithMetadata(
        phonemeProsody: PhonemeProsodySequence,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        priority: SynthesisExecutionPriority = .automatic
    ) async throws -> SynthesisResult {
        try await SynthesisExecutor.run(priority: priority) {
            let prepared = try self.prepare(
                phonemeProsody: phonemeProsody,
                voice: voice,
                parameters: parameters)
            return try await self.render(prepared: prepared, voice: voice)
        }
    }

    /// Performs the same model/vocoder initialization work as a real request,
    /// but discards the short result (SYN-009).
    public func warmUp(
        voice: Voice = .isla,
        priority: SynthesisExecutionPriority = .utility
    ) async throws {
        let warmup = PhonemeProsodySequence(
            phonemes: [Phoneme("h"), Phoneme("ə")],
            durationsMs: [40, 40],
            pitchTargetsHz: [0, voice.profile.medianF0])
        _ = try await synthesizeWithMetadata(
            phonemeProsody: warmup,
            voice: voice,
            parameters: SynthesisParameters(seed: 0),
            priority: priority)
    }

    // MARK: - Shared batch/stream preparation

    /// A request after the front end and prosody stages, but before model or
    /// vocoder inference. Streaming renders its ranges one at a time; batch
    /// renders the exact same ranges and concatenates them, which keeps both
    /// modes on one quality path (SYN-004/STR-002).
    fileprivate struct PreparedSynthesis: Sendable {
        let transcript: PhoneticTranscription
        let prosody: ProsodyDescription
        let markup: SSMLParseResult?
        let units: [Range<Int>]
        let parameters: SynthesisParameters
    }

    fileprivate func prepare(
        input: SynthesisInput,
        voice: Voice,
        parameters: SynthesisParameters
    ) throws -> PreparedSynthesis {
        try audioFormat.validate()
        try Cancellation.check()
        let effectiveParameters = parameters.validated()
        if let text = input.text, text.count > ChoirEngine.maximumInputCharacters {
            throw ChoirError.invalidParameter(
                parameter: "input",
                reason: "Text exceeds the maximum of \(ChoirEngine.maximumInputCharacters) characters (TXT-001)")
        }
        if case .phonemes(let phonemes) = input,
           phonemes.count > ChoirEngine.maximumInputCharacters {
            throw ChoirError.invalidParameter(
                parameter: "input",
                reason: "Phoneme input exceeds the maximum of \(ChoirEngine.maximumInputCharacters) symbols")
        }

        let transcript = try linguisticFrontend.process(input)
        try Cancellation.check()
        let prosody = prosodyPredictor.predictProsody(
            for: transcript,
            with: effectiveParameters,
            voiceProfile: voice.profile)
        try Cancellation.check()

        let markup: SSMLParseResult?
        if case .markup(let text) = input {
            markup = try? SSMLCParser().parse(text)
        } else {
            markup = nil
        }

        return PreparedSynthesis(
            transcript: transcript,
            prosody: prosody,
            markup: markup,
            units: Self.synthesisUnits(
                for: transcript,
                phonemeDurationsMs: prosody.phonemes.map(\.prosody.duration)),
            parameters: effectiveParameters)
    }

    fileprivate func prepare(
        phonemeProsody: PhonemeProsodySequence,
        voice: Voice,
        parameters: SynthesisParameters
    ) throws -> PreparedSynthesis {
        try audioFormat.validate()
        try phonemeProsody.validate()
        try Cancellation.check()
        let effectiveParameters = parameters.validated()

        let transcript = phonemeProsody.transcription
        let predicted = prosodyPredictor.predictProsody(
            for: transcript,
            with: effectiveParameters,
            voiceProfile: voice.profile)
        var annotated: [AnnotatedPhoneme] = []
        annotated.reserveCapacity(predicted.phonemes.count)
        var cursor = 0.0

        for index in predicted.phonemes.indices {
            var features = predicted.phonemes[index].prosody
            if let durations = phonemeProsody.durationsMs {
                features.duration = durations[index]
            }
            if let pitches = phonemeProsody.pitchTargetsHz {
                features.fundamentalFrequency = pitches[index]
            }
            let timing = TimingInfo(
                startTime: cursor,
                endTime: cursor + features.duration)
            annotated.append(AnnotatedPhoneme(
                phoneme: predicted.phonemes[index].phoneme,
                prosody: features,
                timing: timing))
            cursor += features.duration
        }

        let pitchPoints = annotated.map {
            (time: $0.timing.midpoint, value: $0.prosody.fundamentalFrequency)
        }
        let energyPoints = annotated.map {
            (time: $0.timing.midpoint, value: $0.prosody.energy)
        }
        let prosody = ProsodyDescription(
            phonemes: annotated,
            pitchContour: ProsodyContour(points: pitchPoints),
            energyContour: ProsodyContour(points: energyPoints),
            durations: annotated.map(\.prosody.duration))

        return PreparedSynthesis(
            transcript: transcript,
            prosody: prosody,
            markup: nil,
            units: Self.synthesisUnits(
                for: transcript,
                phonemeDurationsMs: prosody.phonemes.map(\.prosody.duration)),
            parameters: effectiveParameters)
    }

    /// Natural acoustic units ending at a phrase boundary. A request with no
    /// usable boundary remains one unit. Crucially, this partitions already
    /// predicted prosody rather than reparsing each sentence, so SSML state,
    /// seeded variation, and timing stay request-global.
    static func synthesisUnits(
        for transcript: PhoneticTranscription,
        phonemeDurationsMs: [Double]? = nil
    ) -> [Range<Int>] {
        guard !transcript.phonemes.isEmpty else { return [] }

        var units: [Range<Int>] = []
        var start = 0
        for wordIndex in transcript.wordBoundaries.indices {
            guard transcript.phraseBoundaries[wordIndex] != nil else { continue }
            let end = wordIndex + 1 < transcript.wordBoundaries.count
                ? transcript.wordBoundaries[wordIndex + 1]
                : transcript.phonemes.count
            guard end > start else { continue }
            units.append(start..<end)
            start = end
        }
        if start < transcript.phonemes.count {
            units.append(start..<transcript.phonemes.count)
        }
        if units.isEmpty { units = [0..<transcript.phonemes.count] }

        // Bound every model invocation even for pre-phonemized input with no
        // word/phrase boundaries. Both limits mirror AcousticModelInput's
        // validation. Prefer a word boundary when one is available, falling
        // back to a mechanical split for a single exceptionally long word.
        let maximumPhonemesPerUnit = 512
        let maximumDurationMsPerUnit = 600_000.0
        let durations = phonemeDurationsMs?.count == transcript.phonemes.count
            ? phonemeDurationsMs
            : nil
        let wordStarts = Set(transcript.wordBoundaries)

        return units.flatMap { unit -> [Range<Int>] in
            var partitions: [Range<Int>] = []
            var lower = unit.lowerBound
            var index = lower
            var durationMs = 0.0
            var lastWordBoundary: Int?

            while index < unit.upperBound {
                if index > lower, wordStarts.contains(index) {
                    lastWordBoundary = index
                }
                let nextDuration = durations?[index] ?? 0
                let exceedsCount = index - lower >= maximumPhonemesPerUnit
                let exceedsDuration = durationMs + nextDuration > maximumDurationMsPerUnit
                if exceedsCount || exceedsDuration {
                    let preferred = lastWordBoundary.flatMap { $0 > lower ? $0 : nil } ?? index
                    // Validated public durations keep `index > lower` here.
                    // Advancing one element also makes this helper total for
                    // malformed internal/test data rather than looping on an
                    // empty range.
                    let split = max(lower + 1, preferred)
                    partitions.append(lower..<split)
                    lower = split
                    index = split
                    durationMs = 0
                    lastWordBoundary = nil
                    continue
                }
                durationMs += nextDuration
                index += 1
            }
            if lower < unit.upperBound {
                partitions.append(lower..<unit.upperBound)
            }
            return partitions
        }
    }

    /// Runs acoustic-model and vocoder inference for one prepared unit.
    fileprivate func renderUnit(
        _ range: Range<Int>,
        from prepared: PreparedSynthesis,
        voice: Voice
    ) async throws -> AudioBuffer {
        try Cancellation.check()
        let annotated = Array(prepared.prosody.phonemes[range])
        let acousticInput = try createAcousticInput(
            from: annotated,
            voice: voice,
            parameters: prepared.parameters)
        let acousticFeatures = try await acousticModel.predict(input: acousticInput)
        try Cancellation.check()
        let monoSamples = try await vocoder.synthesize(
            features: acousticFeatures,
            sampleRate: audioFormat.sampleRate)
        try Cancellation.check()
        guard audioFormat.channels > 1 else {
            return AudioBuffer(samples: monoSamples, format: audioFormat)
        }
        let capacity = monoSamples.count.multipliedReportingOverflow(by: audioFormat.channels)
        guard !capacity.overflow else { throw ChoirError.outOfMemory }
        var interleaved: [Int16] = []
        interleaved.reserveCapacity(capacity.partialValue)
        for sample in monoSamples {
            interleaved.append(contentsOf: repeatElement(sample, count: audioFormat.channels))
        }
        return AudioBuffer(samples: interleaved, format: audioFormat)
    }

    /// Batch renderer shared with streaming's unit renderer.
    fileprivate func render(
        prepared: PreparedSynthesis,
        voice: Voice
    ) async throws -> SynthesisResult {
        var samples: [Int16] = []
        for unit in prepared.units {
            let audio = try await renderUnit(unit, from: prepared, voice: voice)
            _ = try Self.validatedCombinedSampleCount(
                currentCount: samples.count,
                newCount: audio.samples.count)
            samples.append(contentsOf: audio.samples)
        }

        let audio = AudioBuffer(samples: samples, format: audioFormat)
        let metadata = Self.buildMetadata(
            transcript: prepared.transcript,
            durationsMs: prepared.prosody.phonemes.map(\.prosody.duration),
            audio: audio,
            voice: voice,
            parameters: prepared.parameters,
            markup: prepared.markup)
        return SynthesisResult(audio: audio, metadata: metadata)
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
        parameters: SynthesisParameters,
        priority: SynthesisExecutionPriority = .automatic
    ) async throws -> SynthesisResult {
        let effectiveParameters = parameters.validated()
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
        if runs.count == 1, runs[0].voice != defaultVoice {
            // A single explicit <voice> still overrides the request default.
            // The old fast path discarded it unless there were two runs.
            return try await synthesizeWithMetadata(
                text: text,
                voice: runs[0].voice,
                parameters: effectiveParameters,
                priority: priority)
        }

        guard runs.count > 1 else {
            return try await synthesizeWithMetadata(
                text: text,
                voice: defaultVoice,
                parameters: effectiveParameters,
                priority: priority)
        }

        var samples: [Int16] = []
        var words: [TimedSpan] = []
        var phonemes: [TimedSpan] = []
        var offsetMs = 0.0
        var diagnostics = markup.diagnostics

        for run in runs {
            try Cancellation.check()
            let result = try await synthesizeWithMetadata(
                text: run.text,
                voice: run.voice,
                parameters: effectiveParameters,
                priority: priority)
            _ = try Self.validatedCombinedSampleCount(
                currentCount: samples.count,
                newCount: result.audio.samples.count)
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
            diagnostics.append(contentsOf: result.metadata.diagnostics)
            offsetMs += result.metadata.totalDurationMs
        }

        let audio = AudioBuffer(samples: samples, format: audioFormat)
        let globalTranscript = try? linguisticFrontend.process(.markup(text))
        let sentences = Self.sentenceRanges(
            for: words,
            phraseBoundaries: globalTranscript?.phraseBoundaries ?? [:])
        let marks = globalTranscript.map {
            Self.markPositions(
                from: $0.markAnchors,
                wordSpans: words,
                totalDurationMs: offsetMs)
        } ?? Self.markPositions(
            from: markup,
            wordSpans: words,
            totalDurationMs: offsetMs)
        let metadata = SynthesisMetadata(
            totalDurationMs: offsetMs,
            words: words,
            phonemes: phonemes,
            sentences: sentences,
            marks: marks,
            effectiveParameters: effectiveParameters,
            // The first run's voice represents the request; per-segment voices
            // are recoverable from the markup.
            voice: runs.first?.voice ?? defaultVoice,
            diagnostics: diagnostics
        )
        return SynthesisResult(audio: audio, metadata: metadata)
    }

    /// Checked accumulation used by every in-memory batch assembly path.
    static func validatedCombinedSampleCount(
        currentCount: Int,
        newCount: Int
    ) throws -> Int {
        guard currentCount >= 0, newCount >= 0 else {
            throw ChoirError.outOfMemory
        }
        let combined = currentCount.addingReportingOverflow(newCount)
        guard !combined.overflow,
              combined.partialValue <= maximumAccumulatedSamples else {
            throw ChoirError.outOfMemory
        }
        return combined.partialValue
    }

    /// Synthesizes and returns the timing metadata SYN-005 requires.
    ///
    /// Timings come from the prosody model's predicted phoneme durations, the
    /// same values that drive the acoustic model, so the metadata describes the
    /// audio actually produced rather than an independent estimate.
    public func synthesizeWithMetadata(
        text: String,
        voice: Voice,
        parameters: SynthesisParameters,
        priority: SynthesisExecutionPriority = .automatic
    ) async throws -> SynthesisResult {
        return try await synthesizeWithMetadata(
            input: .markup(text),
            voice: voice,
            parameters: parameters,
            priority: priority)
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

        let predictedTotalMs = durationsMs.prefix(transcript.phonemes.count).reduce(0) {
            $0 + max(0, $1)
        }
        let audioDurationMs = audio.duration * 1000
        let durationScale = audioDurationMs > 0 && predictedTotalMs > 0
            ? audioDurationMs / predictedTotalMs
            : 1

        var cursor = 0.0
        for (index, phoneme) in transcript.phonemes.enumerated() {
            // A missing duration contributes nothing rather than trapping.
            let duration = index < durationsMs.count
                ? max(0, durationsMs[index]) * durationScale : 0
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

        let sentences = sentenceRanges(
            for: wordSpans,
            phraseBoundaries: transcript.phraseBoundaries)

        // Prefer the audio's own duration; fall back to the prosody total when
        // no audio was produced.
        let totalMs = audioDurationMs > 0 ? audioDurationMs : cursor

        // SYN-005 mark positions. A mark sits between words in the SSML-C
        // stream, so its time is the start of the next word, or the end of the
        // audio when it trails the final word.
        let marks: [MarkPosition]
        if !transcript.markAnchors.isEmpty {
            marks = markPositions(
                from: transcript.markAnchors,
                wordSpans: wordSpans,
                totalDurationMs: totalMs)
        } else {
            marks = markup.map {
                markPositions(from: $0, wordSpans: wordSpans, totalDurationMs: totalMs)
            } ?? []
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

    /// Sentence word ranges shared by ordinary and multi-voice metadata.
    static func sentenceRanges(
        for words: [TimedSpan],
        phraseBoundaries: [Int: PhraseBoundary] = [:]
    ) -> [Range<Int>] {
        guard !words.isEmpty else { return [] }
        var sentences: [Range<Int>] = []
        var sentenceStart = 0
        for (index, span) in words.enumerated() {
            let isSentenceBoundary = phraseBoundaries[index].map { $0 >= .major }
                ?? span.content.contains(where: { ".!?".contains($0) })
            if isSentenceBoundary {
                sentences.append(sentenceStart..<(index + 1))
                sentenceStart = index + 1
            }
        }
        if sentenceStart < words.count {
            sentences.append(sentenceStart..<words.count)
        }
        return sentences
    }

    /// Resolves request-wide mark positions against request-wide word spans.
    static func markPositions(
        from anchors: [TranscriptionMarkAnchor],
        wordSpans: [TimedSpan],
        totalDurationMs: Double
    ) -> [MarkPosition] {
        anchors.map { anchor in
            let timeMs = anchor.followingWordIndex < wordSpans.count
                ? wordSpans[anchor.followingWordIndex].startMs
                : (wordSpans.last?.endMs ?? totalDurationMs)
            return MarkPosition(name: anchor.name, timeMs: timeMs)
        }
    }

    /// Compatibility fallback for transcriptions constructed without
    /// normalized mark anchors.
    static func markPositions(
        from markup: SSMLParseResult,
        wordSpans: [TimedSpan],
        totalDurationMs: Double
    ) -> [MarkPosition] {
        var marks: [MarkPosition] = []
        var wordsSeen = 0
        for event in markup.events {
            switch event {
            case .speech(let text, _):
                wordsSeen += text.split(whereSeparator: \.isWhitespace).count
            case .mark(let name):
                let timeMs = wordsSeen < wordSpans.count
                    ? wordSpans[wordsSeen].startMs
                    : (wordSpans.last?.endMs ?? totalDurationMs)
                marks.append(MarkPosition(name: name, timeMs: timeMs))
            case .pause:
                break
            }
        }
        return marks
    }

    /// Creates acoustic model input from prosody prediction.
    private func createAcousticInput(
        from phonemes: [AnnotatedPhoneme],
        voice: Voice,
        parameters: SynthesisParameters
    ) throws -> AcousticModelInput {
        let phonemeIndices = try phonemeEncoder.encodeStrict(
            phonemes.map(\.phoneme))

        let durations = phonemes.map(\.prosody.duration)
        let fundamentalFrequency = phonemes.map(\.prosody.fundamentalFrequency)
        let energy = phonemes.map(\.prosody.energy)
        let stress = phonemes.map { Int($0.phoneme.stress) }
        let voicing = phonemes.map(\.prosody.voicing)

        let voiceID = voice.conditioningID

        let input = AcousticModelInput(
            phonemeIndices: phonemeIndices,
            durations: durations,
            fundamentalFrequency: fundamentalFrequency,
            energy: energy,
            stress: stress,
            voicing: voicing,
            voiceID: voiceID,
            pitchShift: parameters.pitchShift,
            rate: parameters.rate,
            emotionalIntensity: parameters.emotionalIntensity,
            breathiness: parameters.breathiness,
            ageShift: parameters.ageShift,
            genderShift: parameters.genderShift
        )
        try input.validate()
        return input
    }
}

/// Phrase-progressive synthesis pipeline; production real-time performance is
/// an unpassed device/model acceptance gate.
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
        priority: SynthesisExecutionPriority = .interactive,
        onChunk: @Sendable (AudioChunk) async throws -> Void
    ) async throws {
        try await streamSynthesisWithMetadata(
            input: .markup(text),
            voice: voice,
            parameters: parameters,
            priority: priority
        ) { delivery in
            try await onChunk(delivery.audio)
        }
    }

    /// Streams an explicitly selected input mode with timing updates.
    ///
    /// The linguistic and prosody stages describe the request globally, then
    /// each natural phrase unit is passed through the acoustic model and
    /// vocoder only when it is due. The first unit is delivered before model
    /// inference for later units begins; unlike the former implementation,
    /// this does not render the full request and slice it afterwards.
    public func streamSynthesisWithMetadata(
        input: SynthesisInput,
        voice: Voice,
        parameters: SynthesisParameters,
        priority: SynthesisExecutionPriority = .interactive,
        onChunk: @Sendable (SynthesisStreamChunk) async throws -> Void
    ) async throws {
        guard chunkSize > 0 else {
            throw ChoirError.invalidParameter(
                parameter: "chunkSize", reason: "Chunk size must be greater than zero")
        }

        try await SynthesisExecutor.run(priority: priority) {
            let prepared = try self.pipeline.prepare(
                input: input, voice: voice, parameters: parameters)
            try await self.stream(
                prepared: prepared,
                voice: voice,
                onChunk: onChunk)
        }
    }

    /// Streams fully specified phoneme/prosody input (TXT-050/STR-004).
    public func streamSynthesisWithMetadata(
        phonemeProsody: PhonemeProsodySequence,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters(),
        priority: SynthesisExecutionPriority = .interactive,
        onChunk: @Sendable (SynthesisStreamChunk) async throws -> Void
    ) async throws {
        guard chunkSize > 0 else {
            throw ChoirError.invalidParameter(
                parameter: "chunkSize", reason: "Chunk size must be greater than zero")
        }

        try await SynthesisExecutor.run(priority: priority) {
            let prepared = try self.pipeline.prepare(
                phonemeProsody: phonemeProsody,
                voice: voice,
                parameters: parameters)
            try await self.stream(
                prepared: prepared,
                voice: voice,
                onChunk: onChunk)
        }
    }

    private func stream(
        prepared: SynthesisPipeline.PreparedSynthesis,
        voice: Voice,
        onChunk: @Sendable (SynthesisStreamChunk) async throws -> Void
    ) async throws {
        let plannedMetadata = SynthesisPipeline.buildMetadata(
            transcript: prepared.transcript,
            durationsMs: prepared.prosody.phonemes.map(\.prosody.duration),
            audio: AudioBuffer(samples: [], format: pipeline.outputFormat),
            voice: voice,
            parameters: prepared.parameters,
            markup: prepared.markup)

        var emittedSamples = 0
        for (unitIndex, unit) in prepared.units.enumerated() {
            try Cancellation.check()
            let audio = try await pipeline.renderUnit(unit, from: prepared, voice: voice)
            guard !audio.samples.isEmpty else {
                throw ChoirError.synthesisError(
                    reason: "A streaming synthesis unit produced no audio")
            }

            let channels = audio.format.channels
            let samplesPerChunk = max(channels, (chunkSize / channels) * channels)
            let predictedStartMs = plannedMetadata.phonemes[unit.lowerBound].startMs
            let predictedEndMs = plannedMetadata.phonemes[unit.upperBound - 1].endMs
            let predictedDurationMs = max(
                Double.leastNonzeroMagnitude, predictedEndMs - predictedStartMs)
            let actualUnitStartMs = Double(emittedSamples)
                / Double(audio.format.sampleRate * channels) * 1000
            let actualUnitDurationMs = audio.duration * 1000
            let timingScale = actualUnitDurationMs / predictedDurationMs

            var localOffset = 0
            while localOffset < audio.samples.count {
                try Cancellation.check()
                let end = localOffset + min(
                    samplesPerChunk, audio.samples.count - localOffset)
                let samples = Array(audio.samples[localOffset..<end])
                let startSeconds = Double(emittedSamples)
                    / Double(audio.format.sampleRate * channels)
                let endSeconds = startSeconds
                    + Double(samples.count)
                        / Double(audio.format.sampleRate * channels)
                let isFinal = unitIndex == prepared.units.count - 1
                    && end == audio.samples.count
                let audioChunk = AudioChunk(
                    samples: samples,
                    isFinal: isFinal,
                    timestamp: startSeconds)
                let actualStartMs = startSeconds * 1000
                let actualEndMs = endSeconds * 1000
                let plannedStartMs = predictedStartMs
                    + (actualStartMs - actualUnitStartMs) / timingScale
                let plannedEndMs = min(
                    predictedEndMs,
                    predictedStartMs + (actualEndMs - actualUnitStartMs) / timingScale)
                let plannedTiming = Self.timingUpdate(
                    metadata: plannedMetadata,
                    startMs: plannedStartMs,
                    endMs: plannedEndMs,
                    includeEndBoundary: isFinal)
                let timing = Self.align(
                    plannedTiming,
                    predictedUnitStartMs: predictedStartMs,
                    actualUnitStartMs: actualUnitStartMs,
                    scale: timingScale,
                    actualStartMs: actualStartMs,
                    actualEndMs: actualEndMs)

                try await onChunk(SynthesisStreamChunk(
                    audio: audioChunk,
                    metadata: timing))

                emittedSamples += samples.count
                localOffset = end
            }
        }
    }

    private static func align(
        _ update: StreamingMetadataUpdate,
        predictedUnitStartMs: Double,
        actualUnitStartMs: Double,
        scale: Double,
        actualStartMs: Double,
        actualEndMs: Double
    ) -> StreamingMetadataUpdate {
        func time(_ predicted: Double) -> Double {
            actualUnitStartMs + (predicted - predictedUnitStartMs) * scale
        }
        func span(_ value: TimedSpan) -> TimedSpan {
            TimedSpan(
                content: value.content,
                startMs: time(value.startMs),
                endMs: time(value.endMs))
        }
        return StreamingMetadataUpdate(
            startMs: actualStartMs,
            endMs: actualEndMs,
            words: update.words.map(span),
            phonemes: update.phonemes.map(span),
            marks: update.marks.map {
                MarkPosition(name: $0.name, timeMs: time($0.timeMs))
            },
            completedSentenceCount: update.completedSentenceCount)
    }

    private static func timingUpdate(
        metadata: SynthesisMetadata,
        startMs: Double,
        endMs: Double,
        includeEndBoundary: Bool
    ) -> StreamingMetadataUpdate {
        func intersects(_ span: TimedSpan) -> Bool {
            span.endMs > startMs && span.startMs < endMs
        }
        let marks = metadata.marks.filter { mark in
            mark.timeMs >= startMs
                && (mark.timeMs < endMs || (includeEndBoundary && mark.timeMs <= endMs))
        }
        let completed = includeEndBoundary
            ? metadata.sentences.count
            : metadata.sentences.reduce(into: 0) { count, range in
                guard let lastWord = range.last,
                      metadata.words.indices.contains(lastWord) else { return }
                if metadata.words[lastWord].endMs <= endMs { count += 1 }
            }
        return StreamingMetadataUpdate(
            startMs: startMs,
            endMs: endMs,
            words: metadata.words.filter(intersects),
            phonemes: metadata.phonemes.filter(intersects),
            marks: marks,
            completedSentenceCount: completed)
    }
}

/// Runs expensive synthesis work as a structured child task at the caller's
/// requested priority. Structured ownership propagates cancellation and avoids
/// an untracked detached task outliving its request (CON-001/002/004).
private enum SynthesisExecutor {
    static func run<Value: Sendable>(
        priority: SynthesisExecutionPriority,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        do {
            try Cancellation.check()
            return try await withThrowingTaskGroup(of: Value.self) { group in
                group.addTask(priority: priority.taskPriority) {
                    try Cancellation.check()
                    return try await operation()
                }
                guard let value = try await group.next() else {
                    throw ChoirError.synthesisError(
                        reason: "The synthesis scheduler finished without a result")
                }
                return value
            }
        } catch is CancellationError {
            throw ChoirError.cancelled
        }
    }
}
