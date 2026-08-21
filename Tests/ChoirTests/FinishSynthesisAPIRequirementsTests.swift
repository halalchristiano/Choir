import Foundation
import Testing
@testable import Choir

private actor SynthesisRequirementProbe {
    private(set) var inputs: [AcousticModelInput] = []
    private(set) var activeCalls = 0
    private(set) var maximumActiveCalls = 0

    func begin(_ input: AcousticModelInput) {
        inputs.append(input)
        activeCalls += 1
        maximumActiveCalls = max(maximumActiveCalls, activeCalls)
    }

    func finish() {
        activeCalls = max(0, activeCalls - 1)
    }

    func input(at index: Int) -> AcousticModelInput? {
        inputs.indices.contains(index) ? inputs[index] : nil
    }

    var callCount: Int { inputs.count }
    var peakConcurrency: Int { maximumActiveCalls }
}

private struct ProbedAcousticModel: AcousticModelProtocol {
    let probe: SynthesisRequirementProbe
    let delayNanoseconds: UInt64

    init(probe: SynthesisRequirementProbe, delayNanoseconds: UInt64 = 0) {
        self.probe = probe
        self.delayNanoseconds = delayNanoseconds
    }

    func predict(input: AcousticModelInput) async throws -> AcousticFeatures {
        try input.validate()
        await probe.begin(input)
        do {
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            let durationSeconds = input.durations.reduce(0, +) / 1000
            let frames = max(1, Int(ceil(durationSeconds * 50)))
            let result = AcousticFeatures(
                features: Array(
                    repeating: Array(repeating: Float(-1), count: 8),
                    count: frames),
                frameRate: 50)
            await probe.finish()
            return result
        } catch {
            await probe.finish()
            throw error
        }
    }
}

private actor StreamRequirementCollector {
    private(set) var deliveries: [SynthesisStreamChunk] = []
    private(set) var startedModelCallsAtFirstDelivery: Int?

    func append(_ delivery: SynthesisStreamChunk, startedModelCalls: Int) {
        if startedModelCallsAtFirstDelivery == nil {
            startedModelCallsAtFirstDelivery = startedModelCalls
        }
        deliveries.append(delivery)
    }

    var samples: [Int16] { deliveries.flatMap(\.audio.samples) }
}

@Suite("Finish synthesis and public API requirements")
struct FinishSynthesisAPIRequirementsTests {

    private func engine(
        probe: SynthesisRequirementProbe,
        delayNanoseconds: UInt64 = 0,
        maximumConcurrentJobs: Int = 2
    ) -> ChoirEngine {
        let pipeline = SynthesisPipeline(
            acousticModel: ProbedAcousticModel(
                probe: probe,
                delayNanoseconds: delayNanoseconds),
            vocoder: MockVocoder())
        return ChoirEngine(
            pipeline: pipeline,
            maximumConcurrentJobs: maximumConcurrentJobs)
    }

    @Test("TXT-050: engine phoneme input reaches model inference")
    func phonemeInputSynthesizes() async throws {
        let probe = SynthesisRequirementProbe()
        let engine = engine(probe: probe)
        try await engine.initialize()

        let phonemes = [Phoneme("h"), Phoneme("ɛ", stress: 1), Phoneme("l"), Phoneme("oʊ")]
        let result = try await engine.synthesize(
            input: .phonemes(phonemes),
            voice: .isla,
            parameters: SynthesisParameters(seed: 7))

        #expect(!result.audio.isEmpty)
        #expect(result.metadata.phonemes.map(\.content) == phonemes.map(\.symbol))
        #expect(result.metadata.words.count == 1)
        #expect(await probe.callCount == 1)
    }

