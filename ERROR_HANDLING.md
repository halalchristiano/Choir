# Error Handling in CHOIR

CHOIR uses typed errors to help you handle synthesis failures gracefully.

## The ChoirError Type

All CHOIR functions throw `ChoirError` which has specific cases for each failure:

```swift
do {
    try await engine.synthesize(text: "...", voice: .narratorFeminine)
} catch let error as ChoirError {
    // Handle specific error types
    switch error {
    case .notInitialized:
        // Model not loaded
    case .invalidInput(let reason):
        // Bad text or parameters
    case .synthesisError(let reason):
        // Synthesis failed mid-process
    // ... more cases below
    }
} catch {
    // Non-CHOIR errors (unlikely)
}
```

## Error Cases & Recovery

### 1. `.notInitialized`
**Cause:** You called synthesis before loading models.

**Recovery:**
```swift
do {
    try await engine.initialize()  // Load models first
    let audio = try await engine.synthesize(text: "Hello", voice: .narratorFeminine)
} catch ChoirError.notInitialized {
    print("Models loading, please retry...")
}
```

### 2. `.invalidInput(let reason)`
**Cause:** Bad parameters or empty text.

**Recovery:**
```swift
do {
    let audio = try await engine.synthesize(text: userInput, voice: selectedVoice)
} catch ChoirError.invalidInput(let reason) {
    print("Invalid input: \(reason)")
    // Validate: text.count > 0, valid voice, etc.
}
```

**Prevention:**
```swift
guard !text.isEmpty else { return }
guard !text.count > 5000 else { print("Text too long"); return }
```

### 3. `.synthesisError(let reason)`
**Cause:** Model inference or vocoding failed.

**Recovery:**
```swift
do {
    let audio = try await engine.synthesize(text: text, voice: voice)
} catch ChoirError.synthesisError(let reason) {
    print("Synthesis failed: \(reason)")
    // Retry with shorter text or different voice
    let shortText = String(text.prefix(500))
    let audio = try await engine.synthesize(text: shortText, voice: .narratorFeminine)
}
```

### 4. `.modelLoadError(let reason)`
**Cause:** Failed to load voice models from disk.

**Recovery:**
```swift
do {
    try await engine.initialize()
} catch ChoirError.modelLoadError(let reason) {
    print("Model loading failed: \(reason)")
    // Check available disk space
    // Retry initialization
    try await Task.sleep(nanoseconds: 1_000_000_000)  // Wait 1 second
    try await engine.initialize()
}
```

### 5. `.cachingError(let reason)`
**Cause:** Asset cache failed to store/retrieve audio.

**Recovery:**
```swift
do {
    let audio = try await engine.synthesize(text: text, voice: voice)
} catch ChoirError.cachingError(let reason) {
    print("Cache error: \(reason)")
    // Continue without caching
    // The audio is still available, just not cached
}
```

### 6. `.encodingError(let reason)`
**Cause:** WAV encoding or audio format conversion failed.

**Recovery:**
```swift
do {
    let audio = try await engine.synthesize(text: "...", voice: .narratorFeminine)
    let wavData = try audio.encodeWAV()
} catch ChoirError.encodingError(let reason) {
    print("Encoding failed: \(reason)")
    // Save raw PCM instead
    let rawData = audio.audioBuffer.data()
    try rawData.write(to: rawURL)
}
```

### 7. `.streamingError(let reason)`
**Cause:** Chunk generation or streaming callback failed.

**Recovery:**
```swift
do {
    try await engine.streamSynthesis(
        text: text,
        voice: voice,
        onChunk: { chunk in
            do {
                audioPlayer.enqueue(chunk.samples)
            } catch {
                print("Failed to enqueue chunk: \(error)")
            }
        }
    )
} catch ChoirError.streamingError(let reason) {
    print("Streaming failed: \(reason)")
    // Fallback to batch synthesis
    let audio = try await engine.synthesize(text: text, voice: voice)
    audioPlayer.play(audio)
}
```

## Common Patterns

### Retry with Backoff

