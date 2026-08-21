# CHOIR Development Guide

> CHOIR 0.16 is pre-alpha infrastructure. The default acoustic model and
> vocoder are test doubles, and no trained 32-voice asset set ships. Use the
> in-package DocC **Maintenance Manual** for the production training,
> conversion, benchmark, and release contract.

## Architecture Overview

CHOIR is structured as a modular synthesis pipeline with clear separation of concerns:

```
Text Input
    ↓
[Linguistic Front End]
    ├─ TextNormalizer: Expand abbreviations, numbers, currency
    ├─ Phonemizer: Convert graphemes to phonemes (G2P)
    ├─ StressAssigner: Mark phoneme stress levels
    └─ SSMLParser: Handle prosody markup
    ↓
PhoneticTranscription
    ↓
[Prosody Module]
    ├─ ProsodyPredictor: Predict pitch, duration, energy
    └─ Annotated phonemes with timing & F0
    ↓
ProsodyDescription
    ↓
[Acoustic Models]
    ├─ PhonemeEncoder: Convert phonemes to model indices
    ├─ AcousticModelProtocol: injected model boundary
    ├─ MockAcousticModel: default development fixture
    └─ AcousticFeatures (frequency-domain)
    ↓
[Vocoder]
    ├─ MockVocoder: default development fixture
    ├─ Experimental phase reconstruction or injected vocoder
    ├─ Inverse FFT
    ├─ Overlap-add windowing
    └─ Resampling
    ↓
PCM Audio
    ↓
[Audio Output]
    ├─ AssetCache: Store computed features
    └─ AudioEncoder: WAV and raw PCM today; other codecs fail explicitly
    ↓
AudioBuffer (16-bit PCM)
```

## Module Organization

### Core (`Sources/Choir/Core/`)
- **Voice.swift**: 32 voice definitions with properties
- **SynthesisParameters.swift**: Prosody control parameters
- **Errors.swift**: Comprehensive error types
- **Choir.swift**: Package metadata

### Linguistic Front End (`Sources/Choir/LinguisticFrontend/`)
- **Phoneme.swift**: Phoneme representation with stress
- **TextNormalizer.swift**: Text preprocessing
- **Phonemizer.swift**: Grapheme-to-phoneme conversion
- **StressAssignment.swift**: Stress pattern prediction
- **SSMLParser.swift**: Markup parsing
- **LinguisticFrontend.swift**: Pipeline orchestration

### Prosody (`Sources/Choir/Prosody/`)
- **ProsodyFeatures.swift**: F0, duration, energy, contours
- **ProsodyPredictor.swift**: Prosody prediction rules

### Models (`Sources/Choir/Models/`)
- **AcousticModel.swift**: Phoneme encoding, model interface
- **Vocoder.swift**: Feature-to-waveform conversion

### Synthesis (`Sources/Choir/Synthesis/`)
- **SynthesisEngine.swift**: Main public API (actor)
- **SynthesisPipeline.swift**: Complete pipeline orchestration

### Audio Output (`Sources/Choir/AudioOutput/`)
- **AudioBuffer.swift**: PCM audio representation
- **AudioEncoder.swift**: WAV/raw PCM plus explicit failures for unavailable codecs

### Caching (`Sources/Choir/Caching/`)
- **AssetCache.swift**: LRU cache for features and models

## Extending the System

### Adding a New Voice

1. Add a new case to the `Voice` enum in `Core/Voice.swift`:
```swift
case customVoice = "choir.ya.male.custom-voice"
```

2. Implement voice-specific properties:
```swift
public var ageBand: Int {
    switch self {
    case .customVoice: return 2  // Young adult
    ...
    }
}
```

3. Follow the DocC **Extending CHOIR Safely** article. In particular, append a
   conditioning ID rather than renumbering existing voices, establish licensed
   provenance, train the shared conditioning space, validate the complete SRS
   envelope, and update release evidence. A metadata case is not an audible
   production voice.

### Implementing Core ML Models

Replace `MockAcousticModel` with real inference:

```swift
class CoreMLAcousticModel: AcousticModelProtocol {
    private let model: YourCoreMLModel

    public func predict(input: AcousticModelInput) async throws -> AcousticFeatures {
        // Convert input to MLMultiArray
        // Run model
        // Convert output to AcousticFeatures
    }
}
```

### Adding Language Support

Follow the DocC **Extending CHOIR Safely** article. Language/accent selection,
inventory, normalization, G2P, stress, lexicon, encoding, model conditioning,
cache inputs, mixed-language policy, and native-speaker evaluation must evolve
together. The current English front end is not yet a pluggable multilingual
implementation.

