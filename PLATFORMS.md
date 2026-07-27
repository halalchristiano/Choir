# Platform-Specific Integration Guide

CHOIR supports iOS, macOS, watchOS, visionOS, and tvOS. Each platform has unique constraints and best practices.

## iOS & iPadOS

### Setup
```swift
import AVFoundation
import Choir

// Configure audio session for playback
let audioSession = AVAudioSession.sharedInstance()
try audioSession.setCategory(.playback, mode: .default, options: [.duckOthers])
try audioSession.setActive(true)

let engine = ChoirEngine()
try await engine.initialize()
```

### Background Audio
For background playback (e.g., audio player app):
```swift
// In Info.plist, add:
// <key>UIBackgroundModes</key>
// <array>
//   <string>audio</string>
// </array>

// Enable background mode in your app's capabilities
```

### Memory Constraints
iOS is memory-constrained; optimize for efficiency:
```swift
// Use streaming for long texts (>30KB)
try await engine.streamSynthesis(
    text: longText,
    voice: .narratorFeminine,
    streamingOptions: StreamingOptions(chunkSize: 2400)  // ~50ms chunks
)

// Or batch shorter texts
for chunk in textChunks {
    let audio = try await engine.synthesize(text: chunk, voice: voice)
    audioPlayer.enqueue(audio)
}
```

### Silence/Interruption Handling
Handle audio interruptions (phone calls, alerts):
```swift
let audioSession = AVAudioSession.sharedInstance()

NotificationCenter.default.addObserver(
    forName: AVAudioSession.interruptionNotification,
    object: nil,
    queue: .main
) { notification in
    if let userInfo = notification.userInfo,
       let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt {
        let type = AVAudioSession.InterruptionType(rawValue: typeValue)!
        
        switch type {
        case .began:
            audioPlayer.pause()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionsKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    audioPlayer.play()
                }
            }
        @unknown default: ()
        }
    }
}
```

## macOS

### Full Feature Set
macOS has no memory constraints and supports all CHOIR features:
```swift
let engine = ChoirEngine()
try await engine.initialize()

// Use batch synthesis for best quality
let audio = try await engine.synthesize(
    text: "Full Shakespeare soliloquy here...",
    voice: .narratorMasculine,
    parameters: SynthesisParameters(rate: 1.0)  // Native speed
)
```

### App Sandbox
If your app is sandboxed, ensure audio output is allowed:
```swift
// In Entitlements.plist:
// <key>com.apple.security.device.audio-input</key>
// <false/>
// Audio output doesn't require special permissions
```

### Native Audio Engine (Future)
Current version uses basic playback; consider integrating with:
- AVAudioEngine for advanced mixing
- CoreAudio for low-latency synthesis
- AudioUnit for real-time effects

## watchOS

### Memory-Constrained Environment
Watch apps have ~25MB available; plan accordingly:

```swift
// ✅ Recommended: Shorter texts, streaming
try await engine.streamSynthesis(
    text: "Weather update",  // <100 chars
    voice: .narratorFeminine,
    onChunk: { chunk in
        wkAudioPlayer.enqueue(chunk.samples)
    }
)

// ❌ Avoid: Long texts, batch synthesis
// let audio = try await engine.synthesize(text: veryLongText, voice: voice)
```

### watchOS Speaker Constraints
Watch speakers are small; use de-esser and normalization:
```swift
let chain = AudioEffectChain()
    .add(AudioEffect(name: "De-esser", kind: .deEsser(centerHz: 5000)))
    .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -3.0)))

let audio = try await engine.synthesize(text: "...", voice: .narratorFeminine)
let processed = chain.process(audio.audioBuffer.samples)
```

### Recommendations
- **Streaming**: Always preferred on watchOS
- **Text limit**: ≤200 characters for best performance
- **Voice choice**: Neutral or feminine voices typically sound better on small speakers
- **Session management**: Clear session caches frequently to free memory

