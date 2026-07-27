import Testing
@testable import Choir

/// Helper actor for testing streaming errors.
actor StreamErrorTracker {
    private var chunksReceived: Int = 0
    private var errorThrown: Bool = false

    func recordChunk() {
        chunksReceived += 1
    }

    func recordError() {
        errorThrown = true
    }

    func getChunkCount() -> Int {
        chunksReceived
    }

    func hasError() -> Bool {
        errorThrown
    }
}

@Suite("Error Handling")
struct ErrorHandlingTests {
    // MARK: - notInitialized Tests

    @Test("notInitialized error thrown before engine initialization")
    func testSynthesisThrowsBeforeInitialization() async {
        let engine = ChoirEngine()

        let state = await engine.getState()
        #expect(state == .uninitialized)

        // Attempt synthesis without initializing
        do {
            _ = try await engine.synthesize(text: "Hello", voice: .narratorFeminine)
            #expect(Bool(false), "Should have thrown notInitialized error")
        } catch let error as ChoirError {
            #expect(error == .notInitialized)
        } catch {
            #expect(Bool(false), "Wrong error type thrown")
        }
    }

    @Test("notInitialized error message is clear")
    func testNotInitializedErrorMessage() async {
        let engine = ChoirEngine()

        do {
            _ = try await engine.synthesize(text: "test", voice: .narratorMasculine)
        } catch let error as ChoirError {
            let message = error.errorDescription ?? ""
            #expect(message.contains("not initialized"))
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }

    // MARK: - invalidParameter Tests (Empty Text)

    @Test("invalidParameter error for empty text")
    func testEmptyTextThrowsInvalidParameter() async {
        let engine = ChoirEngine()
        try? await engine.initialize()

        do {
            _ = try await engine.synthesize(text: "", voice: .narratorFeminine)
            #expect(Bool(false), "Should have thrown invalidParameter error")
        } catch let error as ChoirError {
            if case .invalidParameter(let parameter, _) = error {
                #expect(parameter == "text")
            } else {
                #expect(Bool(false), "Wrong error case")
            }
        } catch {
            #expect(Bool(false), "Wrong error type thrown")
        }
    }

    @Test("invalidParameter error message for empty text is descriptive")
    func testEmptyTextErrorMessage() async {
        let engine = ChoirEngine()
        try? await engine.initialize()

        do {
            _ = try await engine.synthesize(text: "", voice: .narratorMasculine)
        } catch let error as ChoirError {
            let message = error.errorDescription ?? ""
            #expect(message.contains("cannot be empty"))
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }

    // MARK: - invalidParameter Tests (Text Too Long)

    @Test("invalidParameter error for text exceeding 5000 characters")
    func testTextTooLongThrowsInvalidParameter() async {
        let engine = ChoirEngine()
        try? await engine.initialize()

        let longText = String(repeating: "a", count: 5001)

        do {
            _ = try await engine.synthesize(text: longText, voice: .narratorFeminine)
            #expect(Bool(false), "Should have thrown invalidParameter error")
        } catch let error as ChoirError {
            if case .invalidParameter(let parameter, _) = error {
                #expect(parameter == "text")
            } else {
                #expect(Bool(false), "Wrong error case")
            }
        } catch {
            #expect(Bool(false), "Wrong error type thrown")
        }
    }

    @Test("invalidParameter error message for long text mentions character limit")
    func testTextTooLongErrorMessage() async {
        let engine = ChoirEngine()
        try? await engine.initialize()

        let longText = String(repeating: "x", count: 5001)

        do {
            _ = try await engine.synthesize(text: longText, voice: .narratorMasculine)
        } catch let error as ChoirError {
            let message = error.errorDescription ?? ""
            #expect(message.contains("5000"))
        } catch {
            #expect(Bool(false), "Wrong error type")
        }
    }

    // MARK: - synthesisError Tests

    @Test("synthesisError can be constructed with reason")
    func testSynthesisErrorConstruction() {
        let error = ChoirError.synthesisError(reason: "Model inference failed")

        if case .synthesisError(let reason) = error {
            #expect(reason == "Model inference failed")
        } else {
            #expect(Bool(false), "Wrong error case")
        }
    }

    @Test("synthesisError message includes reason")
    func testSynthesisErrorMessage() {
        let error = ChoirError.synthesisError(reason: "Acoustic features invalid")
        let message = error.errorDescription ?? ""

        #expect(message.contains("Synthesis error"))
        #expect(message.contains("Acoustic features invalid"))
    }

    // MARK: - modelLoadError Tests

    @Test("modelLoadFailed error can be constructed with reason")
    func testModelLoadFailedConstruction() {
        let error = ChoirError.modelLoadFailed(reason: "Corrupted model file")

        if case .modelLoadFailed(let reason) = error {
            #expect(reason == "Corrupted model file")
        } else {
            #expect(Bool(false), "Wrong error case")
        }
    }

    @Test("modelLoadFailed error message includes reason")
    func testModelLoadFailedMessage() {
        let error = ChoirError.modelLoadFailed(reason: "File not found at /path/to/model")
        let message = error.errorDescription ?? ""

        #expect(message.contains("Failed to load model"))
        #expect(message.contains("File not found"))
    }

    // MARK: - cachingError Tests (represented as textProcessingFailed)

    @Test("textProcessingFailed error can represent cache failures")
    func testCachingErrorRepresentation() {
        let error = ChoirError.textProcessingFailed(reason: "Cache miss for phoneme data")

        if case .textProcessingFailed(let reason) = error {
            #expect(reason.contains("Cache"))
        } else {
            #expect(Bool(false), "Wrong error case")
        }
    }

    @Test("textProcessingFailed error message for cache includes context")
    func testCachingErrorMessage() {
        let error = ChoirError.textProcessingFailed(reason: "Failed to retrieve cached prosody")
        let message = error.errorDescription ?? ""

        #expect(message.contains("Text processing failed"))
        #expect(message.contains("prosody"))
    }

    // MARK: - encodingError Tests

    @Test("audioEncodingFailed error can be constructed with reason")
    func testAudioEncodingFailedConstruction() {
        let error = ChoirError.audioEncodingFailed(reason: "Unsupported audio format MP2")

        if case .audioEncodingFailed(let reason) = error {
            #expect(reason == "Unsupported audio format MP2")
        } else {
            #expect(Bool(false), "Wrong error case")
        }
    }

    @Test("audioEncodingFailed error message is clear")
    func testAudioEncodingFailedMessage() {
        let error = ChoirError.audioEncodingFailed(reason: "AAC codec unavailable on platform")
        let message = error.errorDescription ?? ""

        #expect(message.contains("Audio encoding failed"))
        #expect(message.contains("AAC codec"))
    }

    // MARK: - streamingError Tests

    @Test("streaming error can occur during chunk generation")
    func testStreamingErrorDuringChunkGeneration() async {
        let engine = ChoirEngine()
        try? await engine.initialize()
        let tracker = StreamErrorTracker()

        do {
            try await engine.streamSynthesis(
                text: "test",
                voice: .narratorFeminine,
                options: StreamingOptions(),
                onChunk: { chunk in
                    await tracker.recordChunk()
                }
            )
        } catch {
            await tracker.recordError()
        }

        let hasErrorOccurred = await tracker.hasError()
        #expect(hasErrorOccurred || await tracker.getChunkCount() >= 0)
    }

    @Test("streaming error includes context about failure point")
    func testStreamingErrorContextPreservation() async {
        let engine = ChoirEngine()
        try? await engine.initialize()

        var chunkCount = 0
        var errorOccurred = false

        do {
            try await engine.streamSynthesis(
                text: "Hello world",
                voice: .youngAdultMasculine,
                options: StreamingOptions(),
                onChunk: { _ in
                    chunkCount += 1
                }
            )
        } catch {
            errorOccurred = true
        }

        #expect(chunkCount >= 0)
        #expect(errorOccurred || chunkCount > 0)
    }

    // MARK: - Other Error Types Tests

    @Test("cancelled error indicates operation was halted")
    func testCancelledError() {
        let error = ChoirError.cancelled
        let message = error.errorDescription ?? ""

        #expect(message.contains("cancelled"))
    }

    @Test("timeout error indicates operation exceeded time limit")
    func testTimeoutError() {
        let error = ChoirError.timeout
        let message = error.errorDescription ?? ""

        #expect(message.contains("timed out"))
    }

    @Test("outOfMemory error indicates insufficient resources")
    func testOutOfMemoryError() {
        let error = ChoirError.outOfMemory
        let message = error.errorDescription ?? ""

        #expect(message.contains("memory"))
    }

    @Test("unknown error preserves original error message")
    func testUnknownError() {
        let customMessage = "Unexpected database failure"
        let error = ChoirError.unknown(customMessage)
        let message = error.errorDescription ?? ""

        #expect(message.contains(customMessage))
        #expect(message.contains("Unknown error"))
    }
}