```swift
func synthesizeWithRetry(
    text: String,
    voice: Voice,
    maxAttempts: Int = 3
) async throws -> SynthesisResult {
    var lastError: ChoirError?
    
    for attempt in 1...maxAttempts {
        do {
            return try await engine.synthesize(text: text, voice: voice)
        } catch let error as ChoirError {
            lastError = error
            
            // Exponential backoff: 1s, 2s, 4s
            let delayNs = UInt64(1_000_000_000 * (1 << (attempt - 1)))
            try await Task.sleep(nanoseconds: delayNs)
        }
    }
    
    throw lastError ?? ChoirError.synthesisError("Unknown error after retries")
}
```

### Fallback Voices

```swift
func synthesizeWithFallback(
    text: String,
    voice: Voice
) async throws -> SynthesisResult {
    let fallbackVoices = [voice, .narratorFeminine, .narratorMasculine]
    
    for fallback in fallbackVoices {
        do {
            return try await engine.synthesize(text: text, voice: fallback)
        } catch {
            print("Failed with \(fallback), trying next...")
        }
    }
    
    throw ChoirError.synthesisError("All voices failed")
}
```

### Graceful Degradation

```swift
func synthesizeOrUsePrerecorded(
    text: String,
    voice: Voice,
    prerecordedURL: URL?
) async throws -> SynthesisResult {
    do {
        return try await engine.synthesize(text: text, voice: voice)
    } catch {
        if let prerecordedURL = prerecordedURL {
            print("Using prerecorded audio fallback")
            return try SynthesisResult(audioURL: prerecordedURL)
        }
        throw error
    }
}
```

### Logging & Debugging

```swift
func synthesizeWithLogging(text: String, voice: Voice) async throws -> SynthesisResult {
    do {
        let result = try await engine.synthesize(text: text, voice: voice)
        print("✅ Synthesis succeeded: \(text.count) chars, voice=\(voice)")
        return result
    } catch let error as ChoirError {
        switch error {
        case .notInitialized:
            print("❌ Engine not initialized")
        case .invalidInput(let reason):
            print("⚠️ Invalid input: \(reason)")
        case .synthesisError(let reason):
            print("❌ Synthesis error: \(reason)")
        case .modelLoadError(let reason):
            print("❌ Model load error: \(reason)")
        case .cachingError(let reason):
            print("⚠️ Cache error (non-fatal): \(reason)")
        case .encodingError(let reason):
            print("⚠️ Encoding error: \(reason)")
        case .streamingError(let reason):
            print("❌ Streaming error: \(reason)")
        }
        throw error
    }
}
```

## Performance & Timeout Handling

### Detecting Slow Synthesis

```swift
func synthesizeWithTimeout(
    text: String,
    voice: Voice,
    timeoutSeconds: TimeInterval = 30.0
) async throws -> SynthesisResult {
    try await withThrowingTaskGroup(of: SynthesisResult.self) { group in
        group.addTask {
            try await engine.synthesize(text: text, voice: voice)
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            throw ChoirError.synthesisError("Synthesis timeout")
        }
        
        return try await group.next()!
    }
}
```

## Testing Error Paths

```swift
import Testing
@testable import Choir

@Suite("Error Handling")
struct ErrorHandlingTests {
    @Test("Catches not initialized error")
    async func testNotInitialized() {
        let engine = ChoirEngine()  // Don't initialize
        
        await #expect(throws: ChoirError.self) {
            try await engine.synthesize(text: "Hi", voice: .narratorFeminine)
        }
    }
    
    @Test("Handles empty text")
    async func testEmptyText() {
        let engine = ChoirEngine()
        try await engine.initialize()
        
        await #expect(throws: ChoirError.invalidInput.self) {
            try await engine.synthesize(text: "", voice: .narratorFeminine)
        }
    }
}
```

## Key Takeaways

1. **Always call `initialize()`** before synthesis
2. **Validate input** before attempting synthesis
3. **Use specific error cases** for targeted recovery
4. **Implement retries** for transient failures
5. **Test error paths** in your test suite
6. **Provide fallbacks** for critical features
7. **Log errors** for debugging

---

See also: [Getting Started](./GETTING_STARTED.md), [Streaming Guide](./STREAMING.md), [Architecture](./ARCHITECTURE.md)