    @Test("TXT-050: supplied durations and pitch targets are honored exactly")
    func suppliedPhonemeProsodyReachesModel() async throws {
        let probe = SynthesisRequirementProbe()
        let engine = engine(probe: probe)
        try await engine.initialize()

        let sequence = PhonemeProsodySequence(
            phonemes: [Phoneme("h"), Phoneme("ɛ"), Phoneme("l"), Phoneme("oʊ")],
            durationsMs: [25, 80, 35, 120],
            pitchTargetsHz: [0, 175, 0, 190],
            wordBoundaries: [0, 2],
            wordTexts: ["hel", "lo"])
        let result = try await engine.synthesize(
            phonemeProsody: sequence,
            voice: .maeve,
            parameters: SynthesisParameters(seed: 1))

        let input = await probe.input(at: 0)
        #expect(input?.durations == [25, 80, 35, 120])
        #expect(input?.fundamentalFrequency == [0, 175, 0, 190])
        #expect(result.metadata.phonemes.map(\.durationMs) == [25, 80, 35, 120])
        #expect(result.metadata.words.map(\.content) == ["hel", "lo"])
    }

    @Test("TXT-050: mismatched prosody tensors fail before inference")
    func invalidPhonemeProsodyIsTyped() async throws {
        let probe = SynthesisRequirementProbe()
        let engine = engine(probe: probe)
        try await engine.initialize()
        let invalid = PhonemeProsodySequence(
            phonemes: [Phoneme("h"), Phoneme("ə")],
            durationsMs: [50])

        do {
            _ = try await engine.synthesize(phonemeProsody: invalid, voice: .isla)
            Issue.record("expected invalidParameter")
        } catch let error as ChoirError {
            guard case .invalidParameter(let parameter, _) = error else {
                Issue.record("unexpected ChoirError: \(error)")
                return
            }
            #expect(parameter == "durationsMs")
        }
        #expect(await probe.callCount == 0)
    }

