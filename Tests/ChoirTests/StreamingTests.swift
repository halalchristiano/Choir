import Testing
import Foundation
@testable import Choir

/// Helper actor for collecting and tracking chunks in streaming tests.
actor StreamingChunkCollector {
    private var chunks: [AudioChunk] = []
    private var chunkIndices: [Int] = []
    private var timestamps: [Double?] = []

    func addChunk(_ chunk: AudioChunk, at index: Int) {
        chunks.append(chunk)
        chunkIndices.append(index)
        timestamps.append(chunk.timestamp)
    }

    func getChunks() -> [AudioChunk] {
        chunks
    }

    func getChunkCount() -> Int {
        chunks.count
    }

    func getTotalSampleCount() -> Int {
        chunks.reduce(0) { $0 + $1.samples.count }
    }

    func getFinalChunkIndex() -> Int? {
        chunks.enumerated()
            .first(where: { $0.element.isFinal })
            .map { $0.offset }
    }

    func hasMultipleFinalChunks() -> Bool {
        chunks.filter { $0.isFinal }.count > 1
    }

    func getChunkSizes() -> [Int] {
        chunks.map { $0.samples.count }
    }

    func getTimestamps() -> [Double?] {
        timestamps
    }

    func isTimeStampMonotonic() -> Bool {
        var lastTimestamp: Double? = nil
        for timestamp in timestamps {
            if let ts = timestamp, let last = lastTimestamp {
                if ts < last {
                    return false
                }
            }
            lastTimestamp = timestamp
        }
        return true
    }
}

/// Helper actor for simulating slow consumer with backpressure.
actor SlowConsumer {
    private var chunks: [AudioChunk] = []
    private let delayMs: Int

    init(delayMs: Int = 10) {
        self.delayMs = delayMs
    }

    func processChunk(_ chunk: AudioChunk) async throws {
        try await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
        chunks.append(chunk)
    }

    func getProcessedChunks() -> [AudioChunk] {
        chunks
    }

    func getProcessedCount() -> Int {
        chunks.count
    }
}

@Suite("Streaming Edge Cases")
struct StreamingEdgeCaseTests {
    /// Test 1: Basic streaming
    /// Verify chunks are generated and isFinal flag works correctly
    @Test("Basic streaming generates chunks with correct final flag")
    func testBasicStreaming() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let collector = StreamingChunkCollector()
        var chunkIndex = 0

        try await engine.streamSynthesis(
            text: "Hello world",
            voice: .youngAdultFeminine,
            parameters: SynthesisParameters(),
            options: StreamingOptions(),
            onChunk: { chunk in
                await collector.addChunk(chunk, at: chunkIndex)
                chunkIndex += 1
            }
        )

        let chunks = await collector.getChunks()
        #expect(!chunks.isEmpty, "Should generate at least one chunk")
        #expect(chunks.count > 0)

        // Verify at least one chunk marked as final
        let hasFinalChunk = chunks.contains { $0.isFinal }
        #expect(hasFinalChunk, "Should have at least one chunk marked as final")

        // Verify last chunk is final
        #expect(chunks.last?.isFinal == true, "Last chunk should be marked as final")