### Optimizing for Specific Hardware

Performance tuning points:

1. **Acoustic Model**: Use quantization (FP16, INT8)
2. **Vocoder**: Profile inverse FFT, bottleneck is likely phase reconstruction
3. **Cache**: Adjust LRU cache size for device memory
4. **Streaming**: Tune chunk size in `StreamingOptions`

## Testing Strategy

### Unit Tests
- Individual component behavior in isolation
- Edge cases and error conditions
- Located in `Tests/ChoirTests/`

### Integration Tests
- Full synthesis pipeline end-to-end
- Voice quality spot checks
- Different SSML markup combinations

### Performance Tests
- Cold start, warm time-to-first-audio, and batch/streaming real-time factor
  against the SRS's device-specific targets
- Memory usage tracking
- Cache hit rate monitoring

### Running Tests

```bash
swift test                    # Run all tests
swift test -c release        # Release build (faster)
swift test --filter CachingAndAudioTests  # Specific test suite
```

## Code Style & Conventions

### Naming
- **Types**: PascalCase (Voice, PhoneticTranscription)
- **Functions/variables**: camelCase (synthesize, phonemeList)
- **Constants**: camelCase (basePitch, maxCacheSize)
- **Enums**: PascalCase with camelCase cases (State, case ready)

### Documentation
- Public APIs require doc comments (///)
- Rationale for non-obvious logic in single-line comments (//)
- No comments for self-explanatory code

### Error Handling
- Use typed `ChoirError` enum cases
- Provide actionable error messages
- Validate input at boundaries only

### Concurrency
- Use `actor` for shared mutable state (AssetCache, ChoirEngine)
- Use `async/await` for async operations
- Mark closures `@Sendable` when crossing actor boundaries

## Performance Profiling

Key metrics to monitor:

1. **E2E Latency**: Text to audio output
2. **Throughput**: Characters per second
3. **Memory**: Peak allocation during synthesis
4. **Cache hit rate**: Percentage of re-used computations

Use Instruments (Xcode):
```bash
xcode-select --install  # If needed
instruments -t 'System Trace' <app>
```

## Dependencies & Constraints

### Required
- Swift 6.3+
- iOS 17+, macOS 14+, visionOS 1+, watchOS 10+, tvOS 17+

### Optional (for future features)
- Core ML (acoustic models)
- Audio Toolbox (AAC encoding)
- Accelerate framework (FFT operations)

### Constraints
- **No external HTTP dependencies** (offline-only)
- **No user data collection** (privacy-first)
- **Single-developer maintainability** (no exotic dependencies)

## Common Development Tasks

### Adding a Synthesis Parameter

1. Add field to `SynthesisParameters`:
```swift
public var newParam: Double = 0.5
```

2. Add clamping in init:
```swift
self.newParam = max(minVal, min(maxVal, newParam))
```

3. Use in `ProsodyPredictor`:
```swift
let adjusted = baseValue * (1.0 + synthesisParams.newParam)
```

4. Test with `SynthesisParameterTests`

### Debugging Synthesis

Record stage names, durations, counts, stable error codes, and model/engine
versions. Do not log user text at normal levels:

```swift
logger.debug("front-end complete: \(phonemeCount) phonemes")
logger.debug("prosody complete: \(durationMs) ms predicted")
logger.debug("audio complete: \(audio.frameCount) frames")
```

Developer-only text logging must be an explicit opt-in and disabled in release
builds. See the DocC **Responsible Use** article.

## Release Checklist

Before tagging a release:

- [ ] Follow every gate in the DocC **Maintenance Manual**.
- [ ] All tests and Release builds pass from a clean checkout.
- [ ] Production model/vocoder provenance and hashes are archived.
- [ ] Quality and performance reports cover every reference device.
- [ ] DocC builds without unresolved links or warnings.
- [ ] Known limitations and waivers are explicit.
- [ ] No warnings in build
- [ ] Updated version number
- [ ] Updated CHANGELOG
- [ ] Tested on all target platforms
- [ ] Performance within targets
- [ ] Memory leaks checked

## Resources

- [Apple Swift Concurrency Documentation](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency)
- [Core ML Guide](https://developer.apple.com/documentation/coreml)
- [Speech Synthesis Resources](https://en.wikipedia.org/wiki/Speech_synthesis)
- Internal SRS: See CHOIR — Software Requirements Specification v1.0.pdf

---

For questions or improvements, consult the git log and commit messages for historical context.
