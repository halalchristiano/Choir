# Streaming Synthesis Guide

For responsive, real-time speech synthesis, CHOIR's streaming mode generates audio in chunks as they're produced—perfect for interactive apps, games, and voice-driven interfaces.

## Streaming vs. Batch

| Aspect | Streaming | Batch |
|--------|-----------|-------|
| **Time to first audio** | ~50ms | 500ms+ |
| **Memory peak** | Low (buffered chunks) | High (full audio) |
| **Best for** | Interactive, long-form | Short utterances, offline |
| **Responsiveness** | High | Low |
| **Quality** | Equal | Equal |

## Basic Streaming

```swift
try await engine.streamSynthesis(
    text: "This audio streams as it's generated...",
    voice: .narratorFeminine,
    onChunk: { chunk in
        // Each chunk is 2400 samples (~50ms at 48kHz)
        print("Got chunk: \(chunk.samples.count) samples")
        print("Is final: \(chunk.isFinal)")
        
        // Enqueue for playback
        audioPlayer.enqueue(chunk.samples)
    }
)
```

## Chunk Management

### Understanding Chunks

```swift
public struct AudioChunk: Sendable {
    /// PCM samples in this chunk (1-4800 samples, ~25-100ms at 48kHz)
    public let samples: [Int16]
    
    /// Whether this is the last chunk
    public let isFinal: Bool
    
    /// Chunk index (0-based)
    public let index: Int
}
```

### Chunk Size Options

```swift
// Default: 2400 samples (~50ms)
try await engine.streamSynthesis(text: "...", voice: voice, onChunk: handler)

// Custom chunk size via StreamingOptions
try await engine.streamSynthesis(
    text: "...",
    voice: voice,
    streamingOptions: StreamingOptions(chunkSize: 1200),  // ~25ms, higher CPU
    onChunk: handler
)
```

**Size Recommendations:**

- **512 samples (~10ms)**: Lowest latency, high CPU overhead, best for competitive games
- **1200 samples (~25ms)**: Low latency, moderate CPU, good for real-time apps
- **2400 samples (~50ms)**: Balanced (default), recommended for most apps
- **4800 samples (~100ms)**: High efficiency, acceptable latency for narrative

## Real-Time Playback

### Pattern 1: Simple Audio Player

```swift
import AVFoundation

class RealTimeAudioPlayer {
    private let audioEngine = AVAudioEngine()
    private var playerNode: AVAudioPlayerNode?
    
    func playStreamed(text: String, voice: Voice) async throws {
        // Setup audio engine
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        try audioEngine.start()
        
        try await engine.streamSynthesis(
            text: text,
            voice: voice,
            onChunk: { [weak self] chunk in
                // Convert Int16 to AVAudioPCMBuffer
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(chunk.samples.count))!
                buffer.frameLength = UInt32(chunk.samples.count)
                let floatChannelData = buffer.floatChannelData![0]
                
                // Convert samples
                for (i, sample) in chunk.samples.enumerated() {
                    floatChannelData[i] = Float(sample) / 32767.0
                }
                
                // Schedule for playback
                self?.playerNode?.scheduleBuffer(buffer)
                
                // Start playback on first chunk
                if chunk.index == 0 {
                    self?.playerNode?.play()
                }
            }
        )
    }
}
```

### Pattern 2: Queue-Based Buffering

For apps that need buffering control:

```swift
actor StreamingAudioBuffer {
    private var queue: [AudioChunk] = []
    private let maxBufferSize: Int = 10
    private var isPlaying = false
    
    func enqueue(_ chunk: AudioChunk) {
        guard queue.count < maxBufferSize else {
            // Backpressure: wait for consumer
            Task { try await Task.sleep(nanoseconds: 10_000_000) }
            return
        }
        queue.append(chunk)
    }
    
    func dequeue() -> AudioChunk? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }
    
    func play(text: String, voice: Voice) async throws {
        isPlaying = true
        
        try await engine.streamSynthesis(text: text, voice: voice) { chunk in
            Task {
                await self.enqueue(chunk)
            }
        }
    }
}
```

## Parameter Control During Streaming

Adjust voice characteristics in real-time:

```swift
let controller = RealTimeController()

// Start streaming
try await engine.streamSynthesis(
    text: "This speech gradually becomes faster...",
    voice: .narratorFeminine,
    onChunk: { chunk in
        audioPlayer.enqueue(chunk.samples)
    }
)

// Change parameters mid-synthesis
try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
await controller.setRate(1.5)  // Speed up to 1.5x

try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 more second
await controller.setPitchShift(7)  // Raise pitch 7 semitones
```

## Error Recovery

### Handling Streaming Failures

