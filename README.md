# CHOIR — On-Device Neural Voice Synthesis Engine

A fully on-device neural text-to-speech engine delivered as a Swift Package for the entire Apple ecosystem (iOS, iPadOS, macOS, visionOS, watchOS, tvOS). Complete sovereignty, zero network dependency, 32 original synthetic voices.

## Overview

CHOIR is a self-contained TTS engine featuring:

- **32 Synthetic Voices**: Engineered instruments, not clones. Spanning 4 age bands, multiple gender presentations, villain archetypes, and specialty voices for games, narration, and media.
- **On-Device**: Zero network calls. Works identically in airplane mode on a mountaintop.
- **Cross-Platform**: iOS, iPadOS, macOS, visionOS, watchOS, tvOS via a single Swift Package.
- **Parametric Control**: Adjust pitch, rate, emotion, breathiness, age/gender shift, emphasis.
- **Streaming & Batch**: Real-time streaming synthesis and offline batch rendering.
- **Professional Audio**: 48 kHz, 16-bit PCM, high-quality vocoder output.

## Project Structure

```
Sources/Choir/
├── Core/                          # Core types and interfaces
│   ├── Voice.swift               # 32 voice definitions
│   ├── SynthesisParameters.swift  # Prosody and expression control
│   └── Errors.swift              # Error types
├── Synthesis/                     # Synthesis engine
│   └── SynthesisEngine.swift      # Main ChoirEngine actor
├── AudioOutput/                   # Audio export
│   └── AudioBuffer.swift          # PCM and format types
├── LinguisticFrontend/            # (Planned) Text processing
├── Prosody/                       # (Planned) Prosody prediction
├── Streaming/                     # (Planned) Real-time streaming
├── Caching/                       # (Planned) Model and asset caching
├── VoiceLibrary/                  # (Planned) Voice assets
└── Models/                        # (Planned) ML model definitions

Tests/ChoirTests/
└── ChoirTests.swift               # Core API tests
```

## The 32 Voices

### Age Bands (4 × 2 = 8 base voices)
- **Child**: 4 voices (2 neutral, masculine, feminine)
- **Young Adult**: 4 voices (2 neutral, masculine, feminine)
- **Middle-Aged**: 4 voices (2 neutral, masculine, feminine)
- **Elderly**: 4 voices (2 neutral, masculine, feminine)

### Villain Archetypes (6)
- Masculine (2 variants)
- Feminine (2 variants)
- Neutral/Enigmatic (2 variants)

### Specialty Voices (6)
- **Narration**: Masculine, Feminine
- **Teenage**: Masculine, Feminine
- **Character**: Witchy Feminine, Gruff Masculine, Mystical Neutral, Robot Neutral, Mystery Masculine
- **Audiobook**: Premium quality narration

## Quick Start

```swift
import Choir

// Create and initialize the engine
let engine = ChoirEngine()
try await engine.initialize()

// Synthesize text
let audio = try await engine.synthesize(
    text: "Hello, world!",
    voice: .narratorFeminine,
    parameters: SynthesisParameters(rate: 0.95, emotionalIntensity: 0.7)
)

// Stream synthesis for real-time playback
try await engine.streamSynthesis(
    text: "Speaking in real-time...",
    voice: .youngAdultNeutral1,
    options: StreamingOptions(),
    onChunk: { chunk in
        // Handle audio chunk
        print("Received \(chunk.samples.count) samples")
    }
)
```

## API Overview

### ChoirEngine
The main synthesis actor. Supports both batch and streaming synthesis with full async/await support.

- `initialize()` — Load models and initialize the engine
- `synthesize(text:voice:parameters:)` — Batch synthesis, returns AudioBuffer
- `streamSynthesis(text:voice:parameters:options:onChunk:)` — Streaming synthesis with chunk callback
- `exportAudio(_:format:)` — Export to WAV, MP3, AAC, or FLAC

### Voice
32 cases representing each available voice. Properties:
- `displayName` — Human-readable name
- `ageBand` — Age band (1-4) or 0 for specialty voices
- `isVillain` — Boolean flag for villain voices

### SynthesisParameters
Parametric control over synthesis:
- `pitchShift` — Semitones (-12 to +12)
- `rate` — Speed multiplier (0.5 to 2.0)
- `emotionalIntensity` — Emotional intensity (0.0 to 1.0)
- `breathiness` — Breathiness amount (0.0 to 1.0)
- `ageShift` — Age shifting (-5 to +5)
- `genderShift` — Gender shift (-1.0 to +1.0)

### Error Handling
`ChoirError` enum with specific cases:
- `.modelLoadFailed(reason:)`
- `.textProcessingFailed(reason:)`
- `.synthesisError(reason:)`
- `.audioEncodingFailed(reason:)`
- `.invalidParameter(parameter:reason:)`
- `.notInitialized`
- `.cancelled`
- And more...

## Development Status

**Current**: ✅ Package structure and core API types  
**Next**: 
- Linguistic front end (text normalization, grapheme-to-phoneme conversion)
- Acoustic model integration
- Vocoder implementation
- Audio encoding (WAV, MP3, AAC)
- Streaming synthesis pipeline
- Model asset management
- Performance optimization

## Requirements

- Swift 6.3+
- iOS 16+, macOS 13+, visionOS 1+, watchOS 9+, tvOS 16+

## Building

```bash
swift build
swift test
```

## License

Proprietary — Sole Developer Project

---

**Vision**: CHOIR is the permanent, final answer to every text-to-speech need across all projects: Scripture reading, narration, character voicing for games, video voiceover, and more. Once built, no external TTS service is ever required again.
