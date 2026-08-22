# SRS Conformance Report

Traceability between [CHOIR — Software Requirements Specification v1.0](./CHOIR%20—%20Software%20Requirements%20Specification%20v1.0.pdf)
and the implementation, plus defects found in the specification itself while
implementing Part II.

Source-level traceability is partially exercised by
`Tests/ChoirTests/SRSConformanceTests.swift` and the requirement-focused suites.
Those tests do not substitute for the production-model, listening, hardware,
signing, or release gates recorded below.

---

## 2026-08-22 reconciliation of the 143-item carried backlog

This section is the authoritative reconciliation of the 136 items previously
reported as remaining plus seven mandatory failures found in the subsequent
acceptance review. It supersedes an older status anywhere below when the two
conflict. The list is intentionally not a claim that a mock, test helper, or
documentation page satisfies an acoustic, listening, hardware, signing, App
Store, or production-model acceptance gate.

Latest published source evidence: [CI run 44](https://github.com/halalchristiano/Choir/actions/runs/32551225065)
passed 780 tests in 90 suites, the debug and release builds, all configured
Apple-platform builds, and the 94.97% linguistic-front-end coverage gate.

Status meanings:

- **Implemented** — the repository now contains the requested code or document
  deliverable and regression evidence; the published CI run is still the build
  authority because this work environment has no Swift toolchain.
- **Partial** — a useful primitive, code path, document, or harness exists, but
  at least one material clause or integration is still missing.
- **Open** — the requested product capability is not implemented.
- **External gate** — completion requires trained/licensed artifacts, listening
  evidence, Apple hardware, signing/App Store validation, or a release process
  that cannot truthfully be manufactured in a source-only patch.

### The 100 items that lacked formal implementation/test evidence

| ID | P | Status | Requirement and remaining evidence/work |
|---|---|---|---|
| `ACC-001` | M | Open | Make playback coexist with VoiceOver and system speech; audio-session policy and physical-device interruption tests remain. |
| `ACC-002` | S | Implemented | Accessible highlighting and caption-export workflows are documented in the DocC accessibility guide. |
| `AUD-001` | M | Partial | Float32 buffer, array, and little-endian `Data` conversion surfaces exist, but the native engine/vocoder result is still int16 rather than 48 kHz mono float32. |
| `AUD-002` | M | Implemented | 44.1/24/16 kHz and dithered int16 conversion are implemented; the 385-tap converter has a regression proving at least 100 dB rejection in the 48→16 kHz alias band. |
| `AUD-010` | M | Partial | Validated WAV exists; CAF, AAC, and ALAC export still need real container/codec implementations. |
| `AUD-011` | M | Partial | WAV metadata, title/voice fields, and chapter cues exist; equivalent metadata for every required format remains. |
| `AUD-012` | M | Open | Resumable, verified multi-chapter M4B audiobook assembly is not implemented. |
| `AUD-020` | M | Partial | LUFS normalization and true-peak limiting primitives exist but are not yet the mandatory all-voice output stage or production-voice proof. |
| `AUD-021` | M | Partial | DC removal and clickless-edge primitives exist; integration and all-voice limits remain unproved. |
| `AUD-022` | S | Implemented | The opt-in broadcast chain is integrated into engine and result export APIs, adapts to the output sample rate, and is covered by export-level tests. |
| `AUD-030` | M | Partial | One-call synthesis/playback now retains the player and propagates completion/errors; pause, resume, stop, and seek controls remain. |
| `AUD-031` | S | Partial | Progressive synthesis carries synchronized word/phoneme/mark timing, but playback-time observation events are not exposed by `Choir.play`. |
| `AUD-040` | S | Implemented | Per-line WAV, timing JSON, SRT, and WebVTT export uses validated word timing to derive caption cues. |
| `CCH-001` | M | Partial | Stable SHA-256 synthesis keys and persistent audio storage exist; the cache is not yet wired into every engine synthesis path. |
| `CCH-002` | M | Implemented | Configurable limits, coordinated cross-actor LRU eviction, pinning, inspection, purge, and orphan cleanup are implemented and tested against a shared directory. |
| `CCH-003` | M | Implemented | Platform cache/application-support defaults and version-independent compatible cache records are implemented. |
| `CCH-010` | M | Open | Embedded/resumable downloaded asset packs with SHA-256 verification are not implemented. |
| `CCH-011` | M | Partial | A coalescing lazy asset store handles unload/reload and stale-load races; production model assets and OS memory-pressure integration remain. |
| `CCH-012` | S | Open | Persistent background batch rendering through `BGProcessingTask` is not implemented. |
| `DOC-001` | M | Partial | The DocC catalog, quick start, API-tier guide, and integration recipes exist; every public symbol is not yet documented. |
| `DOC-002` | M | Partial | All 32 voice profile pages exist; a complete auditionable Voice Book still needs production audio. |
| `DOC-003` | M | Implemented | The SSML-C reference documents the dialect, examples, degradation, and unsupported syntax. |
| `DOC-004` | M | Partial | The phoneme inventory is published; production-voice audio examples remain unavailable. |
| `DOC-005` | M | Partial | A maintenance manual exists, but real training/conversion data, commands, and reproducible production releases do not. |
| `DOC-006` | S | Implemented | A printable API and voice-ID cheat sheet is present. |
| `DST-001` | M | Implemented | Semantic package version and separate engine-output version are exposed. |
| `DST-002` | M | External gate | Seeded stability cannot be guaranteed until production weights and golden production audio exist. |
| `DST-003` | M | Partial | Source and current resources are versioned; licensed datasets, training runs, and production models required for a full rebuild are absent. |
| `DST-004` | S | Implemented | Non-breaking extension paths for voices, languages, and emotions are documented. |
| `DST-005` | M | Partial | The release manual records Apple beta/deprecation checks; an annual executed and archived process remains a release gate. |
| `INT-001` | M | Open | There is no single-call verse-addressed synthesis API returning verse timing. |
| `INT-002` | M | Partial | Scripture normalization is substantial; the complete archaic/divine-name pronunciation policy and audit remain. |
| `INT-003` | S | Implemented | Bible chapter pre-rendering and cache-pinning workflow is documented. |
| `INT-004` | S | Implemented | Long-form corpus narration and footnote-handling guidance is documented with current limitations. |
| `INT-010` | M | Open | A resumable 150,000-word document-to-audiobook job controller is not implemented. |
| `INT-011` | S | Implemented | Heading, quotation, and footnote markup conversion is documented. |
| `INT-020` | M | Open | Low-latency interruptible spatial NPC dialogue is not implemented. |
| `INT-021` | S | Implemented | A reference IPA-to-viseme mapping and coarticulation guidance are published. |
| `INT-030` | M | Partial | Deterministic seeded rendering and audio/timing/subtitle bundles exist; the complete script-to-multiple-takes workflow does not. |
| `INT-040` | M | Open | No complete showcase app demonstrates the product solely through public API. |
| `LOC-001` | M | Open | Selectable American and British realization for all voices requires trained accent conditioning. |
| `LOC-002` | M | Partial | Extension points are documented, but no second language has proved the architecture end to end. |
| `LOC-003` | S | Partial | User lexicons and phoneme markup can carry foreign names; supported embedded-language behavior is not validated. |
| `ML-A-001` | M | External gate | The real multi-voice acoustic model must be trained and supplied. |
| `ML-A-002` | M | External gate | Runtime controls reach the conditioning contract, but trained weights must prove every continuous control is learned. |
| `ML-A-003` | M | External gate | Stable 32-way conditioning IDs exist; a trained structured age/gender embedding space does not. |
| `ML-A-004` | M | External gate | Licensed training data and complete provenance must be acquired and archived. |
| `ML-A-005` | M | External gate | A from-scratch production training pipeline and run artifacts do not exist. |
| `ML-A-006` | S | Partial | Expert duration/pitch tensors reach inference; teacher-forced support in a real model/training pipeline remains. |
| `ML-C-001` | M | External gate | Core ML adapter contracts exist, but no runtime network ships as a production `mlprogram`. |
| `ML-C-002` | M | External gate | Quantized production models and an accepted quality-delta study are absent. |
| `ML-C-003` | M | External gate | Production conversion and traceability to a real training run are absent. |
| `ML-C-004` | S | Partial | Compute-unit selection/override can be represented by an injected implementation; automatic policy and device tests remain. |
| `ML-V-001` | M | External gate | No real 48 kHz neural vocoder meeting the quality gates is bundled. |
| `ML-V-002` | M | External gate | Production vocoder lookahead at or below 100 ms is unmeasured. |
| `ML-V-003` | M | External gate | Preservation of breath, rasp, elderly, and villain texture requires the production vocoder and listening evidence. |
| `PLT-031` | S | Open | Paired-iPhone assistance for Apple Watch full-library synthesis is not implemented. |
| `PRO-001` | M | Partial | Semitone control now scales the entire F0 contour; artifact-free formant-preserving production audio across ±6 st is unproved. |
| `PRO-002` | M | Partial | Duration-aware 0.6×–2.0× control reaches prosody/model inputs; natural production output is unproved. |
| `PRO-003` | M | Partial | Emotion intensity changes prosody and reaches model conditioning; trained timbre effects are absent. |
| `PRO-004` | M | Partial | Breathiness is continuous conditioning and optional mastering infrastructure exists; genuine breaths require a trained model. |
| `PRO-005` | M | Partial | Gain/compression DSP exists, but independent synthesis controls and end-to-end integration remain. |
| `PRO-006` | M | Partial | Age/gender shifts affect F0 and reach conditioning; real formant/timbre shifts require trained weights. |
| `PRO-010` | M | External gate | Eight labels/infrastructure are insufficient; eight genuine styles for every production voice need model and listening proof. |
| `PRO-011` | S | Open | Smooth sub-sentence emotion-style changes are not implemented. |
| `PRO-020` | M | Partial | Emphasis changes lexical stress; genuine acoustic accenting remains a production-model gate. |
| `PRO-021` | M | Open | Breaks parse but are not yet rendered as sample-accurate pauses in ordinary synthesis. |
| `PRO-022` | S | Partial | Punctuation informs phrase prosody; a voice-specific production treatment and off switch remain. |
| `PRO-030` | M | Partial | Global control envelopes are clamped and reported; voice-specific safe envelopes still need production validation and publication. |
| `QUA-001` | M | External gate | Naturalness ≥4.2 and cleanliness ≥4.5 MOS require production audio and blinded listening. |
| `QUA-002` | M | External gate | Zero audible artifacts on the standard corpus requires production audio and archived evaluation. |
| `QUA-005` | M | External gate | 60-minute loudness, tempo, and timbre stability requires production voices and device runs. |
| `QUA-006` | M | External gate | The 300-name audited pronunciation gate has not been executed with production audio. |
| `QUA-007` | S | External gate | The structured 30-minute listener-fatigue study has not been run. |
| `SEC-002` | M | Implemented | The package contains no analytics/identifier upload path; caller-controlled local caches are the only persistence primitive. |
| `SEC-003` | M | Partial | SHA-256/cache integrity primitives and typed failures exist; production model manifests and load-time verification remain. |
| `SEC-004` | M | Implemented | Normal runtime paths do not log caller text; privacy-safe diagnostics carry structural messages. |
| `SEC-005` | M | Implemented | No speaker encoder, enrollment, adaptation, or real-person cloning path ships. |
| `SEC-006` | S | Implemented | Responsible-use and synthetic-voice disclosure guidance is published. |
| `SPA-002` | M | Open | Six head-tracked Vision Pro speakers with ≥30 Hz updates are not implemented. |
| `SPA-003` | S | Open | Direct RealityKit entity binding is not implemented. |
| `STR-001` | M | Implemented | The pipeline performs acoustic/vocoder work per natural unit and delivers PCM before rendering later units. |
| `STR-002` | M | Partial | Batch/stream share unit rendering and seeded simple-text samples; production clickless/gapless/level joins remain unproved. |
| `STR-003` | M | External gate | Production real-time factor and safe quality degradation require real models and device benchmarks. |
| `STR-004` | M | Implemented | Word and phoneme timing updates stream beside channel-aligned PCM. |
| `STR-005` | M | Partial | Cancellation is checked through the pipeline and early sequence exit cancels the producer; sentence-boundary parameter changes remain. |
| `STR-006` | S | Partial | A bounded multi-voice dialogue queue streams one timeline with chunked gaps; production gapless switch joins remain unproved. |
| `STR-007` | S | Open | Direct `AVAudioEngine` source-node playback is not implemented. |
| `SYN-001` | M | External gate | The text/prosody interfaces exist, but the default acoustic model and vocoder remain mock-backed. |
| `SYN-004` | M | Partial | Simple seeded batch/stream paths are sample-identical; full SSML and voice-switch streaming equivalence remains. |
| `SYN-006` | M | Implemented | FIFO permits admit at least two independently cancellable jobs. |
| `SYN-009` | S | Partial | Explicit warm-up exists; production model preload/graph warm-up awaits real assets. |
| `TST-001` | M | Partial | Linguistic tests and a CI coverage gate exist; the authoritative published coverage result must be green. |
| `TST-002` | M | Open | At least 200 seeded golden-audio regressions across real voices do not exist. |
| `TST-003` | M | External gate | Every release candidate still needs all gates executed and archived. |
| `TST-004` | M | External gate | Every reference Apple device must be benchmarked for each release. |
| `TST-005` | M | External gate | iOS, macOS, watchOS, and visionOS integration matrices require Apple hardware/CI. |
| `TST-007` | M | Partial | Source auditing rejects network APIs/tokens; a runtime socket-open proof in an embedded app remains. |
| `TST-008` | S | Open | The two-hour concurrency/cancellation/memory/thermal soak has not been implemented or run. |
| `TST-010` | M | Partial | Listening-test structures and guidance exist; the blinded MOS protocol must be frozen and executed against production audio. |

### The 34 items explicitly recorded as unresolved

| ID | P | Status | Requirement and remaining evidence/work |
|---|---|---|---|
| `API-001` | M | Partial | Tier 1 one-call synthesis/playback, Tier 2 requests/results, and Tier 3 explicit input/streaming surfaces exist; full contour/cache/asset management and multi-voice streaming behavior remain incomplete. |
| `API-005` | M | Partial | DocC guides cover major APIs; every public symbol is not yet documented. |
| `API-007` | S | Open | SwiftUI convenience components are not shipped. |
| `CON-001` | M | Partial | Heavy work is async/priority-scheduled; the ≤1 ms main-thread blocking acceptance measurement remains. |
| `CON-004` | M | Implemented | Caller-controlled QoS intent maps to structured task priorities. |
| `CON-005` | M | Partial | Lazy unload/reload is race-safe, but `ChoirEngine` is not wired to OS pressure and production asset restoration. |
| `PKG-002` | M | Open | The package is not split into the required public/core/asset/spatial modules. |
| `PKG-006` | S | Open | A signed XCFramework distribution is not produced. |
| `PLT-001` | M | External gate | Consistent iOS/iPadOS/macOS/visionOS behavior requires integration runs on all targets. |
| `PLT-002` | M | External gate | Seeded cross-platform production-audio parity below −60 dB is unmeasured. |
| `PLT-003` | M | External gate | A14/M-series support and a formal Intel decision require builds and benchmarks on reference hardware. |
| `PLT-010` | M | Open | The complete iPhone/iPad application feature set is not delivered. |
| `PLT-011` | M | Open | Interruption, route-change, and background playback handling are not implemented. |
| `PLT-012` | S | Open | Thermal monitoring and efficient-vocoder fallback are not implemented. |
| `PLT-020` | M | Open | Full macOS product behavior, CLI, and four-job batch proof are not delivered. |
| `PLT-021` | S | Open | `choir-cli` is not shipped. |
| `PLT-030` | M | Open | The documented watchOS subset with four validated voices is not delivered. |
| `PRF-010` | M | External gate | Warm TTFA limits require production assets and reference-device measurements. |
| `PRF-020` | M | External gate | Peak-memory limits require production assets and device measurements. |
| `PRF-021` | M | External gate | One-hour iPhone battery use requires a production build and physical-device run. |
| `QUA-004` | M | External gate | ≥98% default and ≥96% envelope-corner ASR accuracy requires production audio; current rule G2P also remains below target. |
| `REL-004` | M | Partial | Fuzz/robustness tests exist and known traps were fixed; the release fuzz gate and zero-reproducible-crash archive remain. |
| `REL-005` | S | Partial | Typed privacy-safe diagnostics exist; a complete opt-in structured logging facility does not. |
| `SPA-001` | M | Open | The `SpatialSpeaker` playback layer is not implemented. |
| `SPA-005` | M | Open | An optional `CHOIRSpatial` module does not exist. |
| `TXT-020` | M | Partial | The lexicon has 126,052 indexed word forms, but measured held-out OOV phoneme accuracy is 54.2% against 92%. |
| `TXT-023` | S | Partial | The theological/biblical supplement has 196 curated entries against 2,500. |
| `VOX-G-003` | M | External gate | ≥90% perceptual distinctness needs 32 production voices and an ABX study. |
| `VOX-G-006` | M | External gate | Stable conditioning IDs exist, but shared production model weights do not. |
| `VOX-G-007` | M | External gate | Envelope usability needs trained voices and intelligibility/listening tests. |
| `VOX-G-008` | S | Partial | Three scripts per voice are documented; production audio demonstrations are absent. |
| `VOX-P-007` | M | Partial | Continuous age/gender values alter F0 and reach model inputs; trained formant/timbre shifting is absent. |
| `VOX-V-003` | M | External gate | Convincing neutral/warm villain delivery requires production voices and listening evidence. |
| `VOX-V-004` | S | Partial | Menace guidance/profile data exist; a voice-specific acoustic implementation is not proved. |

### The two items that were falsely marked complete

| ID | P | Status | Requirement and remaining evidence/work |
|---|---|---|---|
| `TXT-050` | S | Implemented | Explicit phoneme-plus-prosody input bypasses the text front end, validates aligned tensors, partitions long timing safely, and reaches model inference. |
| `SYN-005` | M | Partial | Results provide normalized word/phoneme/sentence/mark timing aligned to rendered duration; full multi-voice/stream equivalence still needs correction. |

### Seven additional mandatory failures from acceptance review

| ID | P | Status | Requirement and remaining evidence/work |
|---|---|---|---|
| `VOX-P-001` | M | Partial | Every profile parameter is stored and pause/articulation affect timing, but all profile controls do not yet condition the production model. |
| `PKG-007` | M | External gate | App Store compliance must be proved in a signed embedded shipping application. |
| `PRF-001` | M | External gate | Batch RTF ≤0.35 on iPhone 13 and ≤0.15 on M2+ needs production models and hardware. |
| `PRF-011` | M | External gate | Cold-start ≤3 s/≤1.5 s needs production assets and hardware measurements. |
| `PRF-030` | M | Partial | A reproducible asset-size harness exists; the 400 MB product limit cannot be accepted without production model/voice/vocoder assets. |
| `PRF-032` | M | Partial | The current source subset is below 60 MB; the real watchOS asset subset does not yet exist. |
| `PRF-040` | M | Partial | The benchmark harness and reference-device manifest exist; complete reproducible runs on every physical reference device remain. |

The actionable interpretation is deliberately strict: source work can close
the **Implemented** rows, while **Partial**, **Open**, and **External gate** rows
remain product backlog until every clause and its acceptance evidence exist.

## Part II — The Voice Library

| Requirement | Priority | Status | Verified by |
|---|---|---|---|
| `VOX-G-001` 32 voices, 4 bands x 2 genders x 4, 1 villain per cell | MUST | Implemented | `testVoiceCount`, `testCellStructure`, `testCellsPartitionLibrary` |
| `VOX-G-002` original synthetic designs, no real-person imitation | MUST | Satisfied by design | No speaker-encoder path exists |
| `VOX-G-003` perceptual distinctness, ≥90% ABX | MUST | **Not verifiable yet** | Requires trained models and a listening test |
| `VOX-G-004` immutable metadata per voice | MUST | Implemented | `testMetadataCompleteness`, `testIdentifierShape` |
| `VOX-G-005` permanent identifiers | MUST | Implemented | `testIdentifierUniqueness`, `testRawValueIsIdentifier` |
| `VOX-G-006` shared acoustic model via conditioning | MUST | **Not implemented** | Blocked on the acoustic model |
| `VOX-G-007` intelligible across customization envelope | MUST | **Harness ready** | `IntelligibilityHarness.evaluateEnvelopeCorners`; awaits a trained model |
| `VOX-G-008` three demo passages per voice | SHOULD | **Not implemented** | — |
| `VOX-G-009` voice designer API | MAY | Partial | `VoiceBlending` interpolates profiles |
| `VOX-G-010` child voices are stylized characters | MUST | Satisfied by design | `testChildVillainsRemainChildlike` |
| `VOX-P-001` full designed parameter set stored and honored | MUST | **Partial** | Storage/pause/articulation are tested; all profile values do not yet reach model conditioning |
| `VOX-P-002` child realization | MUST | Implemented | `testChildRealization` |
| `VOX-P-003` young adult realization | MUST | Implemented | `testYoungAdultRealization` |
| `VOX-P-004` middle-aged realization | MUST | Implemented | `testMiddleAgedRealization` |
| `VOX-P-005` elderly realization | MUST | Implemented | `testElderlyRealization`, `testElderlyRoughness` |
| `VOX-P-006` gender via F0 *and* formant scale | MUST | Implemented, **amended by [`AMD-001`](./SRS_AMENDMENTS.md)** | `testGenderDirection`, `testGenderSeparationByBand`, `testChildBandFormantSeparation`, `testChildGenderCarriedByF0` |
| `VOX-P-007` ageShift / genderShift modifiers | MUST | Partial | `testAgeBandOrdering`; runtime modifiers exist, safe ranges undocumented |
| `VOX-08-01` … `VOX-08-32` the 32 binding profiles | MUST | Implemented | Values transcribed from §8 and machine-generated |
| `VOX-V-001` exactly eight named villains | MUST | Implemented | `testVillainRoster` |
| `VOX-V-002` menace via prosody, never distortion | MUST | Implemented | `testVillainProsodicDesign` |
| `VOX-V-003` villains capable of neutral delivery | MUST | **Not verifiable yet** | Requires synthesis |
| `VOX-V-004` documented `menace` emphasis behaviour | SHOULD | **Not implemented** | — |
| `VOX-V-005` child villains unsettle by prosody alone | MUST | Implemented | `testChildVillainsRemainChildlike` |

`VOX-P-001` requires nine designed parameters. Seven are quantified per voice in
§8 and are transcribed exactly. Spectral tilt is specified qualitatively
("dark-mellow", "bright with hollowed mids"); the descriptor is preserved
verbatim in `spectralTiltDescription` and a numeric dB/octave mapping is
supplied as a developer decision under §1.1. Pause style and articulation
precision are not quantified per voice in §8; the repository records explicit
designer defaults and uses them in structural timing, pending production-model
validation.

---

## Part III — Functional Requirements

| Requirement | Priority | Status | Verified by |
|---|---|---|---|
| `TXT-001` accept 1 … 1,000,000 characters | MUST | **Fixed** | The engine capped input at 5,000 characters — see below |
| `TXT-002` never crash, hang, or produce unbounded output | MUST | **Implemented — was violated** | `testNormalizerRobustness`, `testFrontendRobustness` (29 adversarial inputs) |
| `TXT-003` input mode selected explicitly, never guessed | MUST | Implemented | 7 tests in `InputModeTests` — `SynthesisInput` with plain-text, markup and phoneme modes |
| `TXT-010` full normalization inventory | MUST | Implemented | 19 tests in `NormalizationInventoryTests` — every named category |
| `TXT-011` Scripture reference formats | MUST | Implemented | 14 tests in `ScriptureNormalizationTests` |
| `TXT-012` configurable `NormalizationPolicy` | SHOULD | Implemented | `testConfigurableStyle`, `testCanBeDisabled`, `testVerbatimMode` |
| `TXT-013` typography (smart quotes, dashes, ellipses, caps) | SHOULD | Implemented | 4 tests in `AllCapsTests` plus typography coverage in `NormalizationInventoryTests` |
| `TXT-020` 120,000-word lexicon, ≥92% OOV accuracy | MUST | **Partial — now measured** | Lexicon indexes 126,052 distinct forms. OOV accuracy **measured at 54.2%** against a 92% target; see below |
| `TXT-021` ≥60 heteronyms disambiguated by part of speech | MUST | Implemented | 79 heteronyms, 7 tests in `HeteronymTests` |
| `TXT-022` runtime user lexicon API | MUST | Implemented | 9 tests in `UserLexiconTests` |
| `TXT-023` biblical/theological proper-noun supplement (≥2,500) | SHOULD | **Partial** | 196 curated entries against a target of 2,500 |
| `TXT-024` documented, stable phoneme inventory | MUST | Implemented | 39 phonemes, ARPAbet↔IPA, 8 tests in `PhonemeInventoryTests` |
| `TXT-030` sentence and phrase segmentation | MUST | Implemented | 10 tests in `SegmentationTests` — abbreviations, initials, decimals, dialogue punctuation, `PhraseBoundary` strength |
| `TXT-031` breath groups for long sentences | MUST | Implemented | 9 tests in `BreathGroupTests` — word cap and duration ceiling |
| `TXT-032` paragraph/section pauses and pitch reset | SHOULD | Implemented | Boundaries reach the transcription and the prosody model lengthens pauses and resets pitch; 7 tests in `StructuralProsodyTests` |
| `TXT-040` SSML-C dialect | MUST | **Partial** | All seven tags parse, but pauses and several acoustic styles are not fully rendered |
| `TXT-041` graceful degradation + markup diagnostics | MUST | Implemented | 9 tests in `SSMLDegradationTests` — degradation, diagnostics, strict mode |
| `TXT-042` `<voice>` mid-text switching | MUST | **Partial** | Batch voice runs switch IDs, but style preservation, clickless joins, and streaming parity remain |
| `TXT-050` pre-phonemized input path | SHOULD | Implemented | `SynthesisInput.phonemes`, validated against the inventory |
| `SYN-002` deterministic output given a seed | MUST | Implemented | 8 tests in `DeterminismTests` |
| `SYN-003` controlled variation without a seed | MUST | Implemented | `testUnseededVaries`, `testVariationBounded` — **was violated**: every render was bit-identical |
| `SYN-005` timing metadata (per word/phoneme, marks) | MUST | **Partial** | Structures, normalized mark provenance, and audio-duration alignment exist; full multi-voice/stream parity remains |
| `SYN-008` failures surface as typed errors, never traps | MUST | Implemented | `testFrontendRobustness`; 16 traps fixed across 0.2.x–0.3.x |
| `SYN-010` duration estimate API | SHOULD | Implemented | 7 tests in `DurationEstimateTests` |

`TXT-022` is implemented as an actor with a replaceable persistence store,
defaulting to `UserDefaults`. Registrations take precedence over the built-in
lexicon and are resolved through an immutable snapshot taken once per synthesis
request, so the synchronous per-word phonemization path never awaits.

`SYN-005` currently returns total duration, per-word and per-phoneme spans, sentence
ranges, the effective parameter set and the voice, with `word(at:)` and
`phoneme(at:)` queries for verse highlighting and lip-sync. Timings derive from
the prosody model's predicted phoneme durations — the same values that drive the
acoustic model — so the metadata describes the audio produced rather than an
independent estimate. `marks` and `diagnostics` are populated from the SSML-C
stream, including normalized source-event provenance. Full multi-voice/stream
parity still needs correction. A mark sits at
the start of the following spoken word, or at audio end when it trails the
final word.

Part III is where the bulk of the remaining work sits. `TXT-020` through
`TXT-024` (lexicon, heteronyms, user pronunciations) are the largest block and
are prerequisites for the acoustic model being useful, since a trained voice
saying the wrong phonemes is not an improvement.

### Defects found while completing Part III

Four, each caught by a test written from a requirement rather than from the
code:

- **The lexicon's stress was being discarded.** `StressAssigner` overwrote
  whatever stress the phonemes arrived with, including CMUdict's primary and
  secondary marks — the very data `TXT-020` exists to supply. It now preserves
  stress that is already present and falls back to rules only for words the
  lexicon did not supply.
- **Emphasis was a no-op on the words that carry a sentence.** `enhanceStress`
  raised only vowels sitting at zero, so once the lexicon supplied stress,
  emphasising a word changed nothing. It now adds to the existing level.
- **The dialogue rule was too broad.** Treating any terminator followed by a
  lowercase word as reported speech meant that in lowercased text —
  which is what the duration estimator segments — *no sentence ever ended*.
  A closing quote must now intervene.
- **ALL-CAPS emphasis was implemented at the wrong stage.** Inserting
  `<emphasis>` markup during normalization would have had it spoken aloud as
  words, since normalization runs per segment *after* parsing. It now runs
  before the parser, so the existing emphasis machinery handles it.


### Normalization stage ordering

`TXT-010` is mostly an ordering problem. Each stage can destroy the pattern a
later one needs, and two real bugs during implementation were exactly that:

- Folding the em dash to a pause marker in the typography stage broke
  `Rom. 8:28–30`, because the Scripture range pattern matches on a dash
  character. Dash folding now runs last, after every range has expanded.
- `1990s` matched the unit pattern as 1990 plus the seconds symbol, giving
  "one thousand nine hundred ninety seconds". Decade expansion now runs before
  units.

Case-sensitive stages run before the text is folded to lowercase, because two
requirements depend on capitals: Roman numerals (lowercase "i", "x" and "c" are
ordinary words) and the `St. John` versus `Baker St.` disambiguation the
requirement names explicitly.

**Performance.** Each `replacingOccurrences` or regex call is a complete
Unicode-aware traversal, and roughly a dozen new stages took the 200,000-character
robustness case from 0.43 s to 5.6 s — which at the 1,000,000 characters
`TXT-001` mandates would have been about 28 s per call. A single `ContentFlags`
scan now records which characters are present, and every stage is gated on it,
returning that case to 0.77 s. This is the third time in this project that
adding correct behaviour reintroduced a performance problem; the pattern is
always the same, and so is the fix.


### Determinism and variation

`SYN-002` and `SYN-003` are a pair, and the engine satisfied the first only by
failing the second: prosody prediction contained no randomness at all, so every
render was already bit-identical. That is trivially deterministic and exactly
the "robotic sameness in repeated game lines" `SYN-003` forbids.

`SeededGenerator` is SplitMix64 — specified entirely in integer arithmetic, so
the stream is identical on every architecture, which is what `SYN-002`'s
"bit-identical audio on the same device class" requires. It is not
cryptographic, and should not be used as though it were.

`ProsodyVariation` applies bounded jitter to phoneme durations (±3%) and pitch
targets (±1.5%). With a seed the stream is reproducible; without one it starts
from a system-drawn value and then proceeds deterministically, so variation is
still bounded and well-distributed, just not reproducible.

### Breath groups

`TXT-031`'s "~30 words" is a proxy, not the constraint. Thirty polysyllabic
words last far longer than thirty short ones, so division enforces both a word
cap and a duration ceiling estimated from syllable count. The first
implementation enforced only the word cap and produced 13.3-second groups
against a 9-second ceiling; the test caught it.

Division prefers punctuation boundaries, then falls back to breaking before a
conjunction, and only then splits mechanically — so a break lands on a phrase
edge rather than inside a constituent, which is what "syntactically plausible"
asks for.

Dialogue punctuation is handled by treating a terminator followed by a
lowercase continuation as reported speech, so `"Stop there!" she cried.` is one
sentence rather than two.


### TXT-020 measured: G2P accuracy is 54.2% against a 92% target

The lexicon half of `TXT-020` shipped in v0.7.0. The other half — "≥ 92%
phoneme accuracy on a held-out OOV test set" — was recorded as unmeasured
rather than claimed. It has now been measured, and it is not close.

`G2PEvaluator` holds 2,000 words out of the built-in lexicon and phonemizes
them by rule alone, which reproduces exactly what an out-of-vocabulary word
encounters. Accuracy is the complement of phoneme error rate, computed by edit
distance against CMUdict.

| Metric | Measured | Target |
|---|---|---|
| Phoneme accuracy | **54.2%** | ≥ 92% |
| Word accuracy (exact) | **4.2%** | — |

Four percent of out-of-vocabulary words are pronounced exactly right.

**Three defects were found by building the harness**, and the first measurement
(50.1%) was partly an artefact of them:

- **`s` was mapped to /z/.** Every word beginning with "s" was mispronounced by
  the fallback — "simple" came out as *zimple*.
- **ASCII `g` versus script `ɡ`.** The inventory uses U+0261; the fallback
  emitted U+0067. Two different characters, so phonemes from the lexicon and
  from the rules were not comparable, and `isValidIPA` rejected rule output.
- **The fallback emitted symbols outside the documented inventory** — bare `i`
  and `ə` — which contradicts `TXT-024`'s premise that the inventory is *the*
  set the engine can produce. Schwa is now a documented entry, since CMUdict
  writes it as unstressed AH and conflating the two makes "about" rhyme with
  "hut".

Fixing these raised the figure from 50.1% to 54.2%. The remaining 38-point gap
is genuine G2P quality, not measurement error.

**What this means.** English orthography is not tractable by the kind of
letter-to-sound rules currently implemented; reaching 92% needs either a
substantially larger rule set with morphological analysis, or the trained
neural G2P the requirement also permits. Until then the 126,052-form lexicon
is doing nearly all the real work, and `TXT-022`'s user lexicon is not a
convenience but the practical escape hatch for any proper noun outside it.

The test asserts a regression floor rather than the target, because a
permanently red build teaches a team to ignore it. A second test asserts that
the target is *not* met and instructs whoever makes it pass to delete the test
and assert the requirement directly.


### The lexicon block

The lexicon-size clause of `TXT-020` is satisfied by vendoring CMUdict (126,052
indexed forms, 6,052 above the
required minimum) as a package resource under its BSD-2-Clause licence, which
is attribution-only and does not encumber a commercial App Store product. It is
stored as distributed in ARPAbet and converted to CHOIR's IPA inventory per
lookup, with results cached: converting all 135,000 entries eagerly would cost
time and memory for words a request never asks about. Loading is lazy; call
`BuiltInLexicon.shared.preload()` to pay the cost at launch instead.

Resolution order in `Phonemizer` is: user lexicon (`TXT-022`), then heteronym
readings when part of speech is known (`TXT-021`), then the built-in lexicon
(`TXT-020`), then the compact fallback dictionary, then rule-based G2P.

**`TXT-020` remains partial** because the requirement has two halves. The
lexicon exists; the "≥92% phoneme accuracy on a held-out OOV test set" is
unmeasured, and claiming it without a test set would be dishonest.

**`TXT-023` is a down-payment, not the corpus.** The requirement asks for 2,500
entries; 111 are curated. The supplement was built after measuring rather than
assuming: of a twenty-term theological sample, CMUdict covered six, and among
the missing were Ecclesiastes, Deuteronomy, Thessalonians, Habakkuk and
Zephaniah — book names `ScriptureNormalizer` itself emits under `TXT-011`.
Expanding "Eccl. 3:1" was therefore handing the phonemizer a word it had to
guess at, undermining the requirement the expansion served. Coverage was
prioritized accordingly: all canonical book names first, then vocabulary the
rule fallback handles worst. `TXT-022` remains the escape hatch for anything
still missing.

**Repository size** grows by about 4 MB for the vendored dictionary. Against
`PRF-030`'s 400 MB installed-asset budget this is negligible, but it is a real
cost on every clone and is noted here deliberately.


### Resolved — the two markup parsers

`LinguisticFrontend` has been migrated to `SSMLCParser` and the older
`SSMLParser` is deleted. Text styling now honours `phoneme`, `say-as` and
`voice` alongside `prosody`, `emphasis` and `break`, and there is one markup
implementation rather than two.

XML entity decoding, which only the older parser had, was carried across rather
than dropped. It runs *after* tag scanning: decoding `&lt;` first would
manufacture an angle bracket the scanner then mistakes for markup.

---

## Part IV — The Swift Package & API

| Requirement | Priority | Status | Notes |
|---|---|---|---|
| `PKG-001` single-import SwiftPM package, no external steps | MUST | Implemented | — |
| `PKG-002` module layout `CHOIR`/`CHOIRCore`/`CHOIRAssets`/`CHOIRSpatial` | MUST | **Not implemented** | One `Choir` target; the public surface is not confined by module boundary |
| `PKG-003` minimum deployment targets | MUST | **Fixed** | Was iOS 16 / macOS 13 / watchOS 9 against a required iOS 17 / macOS 14 / watchOS 10 |
| `PKG-004` zero third-party runtime dependencies | MUST | Implemented | Apple frameworks only |
| `PKG-005` licence-clean, NOTICE file | MUST | **Fixed** | [NOTICE](./NOTICE) added; no NOTICE existed while CMUdict was already being redistributed |
| `PKG-006` exportable as signed XCFramework | SHOULD | **Not implemented** | — |
| `PKG-007` App Store compliance, no private API | MUST | **External gate** | Requires a signed embedded app and App Store validation |
| `API-001` three concentric tiers | MUST | **Partial** | The three surfaces exist, but Tier 3 contour/cache/asset management and complete multi-voice streaming remain incomplete |
| `API-002` async for long operations, `Sendable` types | MUST | **Partial** | Primary synthesis/export/play APIs are async; synchronous public full-buffer DSP still needs off-actor wrappers |
| `API-003` voices addressable type-safely and by string id | MUST | **Fixed** | `Voice(id:)` added |
| `API-004` value type, builder, Codable, clamping reported | MUST | **Fixed** | Clamping was silent; now reported in `clampings` |
| `API-005` DocC on every public symbol | MUST | **Partial** | Broadly documented; not enforced by a gate |
| `API-006` semantic versioning, no source-breaking change in a major | MUST | Observed | Pre-1.0, where breaking change is permitted |
| `API-007` SwiftUI convenience layer | SHOULD | **Not implemented** | — |
| `CON-001` no main-thread block over 1 ms | MUST | **Not verified** | No instrumentation to prove it |
| `CON-002` cancellation honoured every 50 ms | MUST | Implemented | Checked between every pipeline stage and every 64 words while phonemizing; 6 tests |
| `CON-003` actor-isolated, multiple instances | MUST | Implemented | `ChoirEngine` is an actor |
| `CON-004` QoS discipline, caller-assignable priority | MUST | Implemented | Public scheduling intent maps to structured task priority |
| `CON-005` shed caches under memory pressure | MUST | **Partial** | Race-safe lazy unload/reload exists; engine and OS-pressure integration remain |
| `REL-001` error taxonomy with code, description, recovery | MUST | **Fixed** | Stable `CHOIR-1xxx` codes, recovery suggestions, retryability |
| `REL-002` caller-selectable partial-failure policy | MUST | Implemented | `synthesizeBatch(texts:voice:parameters:policy:)`; 6 tests in `BatchPolicyTests` |
| `REL-003` `engine.verify()` self-check | MUST | **Partial** | Current checks cover lexicon/profile/init/mock render; model hashes and the specified 0.5 s silent smoke remain |
| `REL-004` zero known reproducible crashes | MUST | **Partial** | Known traps were fixed and robustness tests exist; the release fuzz/zero-crash gate remains |
| `REL-005` structured logging via `os.Logger` | SHOULD | **Not implemented** | — |

### TXT-001: the engine rejected long input

`validateText` capped input at **5,000 characters**. `TXT-001` requires
accepting "from 1 character to at least 1,000,000 characters per request" — two
orders of magnitude more, and small enough to reject a single chapter of the
audiobooks the specification names as a primary workload.

The robustness tests never caught it because they exercise `TextNormalizer` and
`LinguisticFrontend` directly, where no such cap exists. Only the engine's
public entry point enforced it, and every test that went through the engine used
a short sentence. It surfaced when a *cancellation* test needed input long
enough to still be running when cancelled.

The ceiling now sits at the documented figure. It exists to turn an unbounded
allocation into a typed error, not to cap ordinary use.

### CON-002 and SYN-007: cancellation

Nothing checked cancellation before this release. A sixty-minute audiobook
render — the workload `PRF-001` is written around — could not be stopped once
started, and `REL-001` already declared cancellation part of the error taxonomy
while nothing could produce it.

Checks sit between every pipeline stage, and every 64 words inside the
phonemization loop, the one unbounded loop in the front end. Both are far inside
the 50 ms `CON-002` allows, without paying an atomic read per word.

`CancellationError` is mapped to `ChoirError.cancelled` at the boundary, because
`REL-001` requires *a single* public taxonomy covering cancellation: a caller
catching `ChoirError` should not also have to catch a second error type for the
one outcome the taxonomy already names.

For `SYN-007`'s "model left in reusable state": the engine holds no per-request
mutable state, so restoring `state` on every exit path — including a throw from a
cancellation check partway through a stage — is the whole guarantee. A test
confirms the engine still synthesizes and still passes `verify()` afterwards.

### REL-002: batch failure policy

The choice is not cosmetic. When items form one artifact — the chapters of an
audiobook — half a result is worthless and `.failFast` is right. When they are
independent, such as a table of game lines, one unpronounceable name should not
cost the other four hundred, and `.continueAndReport` is right.

Cancellation is deliberately not an item failure: it ends the whole job
regardless of policy, or a cancelled batch would be reported as a batch of four
hundred failures.



## Part V — Platforms

| Requirement | Priority | Status | Notes |
|---|---|---|---|
| `PLT-001` identical API across platforms, divergence documented | MUST | **Partial** | API is identical and CI builds all five; no "Platform Differences" article |
| `PLT-002` seeded output perceptually identical across platforms | MUST | **Not verified** | Needs a null-test harness comparing renders across devices |
| `PLT-003` Apple silicon baseline, Intel policy documented | MUST | **Not implemented** | Neither documented nor enforced at package resolution |
| `PLT-010` full iOS feature set incl. background rendering | MUST | **Partial** | Synthesis works; background execution untested |
| `PLT-011` audio interruptions and route changes | MUST | **Not implemented** | No playback state machine |
| `PLT-012` thermal step-down to the efficient path | SHOULD | **Not implemented** | Requires the two vocoder paths of ML-V-006 |
| `PLT-020` macOS workstation batch, 4 concurrent jobs, CLI | MUST | **Partial** | `choir-benchmark` is a CLI target; concurrency untested |
| `PLT-021` `choir-cli` render tool | SHOULD | **Not implemented** | — |
| `SPA-001`…`SPA-005` visionOS spatial audio | MUST/SHOULD | **Not implemented** | Whole spatial layer outstanding |
| `PLT-030` watchOS documented subset | MUST | **Partial** | Builds and runs on watchOS; no curated on-watch voice set or capability errors |

These two parts were reviewed for the first time in this release. The four
`MUST` items fixed here were straightforward; the rest are genuine outstanding
work, and `PKG-002`'s module split and the whole `SPA` spatial layer are the
largest.


---

## Part VII — Quality Attributes (performance)

| Requirement | Priority | Status | Verified by |
|---|---|---|---|
| `PRF-001` batch RTF | MUST | **External gate** | Historical mock benchmark is not production-model evidence; reference hardware run remains |
| `PRF-010` streaming TTFA | MUST | **Partial** | Warm TTFA measured; sustained streaming RTF needs a long-running stream on-device |
| `PRF-011` cold start | MUST | **External gate** | Historical mock/source-resource timing excludes production assets and is not acceptance evidence |
| `PRF-020` peak memory | MUST | **Partial** | Whole-process RSS measured; the requirement asks for memory attributable to CHOIR alone |
| `PRF-021` battery | MUST | **Not measured** | Needs 60 minutes of streaming with playback on physical R1 |
| `PRF-030` asset budget | MUST | **Partial** | Harness/source measurement exists; production voice/model/vocoder assets do not |
| `PRF-032` watchOS asset subset | MUST | **Partial** | Current source measurement exists; a real watch voice subset does not |
| `PRF-040` benchmark harness | MUST | **Partial** | Harness/tests/report exist; reproducible runs on every reference device remain |

### PRF-011: measured in debug, corrected in release, then fixed

**Correction to v0.12.0.** That release reported lexicon load at 0.97 s and
claimed it consumed two-thirds of the R3 cold-start budget. That figure came
from a **debug build** and was wrong. Measured in release, the same
implementation cost 0.45 s — roughly 30% of the budget. The concern was real;
its size was overstated by more than 2x.

A debug build is not a slower release build, it is a different program. The
harness now detects an unoptimized build and prints a warning into the report
and to stderr, because a number that misleads is worse than no number.

**The fix, measured properly.** The lexicon now ships pre-sorted by word, is
memory-mapped rather than read, and is searched by comparing raw bytes. Loading
builds only an array of line offsets — one pass, no string allocation — and a
lookup materializes exactly one string.

| Measurement (R3, release, median of 9) | Text parse | Mapped + binary search |
|---|---|---|
| Lexicon load | 0.42–0.52 s | **0.00–0.01 s** |
| Cold start to first audio | 0.38–0.43 s | **0.02–0.05 s** |
| Installed assets | 3.45 MB | 3.18 MB |

The cost was never I/O. It was allocating a quarter of a million Swift strings
and hashing them into a dictionary at every launch, to answer lookups for the
few hundred words a request actually contains.

**A caution recorded with it.** The first attempt at this rewrite measured
*four times slower* than the code it replaced — in debug, where a hand-written
byte loop carries bounds checks while the stdlib call it replaced is already
compiled optimized. Micro-optimizations must be measured in release or they can
be exactly backwards.

Word count: the lexicon indexes **126,052** distinct word forms. Earlier
releases quoted 135,166, which is the source file's line count including
pronunciation variants, not indexed words. Both figures clear the 120,000 the
requirement asks for.

### What the harness measures, and what it cannot

Cold start is a single sample by nature: a true cold start includes process
launch and the first lexicon load, and neither recurs in-process. Repeated
measurement in one process would time a dictionary lookup instead. Everything
else reports a **median** over repeated samples with the range shown, because
single samples straddled targets — batch RTF read 0.16 against a 0.15 target on
one run and 0.03 on the next, which would make any pass/fail gate flap.

`PRF-021` (battery) and sustained streaming RTF are declared as not measured
rather than omitted; an omission reads as a pass. `PRF-040` also requires the
report on **every** reference device, and this run covers R3 only, so R1, R2,
R4 and R5 remain outstanding and are named as such in the report.

### QUA-004 intelligibility: harness built, measurement pending

`QUA-004` is the objective gate on whether a trained voice is usable: word-level
transcription accuracy ≥ 98% on Harvard sentences transcribed by an independent
ASR system, and ≥ 96% at the envelope corners of `VOX-G-007`.

The harness exists and is tested. It **cannot return a meaningful number yet**,
and that is not a limitation of the harness: run against the current mock
acoustic model and Griffin-Lim vocoder it will score near zero, correctly,
because the audio is not speech. It is built now so the first trained model can
be judged the day it lands rather than by ear.

What is in place:

- The IEEE Harvard sentences, the standard corpus, chosen because no sentence
  gives a listener context to guess a word they did not actually hear.
- Word error rate by edit distance, normalizing case and punctuation — an ASR
  returns neither — while preserving contractions, since "it's" and "its" are
  different words and conflating them would hide a real failure.
- Report accuracy weighted by sentence length, so a ten-word sentence and a
  four-word sentence do not count equally toward a word-level figure.
- The four envelope corners as the actual parameter extremes (±12 semitones
  against 0.5x and 2.0x rate).

Two decisions worth recording:

**The recognizer is not in the library.** `SEC-001` requires the runtime to make
zero network connections, and a consuming app should not link a speech
framework, request speech-recognition authorization, or face a privacy prompt
because CHOIR is able to test itself. The library holds the corpus, the protocol
and the scoring; the Apple Speech implementation lives in the benchmark tool and
is unreachable from the shipped product.

**Recognition is forced on-device.** Partly to honour `SEC-001` even in a test
tool, and partly for the measurement itself: a server-side recognizer may apply
language-model correction strong enough to repair speech a listener could not
actually understand, which would flatter the score.

An unavailable recognizer throws rather than scoring zero. A failure to measure
and a measurement of total unintelligibility are different outcomes, and
reporting the first as the second would be alarming and wrong.


---

## Specification defects found

Conflicts between §7's per-band realization rules and §8's binding per-voice
profiles surfaced the first time the conformance tests ran. Three are resolved
by the specification's own tolerance; the fourth required amending the
requirement.

### Resolved by QUA-008

`QUA-008` (§29.6, the tolerance §8 cross-references) permits median F0 ±10% and
tempo ±8%. Three profiles fall marginally outside their band envelope and well
inside that tolerance:

| Profile | Band rule | Specified | Envelope floor | Deviation | QUA-008 allows |
|---|---|---|---|---|---|
| SABLE `VOX-08-16` | `VOX-P-003` YA female 190–230 Hz | 188 Hz | 190 Hz | 1.05% under | 10% |
| GREER `VOX-08-23` | `VOX-P-004` mid female 175–210 Hz | 172 Hz | 175 Hz | 1.71% under | 10% |
| GRIMSHAW `VOX-08-28` | `VOX-P-005` elderly 3.2–4.0 syll/s | 3.1 syll/s | 3.2 syll/s | 3.13% under | 8% |

The conformance tests apply the QUA-008 tolerance to band checks and cite it,
rather than loosening the assertion arbitrarily.

### Resolved by amendment — `VOX-P-006` per-band formant separation

**`VOX-P-006` as published** required female formant scale ≈ **+15–20%** above
male within the same age band. Measured across §8's profiles:

| Band | Mean male | Mean female | Separation | Against v1.0 text |
|---|---|---|---|---|
| Child | 1.1775 | 1.2175 | **+3.4%** | Violates |
| Young Adult | 0.9950 | 1.1625 | +16.8% | Complies |
| Middle-Aged | 0.9800 | 1.1350 | +15.8% | Complies |
| Elderly | 0.9862 | 1.1050 | **+12.0%** | Violates |

Two bands failed as written, not one. Neither is a tolerance question:
`QUA-008` covers median F0 and tempo, not formant scale.

**Resolution.** §8's values are acoustically correct and the v1.0 threshold was
over-generalized. Vocal-tract dimorphism is age-dependent: it is minimal before
puberty and compresses again with age, the latter being the same convergence
`VOX-P-005` already encodes on the F0 axis. `VOX-P-006` has therefore been
amended by [`AMD-001`](./SRS_AMENDMENTS.md) to set per-band thresholds —
Young Adult and Middle-Aged +15–20%, Elderly +10–15%, Child +2–6% — rather than
re-tuning sixteen binding §8 profiles.

All four bands now conform. The child band is additionally checked to confirm
gender there is carried by F0 rather than formant structure, which is what the
amendment asserts is happening.

An adjacent inconsistency, not affecting the build: `VOX-G-004` gives an example
identifier `choir.elderly.male.villain.grimshaw`, while §8's binding table uses
the band token `eld` (`choir.eld.male.villain.grimshaw`), matching `ya` and
`mid` elsewhere. §8 governs, so `eld` is implemented.

---

## Migration from the pre-SRS roster (0.2.x → 0.3.0)

The previous roster was not SRS-conformant: it had no `gender` property, used a
"neutral" presentation the specification does not define, grouped six villains
separately instead of one per cell, and carried specialty voices with no
counterpart in §8. Call sites were migrated to the nearest SRS voice by
recommended use:

| Retired case | SRS voice | Basis |
|---|---|---|
| `.narratorFeminine` | `.isla` | §8: "Narration (long-form)" |
| `.narratorMasculine` | `.garrick` | §8: "epic narration" |
| `.youngAdultFeminine` | `.lyra` | Young adult female lead |
| `.youngAdultMasculine`, `.youngAdultNeutral1` | `.orion` | Young adult male lead |
| `.childFeminine` | `.wren` | Child female |
| `.elderlyFeminine` | `.maeve` | Elderly female |
| `.villainMasculine1` | `.malvern` | Middle-aged male villain |
| `.villainFeminine1` | `.ravenna` | Middle-aged female villain |
| `.characterWitchyFeminine` | `.hespera` | §8: "Witches, curses, gothic horror" |
| `.characterGrufMasculine` | `.bram` | §8: "weary, world-worn man" |
| `.characterRobotNeutral` | `.sable` | §8: "dark-glassy", affectless |

`Voice.ageBand` changed from `Int` to the `AgeBand` enum. Where a numeric axis
is needed, use `voice.ageBand.ordinal` (1 = child … 4 = elderly).