```swift
func streamWithErrorHandling(
    text: String,
    voice: Voice,
    audioPlayer: AudioPlayer
) async {
    do {
        try await engine.streamSynthesis(
            text: text,
            voice: voice,
            onChunk: { chunk in
                do {
                    audioPlayer.enqueue(chunk.samples)
                } catch {
                    print("Failed to enqueue chunk: \(error)")
                    // Continue anyway; we can handle a lost chunk
                }
            }
        )
    } catch ChoirError.streamingError(let reason) {
        print("Streaming failed: \(reason)")
        
        // Fallback to batch synthesis
        print("Falling back to batch synthesis...")
        let audio = try await engine.synthesize(text: text, voice: voice)
        audioPlayer.play(audio.audioBuffer.samples)
    } catch {
        print("Unexpected error: \(error)")
    }
}
```

### Interruption Handling

```swift
func streamWithInterruptionSupport(
    text: String,
    voice: Voice
) async throws {
    let notificationCenter = NotificationCenter.default
    var cancellationToken: AnyCancellable?
    
    // Setup interruption listener
    cancellationToken = notificationCenter.publisher(
        for: AVAudioSession.interruptionNotification
    ).sink { notification in
        if let userInfo = notification.userInfo,
           let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt {
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)!
            
            switch type {
            case .began:
                print("Audio interrupted, pausing synthesis...")
                // Pause playback
            case .ended:
                print("Resuming synthesis...")
                // Resume playback
            @unknown default: ()
            }
        }
    }
    
    defer { cancellationToken?.cancel() }
    
    try await engine.streamSynthesis(
        text: text,
        voice: voice,
        onChunk: { chunk in
            audioPlayer.enqueue(chunk.samples)
        }
    )
}
```

## Advanced Patterns

### Real-Time Voice Switching

Synthesize with multiple voices simultaneously:

```swift
func streamMultiVoice(
    dialogue: [(speaker: String, voice: Voice, text: String)]
) async throws {
    for (speaker, voice, text) in dialogue {
        print("Speaking: \(speaker)")
        
        try await engine.streamSynthesis(
            text: text,
            voice: voice,
            onChunk: { chunk in
                audioPlayer.enqueue(chunk.samples)
            }
        )
    }
}
```

### Adaptive Chunk Sizing

Automatically adjust chunk size based on available memory:

```swift
func optimizedChunkSize() -> Int {
    // Simple heuristic: smaller chunks on constrained devices
    #if os(watchOS)
    return 512   // ~10ms for watchOS
    #elseif os(iOS)
    return 2400  // ~50ms for iOS
    #else
    return 4800  // ~100ms for macOS
    #endif
}

try await engine.streamSynthesis(
    text: text,
    voice: voice,
    streamingOptions: StreamingOptions(chunkSize: optimizedChunkSize()),
    onChunk: handler
)
```

### Progress Tracking

Monitor synthesis progress:

```swift
func streamWithProgress(
    text: String,
    voice: Voice,
    onProgress: (Double) -> Void
) async throws {
    let estimatedChunks = max(1, text.count / 50)  // Rough estimate
    var chunksReceived = 0
    
    try await engine.streamSynthesis(
        text: text,
        voice: voice,
        onChunk: { chunk in
            chunksReceived += 1
            let progress = Double(chunksReceived) / Double(estimatedChunks)
            onProgress(min(1.0, progress))  // Cap at 100%
            
            audioPlayer.enqueue(chunk.samples)
        }
    )
}
```

## Performance Benchmarks

### Latency (Time to First Audio)

| Scenario | Latency |
|----------|---------|
| Simple sentence (10 words) | ~50ms |
| Paragraph (100 words) | ~50ms |
| Long text (1000 words) | ~50ms |

**Note:** Latency is dominated by synthesis + chunk 1 generation, not text length.

### CPU Usage

- **2400-sample chunks**: ~15-20% CPU on A15 (iOS)
- **1200-sample chunks**: ~25-30% CPU on A15
- **4800-sample chunks**: ~10-15% CPU on A15

### Memory

- **Streaming**: 5-10MB peak (chunk buffer)
- **Batch**: 50-200MB peak (full audio in RAM)

## Troubleshooting

### "Chunk callback never called"
- Verify `onChunk` closure is captured correctly
- Check that text is not empty
- Ensure engine is initialized

### Audio stuttering/gaps
- Increase chunk size (try 4800)
- Ensure audio player can consume faster than synthesis produces
- Monitor CPU usage; reduce other tasks

### "Memory pressure warning"
- Reduce chunk size
- Use streaming instead of batch
- Clear old sessions with `sessionManager.clearAllSessions()`

### Silence at beginning of audio
- Normal: first chunk takes ~50ms to generate
- Not an issue; structure audio player to handle variable first-chunk timing

## Best Practices

1. **Use streaming for**: Interactive apps, long texts, games, voice UI
2. **Use batch for**: Short notifications, test/offline, simple use cases
3. **Chunk size**: Start with 2400, adjust based on your latency requirements
4. **Error handling**: Always provide batch fallback for critical features
5. **Testing**: Test on target devices (iOS, watchOS) before shipping

---

See also: [Getting Started](./GETTING_STARTED.md), [Error Handling](./ERROR_HANDLING.md), [Platforms](./PLATFORMS.md)
