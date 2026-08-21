# CHOIR project status

**Status:** Pre-alpha engineering infrastructure
**Package version:** 0.15.0
**Updated:** 21 August 2026

CHOIR is not currently a production text-to-speech engine. It contains a large
amount of useful Swift infrastructure, but the default synthesis path does not
produce speech.

## What works today

- Swift package structure and public types.
- Thirty-two stable `Voice` cases and detailed design profiles.
- A unique conditioning ID for every voice.
- Text normalization, a bundled CMUdict resource, curated pronunciation
  supplements, user-lexicon primitives, phonemization, and stress assignment.
- Sentence and breath-group segmentation.
- SSML-C parsing into events and styles.
- Prosody data structures and prediction infrastructure.
- Explicit plain-text, markup, and phoneme input modes at the front-end level.
- Batch orchestration and post-render chunk delivery.
- Timing metadata infrastructure.
- Validated 16-bit RIFF/WAV export and raw PCM encoding.
- Actor-based in-memory feature, transcription, and prosody caches.
- Cancellation checks and typed errors.
- Benchmark, intelligibility, and conformance harness infrastructure.
- A broad automated test suite for infrastructure behavior.

## What the default engine actually does

`ChoirEngine.initialize()` constructs a `SynthesisPipeline` backed by
`MockAcousticModel` and `MockVocoder` unless the caller injects a configured
pipeline. The mock acoustic model produces deterministic synthetic features.
The mock vocoder converts those features to a fixed test waveform. The result
is useful for exercising APIs but is not intelligible speech.

`CoreMLAcousticModel` validates its input and then reports
`ChoirError.modelLoadFailed` because no production model is bundled.

## Major incomplete product requirements

- No trained production acoustic model.
- No trained neural vocoder in the default path.
- No bundled production voice embedding or model asset for any voice.
- The 32 profiles are not yet 32 audible, perceptually distinct voices.
- Pitch, emotion, breathiness, age, gender, and voice-profile controls are not
  proven audible through production models.
- Chunk delivery starts only after the complete utterance has rendered.
- SSML styling is parsed, but several controls and break events are not fully
  executed through audio synthesis.
- MP3, AAC, FLAC, CAF, ALAC, and audiobook export are not implemented.
- Physical-device, thermal, battery, accessibility, and platform conformance
  remain unverified.
- Naturalness, cleanliness, intelligibility, voice distinctness, and listening
  fatigue gates have not been passed.
- The complete 239-requirement SRS has not passed a traceable release gate.

## Correctness work completed in the August 2026 sprint

- Canonicalized ASCII `g` to IPA U+0261 script-g across public phoneme input.
- Derived the model encoder vocabulary from `PhonemeInventory`.
- Added strict phoneme encoding and decoding APIs.
- Added validation for all parallel acoustic input tensors.
- Added finite-value, stress, voicing, duration, index, and voice-ID checks.
- Replaced four age-band model IDs with 32 stable voice conditioning IDs.
- Fixed a single explicit SSML voice run being discarded.
- Made mock acoustic output deterministic.
- Made missing Core ML assets report a model-load error rather than unknown.
- Added injectable pipelines to `ChoirEngine`.
- Added a distinct retryable `engineBusy` error.
- Validated streaming chunk sizes and checked cancellation between chunks.
- Avoided streaming chunk-offset integer overflow.
- Implemented `ChoirEngine.exportAudio(..., .wav)`.
- Made unavailable codecs throw rather than return empty files.
- Added WAV format, interleaving, bitrate, and RIFF-size validation.
- Made `clearCache()` release the initialized pipeline when idle.
- Corrected replacement size accounting in `AssetCache`.
- Enabled eviction for transcription-only and prosody-only caches.
- Prevented oversized entries from violating configured cache limits.
- Added cache capacity and emptiness statistics.
- Rewrote public streaming and getting-started documentation to match behavior.

## Build and test truth

GitHub Actions is the authoritative build result. The current work environment
does not include a Swift toolchain, so new changes must not be described as
compiled locally. A green infrastructure suite does not establish production
speech quality because the suite still runs primarily against mocks.

## Release rule

Do not describe CHOIR as production-ready, natural-sounding, neural,
real-time-streaming, or a 32-voice library until the relevant production models
exist and the corresponding objective and listening gates pass.

The next meaningful milestone is one intelligible production voice running
fully on-device through a real acoustic model and neural vocoder, with genuine
progressive streaming, WAV playback/export, and measured quality evidence.
