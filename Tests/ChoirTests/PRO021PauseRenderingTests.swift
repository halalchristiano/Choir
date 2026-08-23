import Foundation
import Testing
@testable import Choir

@Suite("SRS PRO-021 — sample-accurate explicit pauses")
struct PRO021PauseRenderingTests {
    @Test("Batch synthesis renders consecutive breaks once at frame accuracy")
    func batchPauseAccuracyAndNoDuplication() async throws {
        let engine = makeEngine(sampleRate: 8_000)
        try await engine.initialize()

        let result = try await engine.synthesizeWithMetadata(
            text: "Alpha<break time=\"125ms\"/><break time=\"75ms\"/>beta",
            voice: .isla,
            parameters: SynthesisParameters(seed: 21))

        #expect(result.metadata.words.count == 2)
        let gapMs = result.metadata.words[1].startMs - result.metadata.words[0].endMs
        #expect(abs(gapMs - 200) <= 0.125)
        #expect(longestZeroRun(in: result.audio.samples) == 1_600)
        #expect(result.audio.samples.filter { $0 == 0 }.count == 1_600)
        #expect(abs(result.metadata.totalDurationMs - result.audio.duration * 1_000) < 0.001)
    }

    @Test("Leading and trailing strength pauses shift the word timeline")
    func edgePauseTiming() async throws {
        let engine = makeEngine(sampleRate: 8_000)
        try await engine.initialize()

        let result = try await engine.synthesizeWithMetadata(
            text: "<break time=\"25ms\"/>Alpha<break strength=\"weak\"/>",
            voice: .isla,
            parameters: SynthesisParameters(seed: 22))

        let word = try #require(result.metadata.words.first)
        #expect(abs(word.startMs - 25) <= 0.125)
        #expect(abs((result.metadata.totalDurationMs - word.endMs) - 100) <= 0.125)
        #expect(result.audio.samples.prefix(200).allSatisfy { $0 == 0 })
        #expect(result.audio.samples.suffix(800).allSatisfy { $0 == 0 })
    }

    @Test("Seeded batch and progressive streaming include identical pause PCM")
    func batchAndStreamPauseParity() async throws {
        let engine = makeEngine(sampleRate: 8_000)
        let collector = PauseStreamCollector()
        let text = "Alpha<break time=\"137ms\"/>beta"
        let parameters = SynthesisParameters(seed: 23)
        try await engine.initialize()

        let batch = try await engine.synthesize(
            text: text, voice: .isla, parameters: parameters)
        try await engine.streamSynthesisWithMetadata(
            input: .markup(text),
            voice: .isla,
            parameters: parameters,
            options: StreamingOptions(chunkSize: 200, preloadModel: false)
        ) { delivery in
            await collector.append(delivery)
        }

        #expect(await collector.samples == batch.samples)
        #expect(await collector.hasSilenceOnlyChunk)
        #expect(await collector.finalChunkCount == 1)
        #expect(longestZeroRun(in: batch.samples) == 1_096)
    }

    @Test("Batch synthesis rejects a pause that exceeds its memory budget")
    func oversizedPauseFailsBeforeAllocation() async throws {
        let engine = makeEngine(sampleRate: 8_000)
        try await engine.initialize()

        await #expect(throws: ChoirError.outOfMemory) {
            try await engine.synthesize(
                text: "Alpha<break time=\"1000000000ms\"/>beta",
                voice: .isla,
                parameters: SynthesisParameters(seed: 24))
        }
    }

    private func makeEngine(sampleRate: Int) -> ChoirEngine {
        let format = AudioFormat(sampleRate: sampleRate)
        return ChoirEngine(
            audioFormat: format,
            pipeline: SynthesisPipeline(
                acousticModel: MockAcousticModel(),
                vocoder: NonzeroVocoder(),
                audioFormat: format))
    }

    private func longestZeroRun(in samples: [Int16]) -> Int {
        var longest = 0
        var current = 0
        for sample in samples {
            if sample == 0 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }
}

private struct NonzeroVocoder: VocoderProtocol {
    func synthesize(features: AcousticFeatures, sampleRate: Int) async throws -> [Int16] {
        let sampleCount = max(1, Int((features.duration * Double(sampleRate)).rounded()))
        return Array(repeating: 1_000, count: sampleCount)
    }
}

private actor PauseStreamCollector {
    private(set) var samples: [Int16] = []
    private(set) var hasSilenceOnlyChunk = false
    private(set) var finalChunkCount = 0

    func append(_ delivery: SynthesisStreamChunk) {
        samples.append(contentsOf: delivery.audio.samples)
        if !delivery.audio.samples.isEmpty,
           delivery.audio.samples.allSatisfy({ $0 == 0 }) {
            hasSilenceOnlyChunk = true
        }
        if delivery.isFinal { finalChunkCount += 1 }
    }
}
