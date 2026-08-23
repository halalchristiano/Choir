# CHOIR project status

**Status:** Pre-alpha engineering infrastructure
**Package version:** 0.16.0
**Updated:** 22 August 2026

CHOIR is not currently a production text-to-speech engine. It contains a large
amount of useful Swift infrastructure, but the default synthesis path does not
produce speech.

## What works today

- Swift package structure and public types.
- Thirty-two stable `Voice` cases and detailed design profiles.
- A unique conditioning ID for every voice.
- Text normalization, a bundled CMUdict resource, curated pronunciation
  supplements, user-lexicon primitives, phonemization, and stress assignment.
- Deterministic on-device English speech planning for intent, restrained
  emotion, quoted dialogue, contrastive emphasis, and clause boundaries, with
  typed cues consumed by duration, pitch, energy, accent, pause, and terminal
  boundary-tone prediction.
- Sentence and breath-group segmentation.
- SSML-C parsing into events and styles.
- Prosody data structures and prediction infrastructure.
- Explicit plain-text, markup, and phoneme input modes at the front-end level.
- Batch orchestration and phrase-progressive PCM/timing delivery.
- Word, phoneme, sentence, mark, and incremental timing infrastructure.
- Validated RIFF/WAV and raw PCM, float conversion/mastering primitives, and
  per-line timing/SRT/WebVTT export.
- In-memory caches plus a persistent SHA-256 synthesis-cache primitive with
  limits, LRU eviction, pinning, inspection, and purge.
- Cancellation checks and typed errors.
- Benchmark, intelligibility, and conformance harness infrastructure.
- A broad automated test suite for infrastructure behavior.

## What the default engine actually does

`ChoirEngine.initialize()` constructs a `SynthesisPipeline` backed by
`MockAcousticModel` and `MockVocoder` unless the caller injects a configured
pipeline. The mock acoustic model produces deterministic synthetic features.
The mock vocoder converts those features to a fixed test waveform. The result
is useful for exercising APIs but is not intelligible speech.

`CoreMLAcousticModel` and `CoreMLVocoder` validate caller-injected inference
closures. The acoustic adapter's default form reports that no production model
is bundled; the vocoder adapter requires an inference closure.

## Reconciled 143-item carried backlog

The authoritative item-by-item ledger is in
[`SRS_CONFORMANCE.md`](./SRS_CONFORMANCE.md). Its current source-level
classification is:

| Status | Count |
|---|---:|
| Implemented | 23 |
| Partial | 55 |
| Open | 28 |
| External acceptance gate | 37 |
| **Still incomplete or externally gated** | **120** |
| **Total reconciled items** | **143** |

“Implemented” means the requested repository code/document deliverable exists;
it does not convert a mock-backed feature into production speech or waive an
acoustic, listening, hardware, signing, or App Store gate.

## Major incomplete product requirements

- No trained production acoustic model.
- No trained neural vocoder in the default path.
- No bundled production voice embedding or model asset for any voice.
- The 32 profiles are not yet 32 audible, perceptually distinct voices.
- Pitch, emotion, breathiness, age, gender, and voice-profile controls are not
  proven audible through production models.
- Production-model TTFA, real-time factor, clickless joins, and long-form memory
  behavior remain unmeasured even though phrase-progressive orchestration exists.
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
- Added bounded pull-based streaming with cancellation ownership and a
  source-compatible fail-fast `AsyncThrowingStream` adapter.
- Preserved clamping reports through request validation and Codable round trips.
- Made normalized mark/sentence provenance drive timing metadata.
- Hardened acoustic/vocoder allocation arithmetic and long expert timing.
- Fixed lazy-asset stale-load, warm-up coalescing, dialogue-timeline, cache-key,
  stereo DSP, playback-lifetime, and cache-startup regressions.

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
