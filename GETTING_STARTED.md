# Getting Started with CHOIR

Welcome! This guide will get you synthesizing speech with CHOIR in 5 minutes.

## Installation

### Swift Package Manager

Add CHOIR to your `Package.swift`:

```swift
.package(url: "https://github.com/halalchristiano/Choir.git", from: "0.1.0")
```

Or in Xcode: File → Add Packages → Paste the URL above.

## Your First Synthesis

Here's a complete example to speak text:

```swift
import Choir

// 1. Create the synthesis engine
let engine = ChoirEngine()

// 2. Initialize (loads voice models)
try await engine.initialize()

// 3. Synthesize text
let audio = try await engine.synthesize(
    text: "Hello, welcome to Choir!",
    voice: .narratorFeminine
)

// 4. Play or save the audio
let buffer = audio.audioBuffer  // PCM samples
// Use your favorite audio player...
```

## Common Patterns

### Pick a Different Voice

Choose from 32 professional voices:

```swift
// Narrators
.narratorMasculine
.narratorFeminine

// Age bands (child, young adult, middle-aged, elderly)
.childFeminine
.youngAdultNeutral1
.middleAgedMasculine
.elderlyFeminine

// Characters (witchy, gruff, robotic, etc.)
.characterWitchyFeminine
.characterRobotNeutral

// List all voices
Voice.allCases
```

### Change Speech Speed & Pitch

```swift
let audio = try await engine.synthesize(
    text: "Whisper this...",
    voice: .narratorMasculine,
    parameters: SynthesisParameters(
        pitchShift: 5,      // Raise pitch by 5 semitones
        rate: 0.8           // Slow down to 80% speed
    )
)
```

### Stream Audio in Real-Time

For responsive apps, stream chunks as they're generated:

```swift
try await engine.streamSynthesis(
    text: "This text streams in chunks...",
    voice: .narratorFeminine,
    onChunk: { chunk in
        audioPlayer.enqueue(chunk.samples)
        if chunk.isFinal {
            audioPlayer.play()
        }
    }
)
```

### Apply Audio Effects

Enhance audio with professional effects:

```swift
let audio = try await engine.synthesize(text: "...", voice: .narratorFeminine)

let withEffects = try audio.apply(
    effectChain: AudioEffectChain.podcast  // or .warmth, .clean, .voiceClarity
)

// Or build custom chains:
let custom = AudioEffectChain()
    .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -6)))
    .add(AudioEffect(name: "De-esser", kind: .deEsser(centerHz: 6000)))
```

## Platform-Specific Notes

### iOS / iPadOS
- Background audio playback requires proper AVAudioSession setup
- Supports streaming and real-time synthesis
- Works with Voice Over and accessibility features

### macOS
- Native AppKit support
- Full feature set available
- Works in sandboxed apps

### watchOS
- Memory-constrained; use shorter texts
- Streaming recommended over batch synthesis
- Limit concurrent sessions

### visionOS
- Spatial audio support (future enhancement)
- Works in both app and scene contexts

## Troubleshooting

### "Model not found" Error
Make sure you call `await engine.initialize()` before synthesizing:
```swift
try await engine.initialize()  // Load models first
try await engine.synthesize(...)
```

### Audio is too quiet/loud
Use normalization to control output level:
```swift
parameters: SynthesisParameters(
    // ... other params
)
// Or apply normalization filter
let chain = AudioEffectChain()
    .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -6)))
```

### Performance is slow
- **Streaming** is faster than batch synthesis for long texts
- **Batch mode** is better for short utterances
- Cache audio for repeated text using `SynthesisSession`

### My app crashes after synthesis
Ensure proper async/await handling:
```swift
// ✅ Correct
Task {
    try await engine.synthesize(...)
}

// ❌ Don't do this
engine.synthesize(...)  // Missing await
```

## Next Steps

- **[API Reference](./API.md)** — Complete method documentation
- **[Voice Blending](./VOICE_BLENDING_GUIDE.md)** — Morph between voices
- **[Streaming Guide](./STREAMING.md)** — Real-time synthesis patterns
- **[Error Handling](./ERROR_HANDLING.md)** — Recovery strategies
- **[Architecture](./ARCHITECTURE.md)** — How CHOIR works internally

## Questions?

- Check the [Examples](./Sources/Choir/Demo/ChoirDemo.swift) in the source code
- Review the comprehensive [API Reference](./API.md)
- Open an issue on [GitHub](https://github.com/halalchristiano/Choir/issues)

---

Happy synthesizing! 🎙️
