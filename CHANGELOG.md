# Changelog

All notable changes to CHOIR are recorded here. Versions follow Semantic
Versioning; the separate audio engine version remains unchanged unless seeded
audio output compatibility changes.

## 0.17.0 - 11 September 2026

### Added

- A rule-based formant synthesis path — `FormantAcousticModel`, `FormantVocoder`
  and `FormantTable` — reachable as `SynthesisPipeline.formant()`. It renders
  intelligible, unmistakably synthetic speech with no trained model, no bundled
  voice assets and no recorded audio, so the front end, prosody, timing and
  output stages can be exercised against real speech structure instead of a
  test tone. It is a development and demonstration path, not a production
  voice: the SRS naturalness, distinctness and fatigue gates still require
  trained models.
- Formant targets for all 40 phonemes of `PhonemeInventory`, with per-voice
  vocal-tract scaling so that the 32 profiles render audibly differently.
- Deterministic on-device English NLP speech planning for utterance intent,
  restrained emotion, quoted dialogue, contrastive focus, nuclear stress, and
  syntactic clause boundaries.
- Typed `ContextualSpeechPlan`, `PlannedUtterance`, and `WordSpeechCue` APIs,
  with independently configurable detection capabilities and a literal-mode
  opt-out.
- Prosody realization of contextual plans through local duration, pitch,
  energy, pitch-accent, pause, and terminal boundary-tone changes.
- Focused NLP, front-end integration, prosody, configuration, and regression
  tests plus an integration guide.

### Changed

- `Choir.engineVersion` is now 2. The soft-clip fix below intentionally changes
  the audio produced by identical seeded inputs, so persistent synthesis caches
  written by 0.16.0 and earlier must not be reused (DST-001).

### Fixed

- `softClip` now bends only the overshoot above the knee, so the curve leaves
  the knee at the same value. It previously shaped the whole sample, which put
  a step of roughly 6,000 at the default threshold — audible distortion, and
  the opposite of what soft clipping is for. A threshold of exactly 1.0 now
  returns the buffer untouched instead of altering full-scale negative samples.
  Recovered from the unmerged Int16 narrowing sweep on
  `claude/last-thing-done-t48g2n`.
- `BenchmarkHarness` no longer requires Darwin, so the package builds and tests
  on Windows and Linux toolchains. Resident memory is read through Mach on
  Apple platforms and `K32GetProcessMemoryInfo` on Windows.

## 0.16.0 - 2026-08-21

### Added

- Fully specified phoneme-plus-prosody input that bypasses the linguistic front end.
- Request-complete and incremental word, phoneme, sentence, mark, parameter, and diagnostic metadata.
- Phrase-unit progressive streaming with synchronized metadata and cancellation boundaries.
- Caller-selectable structured-concurrency scheduling priority and model warm-up APIs.
- Native float PCM conversion, mastering, timeline/caption export, and enriched WAV metadata.
- Persistent content-addressed synthesis caching with SHA-256 keys, limits, LRU eviction, and pinning.
- Lazy asset lifecycle support for memory-pressure unload and transparent reload.
- Generated-Core-ML acoustic-model and vocoder adapters with tensor/output validation.
- Complete DocC foundation: API tiers, platform differences, integration recipes, SSML-C,
  phoneme reference, voice book, maintenance, accessibility, extension, and responsible-use guidance.
- Executable MOS, voice-distinctness, fatigue, long-form stability, source-security,
  documentation, and linguistic-front-end coverage gates.

### Changed

- Aligned public control envelopes with SRS v1.0: pitch `-6...6` semitones,
  rate `0.6...2.0`, and age/gender modifiers `-1...1`.
- Voice profiles now store pause style and articulation precision and feed them
  into prosody prediction.
- Spectral fallback reconstruction is deterministic and uses an O(n log n)
  inverse transform with precomputed overlap windows.
- Debug CI builds treat warnings as errors and enforce at least 85% line
  coverage for the linguistic front end.

### Known release blockers

- The repository still needs licensed trained acoustic-model and neural-vocoder
  checkpoints plus their voice embeddings; the default test engine remains mock-backed.
- Device, battery, thermal, App Store, MOS, intelligibility, long-form, and
  listener-fatigue gates require external hardware/assets/human evidence before
  a production release can be declared.
- CAF, AAC, and ALAC export still require implementation; spatial,
  background-execution, watchOS, and downloadable-asset paths require final
  validation in signed consuming applications.