    @Test("TXT-050: explicit timing is partitioned within model limits")
    func explicitTimingPartitionsByDuration() throws {
        let phonemes = Array(repeating: Phoneme("ə"), count: 61)
        let transcript = PhoneticTranscription(
            phonemes: phonemes,
            originalText: "long explicit sequence",
            wordBoundaries: [0, 10, 20, 30, 40, 50, 60],
            wordTexts: ["a", "b", "c", "d", "e", "f", "g"])
        let durations = Array(repeating: 10_000.0, count: phonemes.count)

        let units = SynthesisPipeline.synthesisUnits(
            for: transcript,
            phonemeDurationsMs: durations)

        #expect(units == [0..<60, 60..<61])
        #expect(units.allSatisfy { range in
            range.count <= 512 && durations[range].reduce(0, +) <= 600_000
        })
    }

    @Test("SYN-005: multi-voice results retain sentences and marks")
    func multiVoiceMetadataIsComplete() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()
        let text = """
        <mark name="opening"/><voice id="\(Voice.garrick.identifier)">First sentence.</voice>
        <mark name="turn"/><voice id="\(Voice.lyra.identifier)">Second sentence.</voice>
        """

        let result = try await engine.synthesize(
            input: .markup(text),
            voice: .isla,
            parameters: SynthesisParameters(seed: 42))

        #expect(result.metadata.sentences.count == 2)
        #expect(result.metadata.marks.map(\.name) == ["opening", "turn"])
        #expect(result.metadata.marks.allSatisfy { $0.timeMs <= result.metadata.totalDurationMs })
        #expect(result.metadata.isStructurallyValid, "\(result.metadata.validationIssues)")
    }

    @Test("SYN-005: marks and sentences follow normalized front-end provenance")
    func normalizationAwareMetadata() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()
        let result = try await engine.synthesize(
            input: .markup(#"Dr. Smith paid $1,250 <mark name="paid"/> today. Next."#),
            voice: .isla,
            parameters: SynthesisParameters(seed: 9))

        let today = try #require(result.metadata.words.first {
            $0.content.lowercased().hasPrefix("today")
        })
        #expect(result.metadata.time(ofMark: "paid") == today.startMs)
        #expect(result.metadata.sentences.count == 2)
    }

    @Test("STR-001: first delivery precedes inference for later phrases")
    func streamingIsActuallyIncremental() async throws {
        let probe = SynthesisRequirementProbe()
        let engine = engine(probe: probe, delayNanoseconds: 10_000_000)
        let collector = StreamRequirementCollector()
        try await engine.initialize()

        try await engine.streamSynthesisWithMetadata(
            input: .markup("First sentence. Second sentence."),
            voice: .isla,
            parameters: SynthesisParameters(seed: 100),
            options: StreamingOptions(
                chunkSize: 1_000_000,
                preloadModel: false,
                priority: .interactive)
        ) { delivery in
            let started = await probe.callCount
            await collector.append(delivery, startedModelCalls: started)
        }

        let deliveries = await collector.deliveries
        #expect(await collector.startedModelCallsAtFirstDelivery == 1)
        #expect(await probe.callCount >= 2)
        #expect(deliveries.count >= 2)
        #expect(deliveries.filter(\.isFinal).count == 1)
        #expect(deliveries.last?.isFinal == true)
        #expect(deliveries.allSatisfy { !$0.audio.samples.isEmpty })
        #expect(deliveries.contains { !$0.metadata.words.isEmpty })
        for (left, right) in zip(deliveries, deliveries.dropFirst()) {
            #expect(left.metadata.endMs <= right.metadata.endMs)
            #expect((left.audio.timestamp ?? 0) <= (right.audio.timestamp ?? 0))
        }
    }

    @Test("SYN-004/STR-002: seeded batch and stream are sample-identical")
    func seededBatchAndStreamMatch() async throws {
        let engine = ChoirEngine()
        let collector = StreamRequirementCollector()
        let text = "First sentence. Second sentence. Third sentence."
        let parameters = SynthesisParameters(seed: 0xC401)
        try await engine.initialize()

        let batch = try await engine.synthesize(
            text: text,
            voice: .isla,
            parameters: parameters)
        try await engine.streamSynthesisWithMetadata(
            input: .markup(text),
            voice: .isla,
            parameters: parameters,
            options: StreamingOptions(chunkSize: 997, preloadModel: false)
        ) { delivery in
            await collector.append(delivery, startedModelCalls: 0)
        }

        #expect(await collector.samples == batch.samples)
    }

    @Test("SYN-006: one engine runs at least two jobs concurrently")
    func concurrentJobsOverlap() async throws {
        let probe = SynthesisRequirementProbe()
        let engine = engine(
            probe: probe,
            delayNanoseconds: 50_000_000,
            maximumConcurrentJobs: 2)
        try await engine.initialize()

        async let first = engine.synthesize(
            text: "First independent request.",
            voice: .isla,
            parameters: SynthesisParameters(seed: 1))
        async let second = engine.synthesize(
            text: "Second independent request.",
            voice: .maeve,
            parameters: SynthesisParameters(seed: 2))
        let results = try await (first, second)

        #expect(!results.0.isEmpty)
        #expect(!results.1.isEmpty)
        #expect(await probe.peakConcurrency >= 2)
        #expect(await engine.getState() == .ready)
    }

    @Test("SYN-009: warm-up performs model work once ahead of synthesis")
    func warmUpIsExplicitAndIdempotent() async throws {
        let probe = SynthesisRequirementProbe()
        let engine = engine(probe: probe)

        try await engine.warmUp(voice: .isla)
        #expect(await engine.isWarmedUp())
        #expect(await probe.callCount == 1)

        try await engine.warmUp(voice: .maeve)
        #expect(await probe.callCount == 1, "idempotent warm-up reran inference")
    }

    @Test("SYN-009: concurrent warm-up callers share one model pass")
    func concurrentWarmUpsCoalesce() async throws {
        let probe = SynthesisRequirementProbe()
        let engine = engine(probe: probe, delayNanoseconds: 30_000_000)

        async let first: Void = engine.warmUp(voice: .isla)
        async let second: Void = engine.warmUp(voice: .maeve)
        _ = try await (first, second)

        #expect(await probe.callCount == 1)
        #expect(await engine.isWarmedUp())
    }

    @Test("API-001: standard request returns complete result and async export")
    func standardRequestAndExport() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()
        let request = SynthesisRequest(
            text: "One standard request.",
            voice: .garrick,
            parameters: SynthesisParameters(seed: 11),
            priority: .standard)

        let result = try await engine.synthesize(request)
        let output = try await result.exported(as: .wav)

        #expect(!result.audio.isEmpty)
        #expect(!result.metadata.words.isEmpty)
        #expect(result.metadata.isStructurallyValid)
        #expect(output.kind == .wav)
        #expect(output.byteSize > result.audio.byteCount)
    }

    @Test("API-004: constructor clamp reports survive the engine boundary")
    func constructorClampReportSurvivesSynthesis() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()
        let result = try await engine.synthesize(
            input: .plainText("Clamp report."),
            voice: .isla,
            parameters: SynthesisParameters(pitchShift: 100, seed: 1))

        #expect(result.metadata.effectiveParameters.pitchShift == 6)
        #expect(result.metadata.effectiveParameters.clampings.contains {
            $0.parameter == "pitchShift" && $0.requested == 100 && $0.applied == 6
        })
    }

    @Test("API-001/STR-004: expert AsyncSequence yields timed chunks")
    func expertAsyncSequence() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()
        let request = SynthesisRequest(
            input: .markup(#"Alpha. <mark name="middle"/> Beta."#),
            voice: .lyra,
            parameters: SynthesisParameters(seed: 22),
            priority: .interactive)
        var deliveries: [SynthesisStreamChunk] = []

        for try await delivery in engine.stream(
            request,
            options: StreamingOptions(chunkSize: 1200, preloadModel: false)) {
            deliveries.append(delivery)
        }

        #expect(!deliveries.isEmpty)
        #expect(deliveries.last?.isFinal == true)
        #expect(deliveries.flatMap(\.metadata.words).isEmpty == false)
        #expect(deliveries.flatMap(\.metadata.phonemes).isEmpty == false)
        #expect(deliveries.flatMap(\.metadata.marks).map(\.name).contains("middle"))
    }

    @Test("API-006: compatibility stream remains lossless for a slow consumer")
    func compatibilityStreamPreservesBufferedPCM() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()
        let request = SynthesisRequest(
            text: "Compatibility delivery must not discard any generated samples.",
            voice: .lyra,
            parameters: SynthesisParameters(seed: 23))
        let batch = try await engine.synthesize(request)
        let stream = engine.stream(
            request,
            options: StreamingOptions(chunkSize: 16, preloadModel: false))

        // Let the bridge get well beyond the bounded streamChunks capacity
        // before this consumer starts pulling.
        try await Task.sleep(nanoseconds: 20_000_000)
        var streamed: [Int16] = []
        for try await delivery in stream {
            streamed.append(contentsOf: delivery.audio.samples)
        }

        #expect(streamed == batch.audio.samples)
    }

    @Test("STR-005: ending pull iteration cancels producer and releases permit")
    func earlySequenceExitReleasesEngine() async throws {
        let probe = SynthesisRequirementProbe()
        let engine = engine(probe: probe, delayNanoseconds: 20_000_000)
        try await engine.initialize()
        let request = SynthesisRequest(
            text: Array(repeating: "A sentence.", count: 20).joined(separator: " "),
            voice: .isla,
            parameters: SynthesisParameters(seed: 33))

        var iterator: SynthesisChunkStream.Iterator? = engine.streamChunks(
            request,
            options: StreamingOptions(chunkSize: 1_000_000, preloadModel: false)
        ).makeAsyncIterator()
        let first = try await iterator?.next()
        #expect(first != nil)
        iterator = nil

        for _ in 0..<100 {
            if await engine.getState() == .ready { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(await engine.getState() == .ready)
        #expect(await probe.callCount < 20)
    }

    @Test("STR-006: quantized gaps and markup keep one monotonic dialogue timeline")
    func dialogueTimelineUsesDeliveredProgress() async throws {
        let engine = ChoirEngine(audioFormat: AudioFormat(sampleRate: 8_000))
        try await engine.initialize()
        let queue = DialogueQueue([
            DialogueUtterance(
                text: #"<voice id="choir.eld.female.maeve">One.</voice>"#,
                voice: .isla,
                parameters: SynthesisParameters(seed: 1),
                gapAfterMs: 0.001),
            DialogueUtterance(
                text: "Two.",
                voice: .lyra,
                parameters: SynthesisParameters(seed: 2)),
        ])
        let collector = StreamRequirementCollector()

        try await engine.streamDialogue(
            queue,
            options: StreamingOptions(chunkSize: 1_000_000, preloadModel: false)
        ) { delivery in
            await collector.append(delivery, startedModelCalls: 0)
        }

        let deliveries = await collector.deliveries
        for (left, right) in zip(deliveries, deliveries.dropFirst()) {
            #expect(left.metadata.endMs <= right.metadata.startMs)
            #expect((left.audio.timestamp ?? 0) <= (right.audio.timestamp ?? 0))
        }
        #expect(deliveries.last?.metadata.completedSentenceCount == 2)
        #expect(deliveries.last?.isFinal == true)
    }

    @Test("CON-004/PRO-001/002/VOX-P-007: public controls match SRS envelopes")
    func publicPriorityAndParameterEnvelopes() {
        let values = SynthesisParameters(
            pitchShift: 100,
            rate: 0,
            ageShift: -100)
        #expect(values.pitchShift == 6)
        #expect(values.rate == 0.6)
        #expect(values.ageShift == -1)
        #expect(values.wasClamped)
        #expect(SynthesisExecutionPriority.allCases.count == 5)
        #expect(StreamingOptions().priority == .interactive)
    }

    @Test("API-004/ML-A-002: request boundary revalidates mutable controls and conditions model")
    func mutatedControlsAreRevalidatedAndConditioned() async throws {
        let probe = SynthesisRequirementProbe()
        let engine = engine(probe: probe)
        try await engine.initialize()
        var parameters = SynthesisParameters(seed: 44)
        parameters.pitchShift = 100
        parameters.rate = 0
        parameters.emotionalIntensity = 2
        parameters.breathiness = -1
        parameters.ageShift = 9
        parameters.genderShift = -9

        let result = try await engine.synthesize(
            input: .plainText("Validated request."),
            voice: .isla,
            parameters: parameters)
        let input = await probe.input(at: 0)

        #expect(result.metadata.effectiveParameters.pitchShift == 6)
        #expect(result.metadata.effectiveParameters.rate == 0.6)
        #expect(result.metadata.effectiveParameters.clampings.count == 6)
        #expect(input?.pitchShift == 6)
        #expect(input?.rate == 0.6)
        #expect(input?.emotionalIntensity == 1)
        #expect(input?.breathiness == 0)
        #expect(input?.ageShift == 1)
        #expect(input?.genderShift == -1)
    }

    @Test("REL-002: batch accumulation is checked before allocation")
    func batchAccumulationHasDeterministicMemoryLimit() throws {
        #expect(try SynthesisPipeline.validatedCombinedSampleCount(
            currentCount: 100, newCount: 200) == 300)
        #expect(throws: ChoirError.outOfMemory) {
            try SynthesisPipeline.validatedCombinedSampleCount(
                currentCount: SynthesisPipeline.maximumAccumulatedSamples,
                newCount: 1)
        }
        #expect(throws: ChoirError.outOfMemory) {
            try SynthesisPipeline.validatedCombinedSampleCount(
                currentCount: Int.max,
                newCount: 1)
        }
    }
}
