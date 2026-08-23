# CHOIR — On-Device Voice Synthesis Development Kit

[![CI](https://github.com/halalchristiano/Choir/actions/workflows/ci.yml/badge.svg)](https://github.com/halalchristiano/Choir/actions/workflows/ci.yml)
[![Swift 6.3](https://img.shields.io/badge/Swift-6.3-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20visionOS%20%7C%20watchOS%20%7C%20tvOS-lightgrey.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

An experimental on-device text-to-speech Swift package for Apple platforms.

> ### ⚠️ Pre-alpha (v0.16.0) — not a speech product yet
>
> The package contains substantial API, linguistic, prosody, caching, and test
> infrastructure. The default `SynthesisPipeline` still uses
> `MockAcousticModel` and `MockVocoder`, producing a test sine wave rather than
> speech. Core ML adapter types are injectable, but no production model is bundled.
> The 32 voices are metadata profiles with unique conditioning IDs, not 32
> trained or perceptually distinct voices.
>
> Treat this as a foundation to build on, not a drop-in replacement for AVSpeechSynthesizer.
> The API may change before 1.0.

## Overview

CHOIR is a self-contained TTS engine featuring:

- **32 Voice Definitions**: Engineered instruments, not clones. Spanning 4 age bands, multiple gender presentations, villain archetypes, and specialty voices for games, narration, and media. *(Parameter profiles; see the pre-release note above.)*
- **Offline architecture**: The runtime code has no intended network dependency; a release still requires an automated network-silence audit.
- **Declared platform targets**: iOS, iPadOS, macOS, visionOS, watchOS, and tvOS; physical-device conformance remains outstanding.
- **Parameter API**: Pitch, rate, emotion, breathiness, and age/gender controls exist, but the mock path does not prove their audible effect.
- **On-device NLP speech planning**: Deterministic English intent, restrained
  emotion, dialogue, contrastive focus, and clause analysis feed duration,
  pitch, energy, accent, pause, and boundary-tone planning.
- **Batch and progressive delivery**: Streaming prepares request-wide prosody,
  then renders and emits natural phrase units before later units run.
- **Audio output**: 48 kHz mono 16-bit PCM by default, plus float PCM,
  conversion/mastering primitives, validated WAV export, and timing/caption sidecars.

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
├── LinguisticFrontend/            # Text normalization, G2P, stress, SSML
├── NaturalLanguage/               # Contextual speech planning
├── Prosody/                       # Prosody prediction, ToBI
├── VoiceSynthesis/                # Sample-based synthesis (see REAL_VOICES.md)
├── Caching/                       # Asset caching with LRU eviction
├── Demo/                          # Runnable usage examples
└── Models/                        # Model protocols, development mocks, experimental vocoder

Tests/ChoirTests/
├── ChoirTests.swift               # Core API tests
├── LinguisticFrontendTests.swift  # Text processing
├── SynthesisTests.swift           # Pipeline
├── AdvancedFeaturesTests.swift    # Blending, ToBI, filters
├── CachingAndAudioTests.swift     # Cache + encoding
├── ErrorHandlingTests.swift       # Error paths
└── ProductionFeaturesTests.swift  # Streaming, performance
```

## The 32 Voices

Per SRS `VOX-G-001`, the library is organized as **4 age bands x 2 gender
presentations x 4 voices per cell**, exactly one of which is a villain
archetype (`VOX-V-001`). Every voice carries a stable identifier that is
permanent across versions (`VOX-G-005`).

| Age band | Male | Female |
|---|---|---|
| **Child** | FINCH, SCOUT, ALDER, *WICK* | WREN, JUNIPER, CLOVER, *BRIAR* |
| **Young Adult** | ORION, FLINT, REED, *CORVIN* | LYRA, ISLA, NOVA, *SABLE* |
| **Middle-Aged** | GARRICK, HALE, BRAM, *MALVERN* | MARION, TAMSIN, GREER, *RAVENNA* |
| **Elderly** | ALARIC, WILFRED, CORMAC, *GRIMSHAW* | MAEVE, ODETTE, HATTIE, *HESPERA* |

*Italics mark the eight villain voices.*

Each voice exposes its full designed parameter set (`VOX-P-001`) — median F0
and range, formant scale, spectral tilt, breathiness, roughness, tempo, and
pitch dynamism — together with a character description and recommended-use
tags:

```swift
let voice = Voice.grimshaw
voice.identifier                  // "choir.eld.male.villain.grimshaw"
voice.displayName                 // "GRIMSHAW"
voice.ageBand                     // .elderly
voice.gender                      // .male
voice.isVillain                   // true
voice.profile.medianF0            // 98.0
voice.profile.f0Range             // 70.0...140.0
voice.profile.roughness           // 0.30
voice.profile.recommendedUse      // [.antagonist, .narration]

// Query the library
Voice.voices(ageBand: .child, gender: .female)   // WREN, JUNIPER, CLOVER, BRIAR
Voice.villains                                    // the eight villains
Voice.voices(for: .narration)                     // every narration-tagged voice
Voice.voice(withIdentifier: "choir.ya.female.lyra")
```

> **Note:** the voice roster changed in 0.3.0 to conform to the SRS. See
> [SRS_CONFORMANCE.md](./SRS_CONFORMANCE.md) for the migration table and for
> specification defects found while implementing it.

## Installation

Add CHOIR to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/halalchristiano/Choir.git", from: "0.16.0")
]
```

Or in Xcode: **File → Add Package Dependencies…** and paste the repository URL.

## Quick Start

```swift
import Choir

// Create and initialize the engine
let engine = ChoirEngine()
try await engine.initialize()

// Synthesize text
let audio = try await engine.synthesize(
    text: "Hello, world!",
    voice: .isla,
    parameters: SynthesisParameters(rate: 0.95, emotionalIntensity: 0.7)
)

// Render and deliver natural phrase units progressively
try await engine.streamSynthesis(
    text: "Deliver this render in chunks...",
    voice: .orion,
    options: StreamingOptions(),
    onChunk: { chunk in
        // Handle audio chunk
        print("Received \(chunk.samples.count) samples")
    }
)
```

## 📚 Documentation

Complete guides for all use cases:

| Guide | Purpose | Best For |
|-------|---------|----------|
| **[Getting Started](./GETTING_STARTED.md)** | 5-min quickstart, installation, common patterns | New users |
| **[Error Handling](./ERROR_HANDLING.md)** | All error types, recovery patterns, testing | Production reliability |
| **[Streaming Synthesis](./STREAMING.md)** | Current chunked-delivery behavior and true-streaming gates | Integration planning |
| **[Voice Blending](./VOICE_BLENDING_GUIDE.md)** | Smooth voice transitions, character morphing | Creative applications |
| **[Natural-language processing](./NATURAL_LANGUAGE_PROCESSING.md)** | Intent, emotion, dialogue, and contextual emphasis | Expressive reading |
| **[Platforms Guide](./PLATFORMS.md)** | iOS, macOS, watchOS, visionOS, tvOS specifics | Cross-platform apps |

**Quick Links:**
- [API Reference](#api-overview) — Core types and methods
- [Advanced Features](#advanced-features) — Voice blending, ToBI prosody, SSML
- [Implementation Status](#implementation-status) — Phase tracking
- [Examples](./Sources/Choir/Demo/ChoirDemo.swift) — 9 runnable examples

## API Overview

### ChoirEngine
The main synthesis actor. Supports batch synthesis and phrase-progressive delivery with async/await.

```swift
let engine = ChoirEngine()
try await engine.initialize()

// Batch synthesis
let audio = try await engine.synthesize(
    text: "Hello world",
    voice: .isla,
    parameters: SynthesisParameters(rate: 1.2, emotionalIntensity: 0.8)
)

// Phrase-progressive delivery
try await engine.streamSynthesis(
    text: "Chunked output",
    voice: .orion,
    onChunk: { chunk in print(chunk.samples.count) }
)
```

- `initialize()` — Load models and initialize the engine
- `synthesize(text:voice:parameters:)` — Batch synthesis, returns AudioBuffer
- `streamSynthesis(text:voice:parameters:options:onChunk:)` — Phrase-progressive chunk callbacks

### Voice
32 cases representing each available voice. Properties:
- `displayName` — Human-readable name
- `ageBand` — Child, young-adult, middle-aged, or elderly
- `isVillain` — Boolean flag for villain voices

### SynthesisParameters
Parametric control over synthesis:
- `pitchShift` — Semitones (-6 to +6)
- `rate` — Speed multiplier (0.6 to 2.0)
- `emotionalIntensity` — Emotional intensity (0.0 to 1.0)
- `breathiness` — Breathiness amount (0.0 to 1.0)
- `ageShift` — Normalized age shifting (-1.0 to +1.0)
- `genderShift` — Gender shift (-1.0 to +1.0)

### Error Handling
`ChoirError` enum with specific cases:
- `.modelLoadFailed(reason:)`
- `.textProcessingFailed(reason:)`
- `.synthesisError(reason:)`
- `.audioEncodingFailed(reason:)`
- `.invalidParameter(parameter:reason:)`
- `.notInitialized`
- `.engineBusy`
- `.cancelled`
- And more...

## Advanced Features

### Speaking Styles
Pre-configured parameter sets for common speaking patterns:

```swift
let audio = try await engine.synthesize(
    text: "What an amazing day!",
    voice: .lyra,
    parameters: SpeakingStyle.happy.parameters
)
```

Available styles: `.normal`, `.fast`, `.slow`, `.whisper`, `.shout`, `.happy`, `.sad`, `.angry`, `.calm`

These presets are parameter bundles. Their audible behavior must be validated
again after production models replace the mocks.

### Voice Blending
Interpolation between two parameter sets (not yet timbre interpolation):

```swift
let blending = VoiceBlending()
let profile1 = VoiceBlending.VoiceProfile(voice: .orion)
let profile2 = VoiceBlending.VoiceProfile(voice: .lyra)

for step in 0...10 {
    let mix = Double(step) / 10.0
    let params = blending.blend(profile1, with: profile2, mix: mix)
    let audio = try await engine.synthesize(text: text, voice: .orion, parameters: params)
}
```

### ToBI Prosody Control
Linguistic prosody annotations (Tones and Break Indices):

```swift
let predictor = ToBIPredictor()
let tobi = ToBI(
    pitchAccent: .L_H,      // Rising accent
    phraseAccent: .high,
    boundaryTone: .low,
    breakIndex: .intonational
)

let f0 = predictor.applyToBIToF0(baseF0: 120, tobi: tobi, position: 0.5)
```

### Audio Post-Processing
Professional audio quality filters:

```swift
let filters = AudioFilters()

let audio = try await engine.synthesize(text: "Demo", voice: .isla)

// Apply processing chain
let deessed = filters.deEsser(audio.samples)
let normalized = filters.normalize(deessed, targetLevel: -6.0)
let compressed = filters.compress(normalized, threshold: -20, ratio: 4.0)
```

Supported filters: high-pass, low-pass, normalize, soft clip, compress, de-esser, reverb

### SSML Markup
Control prosody with XML-like tags:

```swift
let ssml = """
Hello <prosody pitch="+5" rate="1.2">there!</prosody>
<emphasis level="strong">This is important!</emphasis>
"""

let audio = try await engine.synthesize(text: ssml, voice: .orion)
```

## Implementation Status

### Implemented infrastructure

**Phase 1: Core Package & API**
- Swift Package structure with cross-platform support
- 32 voice definitions (age bands, gender, villains, specialty voices)
- Synthesis parameters and audio format specifications
- Comprehensive error handling

**Phase 2: Linguistic Front End**
- Text normalization (contractions, numbers, abbreviations, currency)
- Grapheme-to-phoneme (G2P) conversion with rule-based fallback
- Stress assignment with dictionary patterns
- SSML markup parsing (prosody, emphasis, pause)
- On-device contextual NLP for intent, restrained emotion, dialogue,
  contrastive focus, and clause boundaries
- Complete text-to-phoneme pipeline

**Phase 3: Prosody & Synthesis**
- Duration prediction with rate adjustment
- Pitch contour generation with declination
- Energy modeling for realistic prosody
- Stress-based accentuation
- Emotional intensity mapping to pitch/loudness
- NLP-driven local pacing, pitch, energy, accents, pauses, and terminal tones

**Phase 4: Model and vocoder interfaces**
- Phoneme encoding/decoding interface
- Deterministic mock acoustic model for testing
- Experimental spectral reconstruction code and a separate sine-wave mock vocoder
- Resampling and windowing
- PCM 16-bit output

**Phase 5: Development pipeline**
- End-to-end synthesis orchestration
- Batch (offline) synthesis
- Post-render chunk delivery with async/await
- ChoirEngine with full state management

**Phase 6: Output & Caching**
- WAV audio encoding with RIFF headers
- Raw PCM export
- Actor-based asset caching with LRU eviction
- Cache statistics and monitoring
- Memory-efficient storage management

**Phase 7: Advanced Prosody & Audio**
- ToBI (Tones and Break Indices) linguistic prosody
- Voice blending and interpolation
- 9 speaking style presets
- Audio post-processing filters (7 filter types)
- Experimental post-processing utilities
- Comprehensive demo module

### 📋 Test Coverage

The suite covers text normalization, G2P, stress assignment, SSML parsing,
prosody and ToBI, model/vocoder interfaces, the mock pipeline, chunk delivery,
audio encoding, filters, caching, and error paths. Passing infrastructure tests
does not establish speech naturalness, voice distinctness, or production SRS
conformance.

Run them with `swift test`. CI executes the same suite on every push.

### 🚀 Next Phases

**Next: Model Training**
- Acoustic model training pipeline
- Vocoder training with sample data
- Voice model asset preparation

**Then: Performance Optimization**
- Core ML model integration
- GPU acceleration
- Quantization for edge devices
- Latency benchmarking

**Later optional features**
- Voice conversion/morphing
- Real-time parameter adjustment
- Multi-speaker synthesis
- Singing support (v2.0)

### 📊 Current Build Status

Verified by [CI](./.github/workflows/ci.yml) on every push, rather than
asserted here — see the badge at the top of this file for live status.

## Requirements

- Swift 6.3+
- iOS 17+, macOS 14+, visionOS 1+, watchOS 10+, tvOS 17+

## Building

```bash
swift build
swift test
```

## License

[MIT](./LICENSE) © 2026 Kiana Arabpour

---

**Vision**: CHOIR is the permanent, final answer to every text-to-speech need across all projects: Scripture reading, narration, character voicing for games, video voiceover, and more. Once built, no external TTS service is ever required again.
