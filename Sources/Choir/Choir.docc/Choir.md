# ``Choir``

An on-device text-to-speech engine for the Apple ecosystem, with no network
dependency.

## Overview

CHOIR is designed for entirely on-device synthesis across Apple platforms from
a single Swift package.

> Important: CHOIR is pre-alpha software (0.15.0). The default pipeline uses
> `MockAcousticModel` and `MockVocoder`, so it emits a test waveform rather than
> speech. The 32 voices are metadata profiles with unique conditioning IDs,
> not trained voices. Treat this as development infrastructure rather than a
> replacement for `AVSpeechSynthesizer`.

### Synthesizing speech

Create an engine, initialize it once, then synthesize:

```swift
import Choir

let engine = ChoirEngine()
try await engine.initialize()

let audio = try await engine.synthesize(
    text: "Hello, world!",
    voice: .isla,
    parameters: SynthesisParameters(rate: 0.95, emotionalIntensity: 0.7)
)
```

The current API can deliver a completed render in chunks. It does not yet emit
audio while later text is still being synthesized:

```swift
try await engine.streamSynthesis(
    text: "Deliver this render in chunks...",
    voice: .orion,
    options: StreamingOptions(),
    onChunk: { chunk in
        // Feed chunk.samples to your audio output
    }
)
```

### Shaping the voice

``SynthesisParameters`` exposes pitch, rate, emotional intensity, breathiness,
and age and gender shifting. ``SpeakingStyle`` bundles these into presets such
as `.whisper`, `.happy` and `.calm`. ``VoiceBlending`` interpolates between two
voice profiles, which is useful for character morphing.

### Pipeline

Text passes through ``LinguisticFrontend`` for normalization, grapheme-to-phoneme
conversion, stress assignment and SSML parsing; then ``ProsodyPredictor`` and
``ToBI`` for timing and intonation; then the acoustic model and vocoder; and
finally ``AudioFilters`` and ``AudioEncoder`` for post-processing and export.

## Topics

### Essentials

- ``ChoirEngine``
- ``Voice``
- ``SynthesisParameters``
- ``ChoirError``

### Expression

- ``SpeakingStyle``
- ``VoiceBlending``
- ``ToBI``
- ``ToBIPredictor``

### Text processing

- ``LinguisticFrontend``
- ``TextNormalizer``
- ``Phonemizer``
- ``StressAssigner``
- ``SSMLCParser``
- ``PronunciationDictionary``
- ``Phoneme``
- ``PhoneticTranscription``

### Prosody

- ``ProsodyPredictor``
- ``ProsodyFeatures``
- ``ProsodyContour``

### Audio output

- ``AudioBuffer``
- ``AudioFormat``
- ``AudioEncoder``
- ``AudioFilters``
- ``AudioEffect``
- ``AudioEffectChain``
- ``VoiceQualityAnalyzer``

### Streaming

- ``StreamingOptions``
- ``AudioChunk``
- ``StreamingSynthesisPipeline``
- ``RealTimeController``
- ``SynthesisSession``

### Sample-based synthesis

- ``VoiceSampleLibrary``
- ``PhonemeSample``
- ``SampleBasedSynthesizer``

### Models and caching

- ``AcousticModelProtocol``
- ``VocoderProtocol``
- ``AssetCache``