### Sample Implementation
```swift
// In a watchOS complication or notification handler
let engine = ChoirEngine()
try await engine.initialize()

let shortText = String(userInput.prefix(100))
try await engine.streamSynthesis(text: shortText, voice: .narratorFeminine)
```

## visionOS

### Spatial Audio (Beta)
Future CHOIR versions will support spatial audio in visionOS apps:

```swift
// Currently: Standard stereo synthesis
let audio = try await engine.synthesize(
    text: "Welcome to visionOS",
    voice: .narratorMasculine
)

// Future: Spatial audio with directional synthesis
// try await engine.synthesizeSpatial(
//     text: "...",
//     voice: voice,
//     position: SIMD3<Float>(0, 0.5, -1.0)  // Position in 3D space
// )
```

### Platform-Specific Considerations
- Works in both `.sharedSpace` and `.privateSpace` contexts
- Audio continues properly when app enters/exits immersive space
- Use streaming for responsive spatial experiences

## tvOS

### Large Screen, No Touch
tvOS apps synthesize audio for accessibility and game narration:

```swift
let engine = ChoirEngine()
try await engine.initialize()

// Text-to-speech for menus, narration
let audioForMenu = try await engine.synthesize(
    text: "Select an option",
    voice: .narratorFeminine
)
```

### Remote Input
Use Siri Remote or game controller callbacks:
```swift
// Trigger synthesis from remote events
func handleRemoteClick() {
    Task {
        let audio = try await engine.synthesize(
            text: "Button pressed",
            voice: .characterRobotNeutral
        )
        tvAudioPlayer.play(audio)
    }
}
```

### Performance Targets

| Platform | Voice Count | Batch Speed | Streaming | Memory |
|----------|-----------|-------------|-----------|---------|
| iOS/iPadOS | 32 | 150ms/sec | Recommended | Constrained |
| macOS | 32 | 100ms/sec | Excellent | Unconstrained |
| watchOS | 32 | 200ms/sec | Required | Tightly constrained |
| visionOS | 32 | 120ms/sec | Excellent | Moderate |
| tvOS | 32 | 110ms/sec | Excellent | Moderate |

## Cross-Platform Best Practices

### 1. Conditional Compilation
```swift
#if os(watchOS)
let textLimit = 200
#elseif os(iOS)
let textLimit = 5000
#else
let textLimit = 50000
#endif
```

### 2. Memory Monitoring
```swift
import os

let logger = Logger(subsystem: "com.example.choir", category: "memory")

Task {
    while true {
        // Monitor memory pressure
        try await Task.sleep(nanoseconds: 1_000_000_000)
        
        let pressure = try os_proc_available_memory()
        if pressure < 10_000_000 {  // <10MB free
            logger.warning("Low memory pressure")
            // Consider clearing caches
        }
    }
}
```

### 3. Session Management
```swift
// Clean up sessions on all platforms
let sessionManager = SynthesisSessionManager()

// Create and use sessions
let session = await sessionManager.createSession(voice: .narratorFeminine)
// ... use session ...
await sessionManager.clearSession(session.id)  // Always clean up
```

### 4. Graceful Degradation
```swift
func bestVoiceForPlatform() -> Voice {
    #if os(watchOS)
    return .narratorFeminine  // Smallest file size
    #elseif os(iOS)
    return .narratorFeminine  // Balanced
    #else
    return .audiobook  // Highest quality
    #endif
}
```

## Troubleshooting by Platform

### iOS: "No default Bluetooth device"
Ensure AVAudioSession is configured before synthesis.

### macOS: "Permission denied"
Check App Sandbox entitlements for audio output.

### watchOS: "Killed (low memory)"
Reduce text size, use streaming, clear old sessions.

### visionOS: Audio not spatial
Spatial audio is in beta; use standard synthesis for now.

### tvOS: No sound
Verify playback is routed to correct audio output.

---

See also: [Getting Started](./GETTING_STARTED.md), [Streaming Guide](./STREAMING.md), [Error Handling](./ERROR_HANDLING.md)
