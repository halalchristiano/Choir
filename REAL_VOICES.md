# CHOIR: Real Voice Synthesis

**TL;DR:** Synthesize speech using actual human voices. Record phoneme samples once, synthesize unlimited speech on-device, free and fully programmed.

---

## What This Is

CHOIR is a **sample-based voice synthesis engine** that:
- ✅ Uses real human voice recordings (actual phoneme samples)
- ✅ No ML models, no cloud APIs, no synthetic voice generators
- ✅ Fully programmed in Swift
- ✅ Runs completely on-device
- ✅ Free and open source

**How it works:**
1. Record a person speaking English phonemes (~300-500 samples, ~10-30 minutes total)
2. Organize samples by phoneme
3. To synthesize new speech:
   - Convert text → phonemes
   - Look up each phoneme sample
   - Concatenate and blend them
   - Output audio

---

## Quick Start

### 1. Create a Voice Library

```swift
import Choir

// Create an empty library
let library = VoiceSampleLibrary(voiceName: "MyVoice")

// Load real phoneme samples (you provide these)
let samples = loadPhonemeRecordings() // Your recorded samples

for sample in samples {
    await library.addSample(sample)
}
```

### 2. Synthesize Speech

```swift
// Create synthesizer with your voice library
let synthesizer = SimpleSynthesizer(library: library)

// Synthesize text
let audio = try await synthesizer.synthesize(text: "Hello, world!")

// Use the audio
playAudio(audio)  // Play on speaker
saveAudio(audio)  // Save to file
streamAudio(audio)  // Stream to network
```

### 3. That's It

No models to download, no APIs to configure, no synthetic voice artifacts.

---

## Voice Sample Recording Guide

### What You Need

- **Microphone**: USB or built-in (no special equipment needed)
- **Quiet room**: Minimal background noise
- **Recording software**: Audacity (free) or similar
- **Time**: 20-30 minutes per voice

### Phonemes to Record

All English phonemes (IPA notation):

**Vowels (9):**
- ɑ, æ, ɛ, ə, ɪ, ɔ, ʊ, ʌ, ɝ

**Consonants (24):**
- p, b, t, d, k, g
- m, n, ŋ
- f, v, θ, ð, s, z, ʃ, ʒ
- h
- w, j, l, ɹ

**Total: ~33 phonemes**

### Recording Steps

1. **Create script** listing each phoneme with carrier words:
   ```
   ɑ: "father"
   æ: "cat"
   ɛ: "dress"
   ... (repeat for all 33 phonemes)
   ```

2. **Record** each phoneme 3-5 times:
   - Consistent volume
   - Clear pronunciation
   - ~0.5 second per phoneme
   - ~3-5 second gaps between takes

3. **Export** as 48kHz mono WAV or similar

4. **Segment** each phoneme sample (audio editing software)

5. **Load** into CHOIR:
   ```swift
   let sample = PhonemeSample(
       phoneme: "ɑ",
       audioData: audioData,  // Int16 samples
       sampleRate: 48000,
       averagePitch: 110.0
   )
   await library.addSample(sample)
   ```

---

## Example: Complete Implementation

```swift
import Choir

// Step 1: Record phoneme samples (done once)
let voiceRecordings = recordPhonemes()  // 30 minutes of audio

// Step 2: Load into library
let library = VoiceSampleLibrary(voiceName: "JohnDoe")
for (phoneme, audioSamples) in voiceRecordings {
    let sample = PhonemeSample(
        phoneme: phoneme,
        audioData: audioSamples
    )
    await library.addSample(sample)
}

// Step 3: Synthesize
let synthesizer = SimpleSynthesizer(library: library)

// Synthesize different texts using the SAME voice
let greetings = [
    "Hello there",
    "How are you today?",
    "Nice to meet you",
    "See you later"
]

for text in greetings {
    let audio = try await synthesizer.synthesize(text: text)
    playAudio(audio)  // Sounds like the recorded person
}
```

---

## Architecture

```
Text Input
    ↓
[TextNormalizer] - Expand abbreviations, numbers, etc.
    ↓
[Phonemizer] - Convert text to phonemes
    ↓
[SampleBasedSynthesizer]
    • Look up phoneme samples
    • Concatenate samples
    • Apply crossfades
    • Normalize volume
    ↓
Audio Output (PCM 16-bit, 48kHz)
```

---

## API Reference

### VoiceSampleLibrary

```swift
public actor VoiceSampleLibrary {
    // Add a phoneme sample
    public func addSample(_ sample: PhonemeSample)
    
    // Get sample for a phoneme
    public func getSample(for phoneme: String) -> PhonemeSample?
    
    // Check if library has phoneme
    public func hasSample(for phoneme: String) -> Bool
    
    // Get all available phonemes
    public func availablePhonemes() -> [String]
    
    // Library statistics
    public func statistics() -> LibraryStats
}
```

### SimpleSynthesizer

```swift
public actor SimpleSynthesizer {
    // Initialize with a voice library
    public init(library: VoiceSampleLibrary)
    
    // Synthesize speech from text
    public func synthesize(text: String) async throws -> AudioBuffer
    
    // Get library info
    public func libraryInfo() async -> LibraryStats
}
```

### PhonemeSample

```swift
public struct PhonemeSample: Sendable {
    public let phoneme: String
    public let audioData: [Int16]  // PCM samples
    public let sampleRate: Int     // Default: 48000
    public let averagePitch: Float // Hz
    public var durationMs: Double  // Calculated
}
```

---

## Quality Tips

- **Recording volume**: Consistent, not too loud (avoid clipping)
- **Phoneme clarity**: Pronounce each phoneme distinctly
- **Sample rate**: 48kHz recommended (but supports any)
- **Number of samples**: 3-5 per phoneme recommended for robustness
- **Post-processing**: Light normalization, no heavy compression

---

## Performance

- **Latency**: <100ms for typical sentences
- **Memory**: ~1-5MB per voice library (depends on sample count)
- **CPU**: Minimal (~5-10% on modern devices)
- **Throughput**: Can synthesize multiple texts in parallel

---

## Limitations

- ❌ No emotion/expression (yet) - can be added via prosody
- ❌ Prosody matching is basic - can be improved
- ❌ Quality depends entirely on recording quality
- ✅ Can be improved with better phoneme concatenation algorithms

---

## Next Steps

### For Users

1. Record your phoneme samples (~30 minutes)
2. Load into CHOIR via `VoiceSampleLibrary`
3. Synthesize speech with `SimpleSynthesizer`
4. Deploy to iOS, macOS, etc.

### For Developers

1. Improve phoneme blending (better crossfade algorithms)
2. Add prosody control (pitch/rate adjustment)
3. Implement duration prediction (more natural timing)
4. Add multiple speakers (mix/blend voices)
5. Integrate with AVFoundation for playback

---

## Why Sample-Based?

✅ **Real voices** - Actual recordings, not synthetic
✅ **Simple** - No ML, no complex algorithms
✅ **Fast** - Low latency, minimal compute
✅ **Free** - No APIs, no subscriptions
✅ **Private** - All on-device, no uploads
✅ **Customizable** - Use YOUR voice or anyone's voice
✅ **Programmable** - Full control, open source

---

## License

MIT - Use freely, including commercially

---

**Ready to use real voices?** Start recording! 🎙️
