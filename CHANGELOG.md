# Changelog

All notable changes to CHOIR are recorded here. Versions follow Semantic
Versioning; the separate audio engine version remains unchanged unless seeded
audio output compatibility changes.

## Unreleased

### Added

- `choir-benchmark --say TEXT` renders text to a WAV file. The package had no
  way to produce an audio file from the command line, so the only evidence that
  any of it made sound was a unit test asserting a buffer was non-empty.
- `choir-benchmark --formant` runs either mode through the rule-based formant
  pipeline. `--intelligibility` previously always measured the mock pipeline,
  where the only possible result is a near-zero score against a 200 Hz tone, so
  QUA-004 could not be measured against the one path that produces speech.

- `Scripts/make_intelligibility_app.sh` builds a minimal app bundle around the
  benchmark tool so QUA-004 can be measured at all. Speech authorization needs
  `NSSpeechRecognitionUsageDescription` in an `Info.plist`, which a SwiftPM
  executable cannot have, and the bundle must be launched through LaunchServices
  or TCC attributes the request to the terminal and kills the process.
- `--intelligibility --output PATH` writes the report to a file. A run that can
  actually measure is launched by `open`, which discards stdout.
- `QUA004_FORMANT.md` records the first intelligibility measurement this project
  has ever had: 8.2% word accuracy for the formant path against a 98% target.

### Changed

- `AudioOutputFormat.isImplemented` and `.implemented`. Only WAV is actually
  implemented; MP3, AAC and FLAC throw. They threw clearly, but a caller had no
  way to find out except by attempting an export and catching the error. The
  errors now name `encodeWAV` as the alternative.
- `DocumentedFiguresTests` fails the build when a figure quoted in the
  documentation disagrees with the figure the code produces. It checks the
  library size, the theological lexicon size and the G2P accuracy, and it
  refuses the word "intelligible" near the formant path unless a measurement
  or a negation stands with it.

  This repository has lost the same fight three times: PROJECT_STATUS.md
  declared the project proprietary while LICENSE was MIT; seven files called
  the formant output intelligible with nothing behind the word; and the G2P
  figure lived in five documents that had to be hand-edited in step. The guard
  found two further unqualified claims that had already crept into
  REMAINING_WORK.md, which are corrected here.
- `G2PErrorAnalysis` reconstructs the edit-distance alignment and counts the
  actual phoneme confusions, so a systematic error appears as one large count
  rather than spread across every class containing it.
- R-coloured vowels: "er", "ir" and "ur" are one phoneme, /ɝ/. The rules
  dropped the vowel and kept the /r/ — 402 occurrences, 9.3% of all errors and
  the single most frequent substitution.
- `G2PDiagnostics` splits a TXT-020 evaluation by orthographic class, so a
  failing letter-to-sound rule appears as a failing row rather than as a
  fraction of one aggregate number. The aggregate said the fallback was wrong
  more often than right; it did not say which rule.
- Eight missing English vowel digraphs (`ea ee ie oa oo ou ue ei` and others).
  They fell through to the single-vowel path and spelled one vowel as two,
  which made this the worst-scoring class at 43.2%.
- Context-sensitive realization for word-final `-s` (/ɪz/, /s/, /z/ by
  preceding voicing), past-tense `-ed` (/ɪd/, /t/, /d/), `-tion`/`-sion`
  (/ʃən/, voiced to /ʒən/ after a vowel) and word-final `y`.

- `ChoirDemo` runs on the formant pipeline. Every demo previously built a
  default `ChoirEngine()`, so all nine of them demonstrated a 200 Hz test tone.
  The formant path needs no model, assets or download, so it costs nothing to
  use here. The library default is unchanged.
- Stops and fricatives no longer share one duration rule. Both were shortened
  as "obstruents", but they move in opposite directions: a stop is a closure
  plus a burst, while a fricative has to sustain turbulence long enough to be
  identified. At 40 ms an /s/ is a click. Sibilants are now longest, then other
  fricatives, then affricates; stops are unchanged.

  This did not move the QUA-004 score: 8.2% before and after. Individual
  sentences changed substantially in both directions and cancelled out, which
  says the bottleneck is formant transitions and coarticulation rather than
  segment length. Kept because it is phonetically correct, and recorded here so
  the next person does not re-run the same experiment.
- `Choir.engineVersion` is now 3. The duration change alters audio for identical
  seeded inputs, so caches written by 0.17.0 must not be reused (DST-001).

- Documentation no longer calls the formant output "intelligible". That was an
  unmeasured claim in seven places, and the measurement contradicts it. The
  output is described as speech-structured, with the number beside it.

- A silent `e` before a final `s` was pronounced. "makes" was /m eɪ k ɛ s/;
  the word-final rule could not see it because the `s` is final, not the `e`.
  This was the largest single source of inserted phonemes.
- A word-final silent `e` was pronounced. "hope" came out as /h oʊ p iː/: the
  `e` marks the preceding vowel long and is not itself a sound.
- Doubled consonants produced two phonemes. "hopping" had two /p/.

### Fixed

- `--intelligibility` no longer aborts with SIGABRT when speech authorization
  has not been granted. A SwiftPM executable has no Info.plist, so it cannot
  carry `NSSpeechRecognitionUsageDescription`, and requesting authorization
  without it is a TCC violation that kills the process rather than returning
  `.denied`. The harness is built to distinguish a failure to measure from a
  score of zero, and this defeated that on the most ordinary invocation. It now
  reports the recognizer as unavailable and explains what would make it
  measurable.

## 0.17.0 - 11 September 2026

### Added

- A rule-based formant synthesis path — `FormantAcousticModel`, `FormantVocoder`
  and `FormantTable` — reachable as `SynthesisPipeline.formant()`. It renders
  speech-structured, unmistakably synthetic audio with no trained model, no
  bundled voice assets and no recorded audio, so the front end, prosody, timing
  and output stages can be exercised against real speech structure instead of a
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
