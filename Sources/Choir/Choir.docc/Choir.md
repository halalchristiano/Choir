# ``Choir``

An on-device text-to-speech engine for the Apple ecosystem, with no network
dependency.

## Overview

CHOIR synthesizes speech entirely on-device across iOS, iPadOS, macOS,
visionOS, watchOS and tvOS from a single Swift package. It makes no network
calls, so it behaves identically offline.

> Important: CHOIR is pre-release software (0.2.0). The architecture, API
> surface and linguistic pipeline are implemented and usable, but the acoustic
> model is a mock and the vocoder is Griffin-Lim, so the engine does not yet
> produce natural-sounding speech on its own. The 32 voices are parameter
> profiles rather than trained models; voice timbre comes from either trained
> acoustic models, which are not included, or from user-supplied phoneme
> recordings. Treat this as a foundation to build on rather than a drop-in
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

For real-time playback, stream chunks as they are produced instead of waiting
for the whole utterance:

```swift
try await engine.streamSynthesis(
    text: "Speaking in real-time...",
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