        // Verify total audio content
        let totalSamples = await collector.getTotalSampleCount()
        #expect(totalSamples > 0, "Should have generated audio samples")
    }

    /// Test 2: Chunk ordering
    /// Verify chunks arrive in correct order with monotonically increasing timestamps
    @Test("Chunks arrive in correct order with proper timestamps")
    func testChunkOrdering() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let collector = StreamingChunkCollector()
        var chunkIndex = 0

        try await engine.streamSynthesis(
            text: "The quick brown fox jumps over the lazy dog",
            voice: .narratorMasculine,
            parameters: SynthesisParameters(),
            options: StreamingOptions(),
            onChunk: { chunk in
                await collector.addChunk(chunk, at: chunkIndex)
                chunkIndex += 1
            }
        )

        let chunks = await collector.getChunks()
        #expect(chunks.count > 1, "Should generate multiple chunks for longer text")

        // Verify chunk indices are in order (they should be since we're streaming sequentially)
        for (index, chunk) in chunks.enumerated() {
            if index < chunks.count - 1 {
                // All but last chunk should not be final
                #expect(!chunk.isFinal, "Only last chunk should be final")
            }
        }

        // Verify timestamps are monotonic (if provided)
        let isMonotonic = await collector.isTimeStampMonotonic()
        #expect(isMonotonic, "Timestamps should be monotonically increasing")
    }

    /// Test 3: Chunk size consistency
    /// Verify chunk sizes match requested size (except last chunk)
    @Test("Chunk sizes match requested size except for last chunk")
    func testChunkSizeConsistency() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let requestedChunkSize = 1200  // 25ms at 48kHz
        let collector = StreamingChunkCollector()
        var chunkIndex = 0

        try await engine.streamSynthesis(
            text: "Testing chunk size consistency with longer text to ensure multiple chunks",
            voice: .youngAdultMasculine,
            parameters: SynthesisParameters(),
            options: StreamingOptions(chunkSize: requestedChunkSize),
            onChunk: { chunk in
                await collector.addChunk(chunk, at: chunkIndex)
                chunkIndex += 1
            }
        )

        let chunks = await collector.getChunks()
        let sizes = await collector.getChunkSizes()

        #expect(chunks.count > 1, "Should generate multiple chunks with small chunk size")

        // Verify all chunks except the last match requested size
        for (index, size) in sizes.enumerated() {
            if index < sizes.count - 1 {
                // Non-final chunks should be exactly the requested size
                #expect(size == requestedChunkSize,
                    "Chunk \(index) size \(size) should match requested \(requestedChunkSize)")
            } else {
                // Last chunk can be smaller
                #expect(size <= requestedChunkSize,
                    "Last chunk size \(size) should not exceed requested \(requestedChunkSize)")
                #expect(size > 0, "Last chunk should contain at least one sample")
            }
        }
    }

    /// Test 4: Error handling during streaming
    /// Test that when callback throws, the streaming stops and error propagates
    @Test("Streaming stops when callback throws error")
    func testCallbackErrorPropagation() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let collector = StreamingChunkCollector()
        var chunkIndex = 0
        let maxChunksBeforeError = 2

        do {
            try await engine.streamSynthesis(
                text: "This should generate enough audio to test error handling",
                voice: .youngAdultFeminine,
                parameters: SynthesisParameters(),
                options: StreamingOptions(),
                onChunk: { chunk in
                    await collector.addChunk(chunk, at: chunkIndex)
                    chunkIndex += 1

                    // Throw error after collecting a few chunks
                    if chunkIndex > maxChunksBeforeError {
                        throw ChoirError.invalidParameter(parameter: "test", reason: "Simulated error")
                    }
                }
            )
            #expect(Bool(false), "Should throw error")
        } catch let error as ChoirError {
            // Expected
            let collectedCount = await collector.getChunkCount()
            #expect(collectedCount > 0, "Should have collected some chunks before error")
            #expect(collectedCount <= chunkIndex, "Should not have more chunks than attempted")
        }
    }

    /// Test 5: Pause/resume simulation
    /// Collect chunks in batches to simulate pause/resume behavior
    @Test("Streaming can be simulated with pause/resume pattern")
    func testPauseResumeSimulation() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let firstCollector = StreamingChunkCollector()
        let secondCollector = StreamingChunkCollector()

        // First "session" - partial stream
        var chunkIndex1 = 0
        var pauseAt = 3
        do {
            try await engine.streamSynthesis(
                text: "First part of the audio synthesis",
                voice: .narratorFeminine,
                parameters: SynthesisParameters(),
                options: StreamingOptions(),
                onChunk: { chunk in
                    if chunkIndex1 < pauseAt {
                        await firstCollector.addChunk(chunk, at: chunkIndex1)
                    } else {
                        throw ChoirError.invalidParameter(parameter: "test", reason: "Simulated pause")
                    }
                    chunkIndex1 += 1
                }
            )
        } catch is ChoirError {
            // Pause simulation
        }

        // Second "session" - continue with different text
        var chunkIndex2 = 0
        try await engine.streamSynthesis(
            text: "Second part continuing the synthesis",
            voice: .narratorFeminine,
            parameters: SynthesisParameters(),
            options: StreamingOptions(),
            onChunk: { chunk in
                await secondCollector.addChunk(chunk, at: chunkIndex2)
                chunkIndex2 += 1
            }
        )

        let firstChunks = await firstCollector.getChunks()
        let secondChunks = await secondCollector.getChunks()

        #expect(!firstChunks.isEmpty, "First stream should have collected chunks")
        #expect(!secondChunks.isEmpty, "Second stream should have collected chunks")
        #expect(firstChunks.count < chunkIndex1, "First stream should have paused")
        #expect(secondChunks.count > 0, "Second stream should have continued successfully")
    }

    /// Test 6: Large text streaming
    /// Synthesize large text (many KB) and verify all chunks are received
    @Test("Large text streaming receives all chunks")
    func testLargeTextStreaming() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        // Create large text input (approximately 3KB)
        let textChunk = "The synthesis engine can handle large amounts of text with multiple sentences. "
        let largeText = String(repeating: textChunk, count: 40)  // ~3200 characters

        let collector = StreamingChunkCollector()
        var chunkIndex = 0

        try await engine.streamSynthesis(
            text: largeText,
            voice: .youngAdultMasculine,
            parameters: SynthesisParameters(),
            options: StreamingOptions(chunkSize: 2400),
            onChunk: { chunk in
                await collector.addChunk(chunk, at: chunkIndex)
                chunkIndex += 1
            }
        )

        let chunks = await collector.getChunks()
        let totalSamples = await collector.getTotalSampleCount()

        // Large text should generate many chunks
        #expect(chunks.count > 5, "Large text should generate multiple chunks")
        #expect(totalSamples > 10000, "Large text should generate substantial audio")

        // Verify last chunk is marked final
        #expect(chunks.last?.isFinal == true, "Last chunk of large stream should be final")

        // Verify no multiple final chunks
        let finalCount = chunks.filter { $0.isFinal }.count
        #expect(finalCount == 1, "Should have exactly one final chunk")
    }

    /// Test 7: Empty text handling
    /// Verify that empty text is rejected before streaming starts
    @Test("Empty text is rejected before streaming")
    func testEmptyTextHandling() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let collector = StreamingChunkCollector()
        var chunkIndex = 0

        do {
            try await engine.streamSynthesis(
                text: "",  // Empty text
                voice: .youngAdultFeminine,
                parameters: SynthesisParameters(),
                options: StreamingOptions(),
                onChunk: { chunk in
                    await collector.addChunk(chunk, at: chunkIndex)
                    chunkIndex += 1
                }
            )
            #expect(Bool(false), "Should reject empty text")
        } catch let error as ChoirError {
            // Expected - should be invalidParameter error
            #expect(true, "Empty text should throw error")
        }

        let collectedCount = await collector.getChunkCount()
        #expect(collectedCount == 0, "No chunks should be generated for empty text")
    }

    /// Test 8: Parameter variations
    /// Test streaming with various parameter combinations
    @Test("Streaming works with different parameter configurations")
    func testParameterVariations() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let testCases = [
            (rate: 0.8, pitch: 0),
            (rate: 1.0, pitch: 5),
            (rate: 1.2, pitch: -3),
            (rate: 1.5, pitch: 10)
        ]

        for (rate, pitch) in testCases {
            let collector = StreamingChunkCollector()
            var chunkIndex = 0

            let params = SynthesisParameters(
                pitchShift: Float(pitch),
                rate: Float(rate)
            )

            try await engine.streamSynthesis(
                text: "Testing parameter variations",
                voice: .narratorMasculine,
                parameters: params,
                options: StreamingOptions(),
                onChunk: { chunk in
                    await collector.addChunk(chunk, at: chunkIndex)
                    chunkIndex += 1
                }
            )

            let chunks = await collector.getChunks()
            #expect(!chunks.isEmpty, "Should generate chunks with rate: \(rate), pitch: \(pitch)")
            #expect(chunks.last?.isFinal == true, "Last chunk should be final for all parameter combinations")
        }
    }

    /// Test 9: Very small chunk size
    /// Request minimal chunk size and verify streaming still works
    @Test("Very small chunk sizes are handled correctly")
    func testMinimumChunkSize() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let minimumChunkSize = 100  // Very small - approximately 2ms at 48kHz
        let collector = StreamingChunkCollector()
        var chunkIndex = 0

        try await engine.streamSynthesis(
            text: "Testing with very small chunks",
            voice: .youngAdultFeminine,
            parameters: SynthesisParameters(),
            options: StreamingOptions(chunkSize: minimumChunkSize),
            onChunk: { chunk in
                await collector.addChunk(chunk, at: chunkIndex)
                chunkIndex += 1
            }
        )

        let chunks = await collector.getChunks()
        #expect(chunks.count > 1, "Small chunk size should generate many chunks")

        let sizes = await collector.getChunkSizes()
        for (index, size) in sizes.enumerated() {
            if index < sizes.count - 1 {
                #expect(size <= minimumChunkSize,
                    "Non-final chunks should respect minimum chunk size")
            }
        }

        let totalSamples = await collector.getTotalSampleCount()
        #expect(totalSamples > 0, "Should still generate audio with small chunks")
    }

    /// Test 10: Backpressure handling
    /// Test streaming with a slow consumer that adds delay between chunks
    @Test("Streaming handles backpressure from slow consumer")
    func testBackpressureHandling() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let slowConsumer = SlowConsumer(delayMs: 5)  // 5ms delay per chunk
        var chunkIndex = 0

        try await engine.streamSynthesis(
            text: "Testing backpressure with delayed chunk processing",
            voice: .narratorFeminine,
            parameters: SynthesisParameters(),
            options: StreamingOptions(),
            onChunk: { chunk in
                try await slowConsumer.processChunk(chunk)
            }
        )

        let processedChunks = await slowConsumer.getProcessedChunks()
        #expect(!processedChunks.isEmpty, "Slow consumer should process all chunks")
        #expect(processedChunks.count > 1, "Should handle backpressure across multiple chunks")

        // Verify integrity despite slow processing
        let lastChunk = processedChunks.last
        #expect(lastChunk?.isFinal == true, "Final chunk should be processed correctly despite backpressure")

        let totalSamples = processedChunks.reduce(0) { $0 + $1.samples.count }
        #expect(totalSamples > 0, "All samples should be processed despite backpressure")
    }

    /// Test 11: Error recovery scenario
    /// Simulate a transient error in the callback and verify appropriate handling
    @Test("Streaming error handling with selective processing")
    func testErrorRecoveryScenario() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let collector = StreamingChunkCollector()
        var chunkIndex = 0
        var errorThrown = false

        do {
            try await engine.streamSynthesis(
                text: "Testing error handling in streaming callbacks",
                voice: .youngAdultMasculine,
                parameters: SynthesisParameters(),
                options: StreamingOptions(),
                onChunk: { chunk in
                    // Simulate error on specific chunk
                    if chunkIndex == 1 {
                        errorThrown = true
                        throw ChoirError.unknown("Simulated processing error")
                    }
                    await collector.addChunk(chunk, at: chunkIndex)
                    chunkIndex += 1
                }
            )
        } catch is ChoirError {
            // Error is expected
        }

        #expect(errorThrown, "Error should have been thrown")
        let collectedCount = await collector.getChunkCount()
        #expect(collectedCount >= 1, "Should have collected at least first chunk before error")
    }

    /// Test 12: Final chunk detection and stream termination
    /// Verify exactly one chunk has isFinal=true, and it's the last chunk
    @Test("Final chunk detection and proper stream termination")
    func testFinalChunkDetection() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let collector = StreamingChunkCollector()
        var chunkIndex = 0
        var callCountAfterFinal = 0

        try await engine.streamSynthesis(
            text: "Testing final chunk detection and termination",
            voice: .narratorFeminine,
            parameters: SynthesisParameters(),
            options: StreamingOptions(),
            onChunk: { chunk in
                await collector.addChunk(chunk, at: chunkIndex)

                // Track if we receive chunks after the final chunk
                if chunkIndex > 0 {
                    let previousChunks = await collector.getChunks()
                    if previousChunks.count > chunkIndex - 1 {
                        let previousChunk = previousChunks[chunkIndex - 1]
                        if previousChunk.isFinal {
                            callCountAfterFinal += 1
                        }
                    }
                }

                chunkIndex += 1
            }
        )

        let chunks = await collector.getChunks()
        #expect(!chunks.isEmpty, "Should have generated chunks")

        // Count final chunks
        let finalChunks = chunks.filter { $0.isFinal }
        #expect(finalChunks.count == 1, "Should have exactly one final chunk")

        // Verify final chunk is the last one
        let lastChunk = chunks.last
        #expect(lastChunk?.isFinal == true, "Last chunk must be marked as final")

        // Verify no chunks come after the final chunk
        if let finalIndex = await collector.getFinalChunkIndex() {
            #expect(finalIndex == chunks.count - 1, "Final chunk should be the last chunk")
        }

        // Verify final chunk timestamp is reasonable
        if let finalChunk = chunks.last, let timestamp = finalChunk.timestamp {
            #expect(timestamp >= 0, "Final chunk timestamp should be non-negative")
        }
    }

    /// Bonus Test: Multiple streaming sessions
    /// Verify engine can handle multiple sequential streaming operations
    @Test("Engine supports multiple sequential streaming sessions")
    func testMultipleStreamingSessions() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let texts = [
            "First synthesis session",
            "Second synthesis session with different voice",
            "Third session testing multiple calls"
        ]

        var allChunksCollected = 0

        for text in texts {
            let collector = StreamingChunkCollector()
            var chunkIndex = 0

            try await engine.streamSynthesis(
                text: text,
                voice: .youngAdultFeminine,
                parameters: SynthesisParameters(),
                options: StreamingOptions(),
                onChunk: { chunk in
                    await collector.addChunk(chunk, at: chunkIndex)
                    chunkIndex += 1
                }
            )

            let chunks = await collector.getChunks()
            #expect(!chunks.isEmpty, "Session should produce chunks: \(text)")
            #expect(chunks.last?.isFinal == true, "Each session should have final chunk")
            allChunksCollected += chunks.count
        }

        #expect(allChunksCollected > texts.count, "Should collect multiple chunks across sessions")
    }
}
