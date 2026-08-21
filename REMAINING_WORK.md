# CHOIR Master Remaining-Work Backlog

**Status:** Pre-alpha engineering infrastructure
**Repository baseline:** v0.15.0 / commit 244ecd20db29cd833e2ebe037cf7504ef3fb78e3
**SRS baseline:** CHOIR-SRS-001 v1.0, 239 numbered requirements
**Last audited:** 21 August 2026

This is the canonical backlog for work that genuinely remains before CHOIR can
be described as a production-quality, fully on-device neural text-to-speech
engine. It is deliberately stricter than PROJECT_STATUS.md, IMPROVEMENTS.md,
and the current SRS_CONFORMANCE.md because those documents contain historical,
partial, or optimistic completion claims.

The existence of an API type, parser, test double, parameter profile, non-empty
audio buffer, or passing unit test does not make an audible product requirement
complete. A requirement involving speech is complete only when it is exercised
through the production model and vocoder and verified against its stated
acceptance criteria.

## Current truthful position

- The package, public types, voice metadata, and much of the linguistic front
  end are real and worth preserving.
- The default engine uses MockAcousticModel and MockVocoder.
- The default output is a 200 Hz sine tone whose duration follows the request;
  it is not speech.
- CoreMLAcousticModel is a throwing placeholder.
- The 32 voices are parameter profiles, not 32 audible voices.
- Voice selection currently collapses to four age-band IDs, and the default
  mock vocoder ignores even those IDs.
- The advertised streaming path renders the complete utterance before dividing
  it into chunks.
- The existing conformance report discusses only part of the 239-requirement
  SRS and does not cover whole requirement families.
- OOV G2P accuracy is 54.2% against the 92% requirement.
- The theological supplement contains 196 entries against the 2,500-entry
  target.
- CI and extensive tests validate substantial plumbing, not natural speech or
  release conformance.

## Definition of done

CHOIR is not production-ready until all retained MUST requirements have a
passing, reproducible acceptance result; every deferred SHOULD requirement has
a written justification; every public claim is demonstrably true; at least one
real production voice has passed the complete audio-quality gate; and all 32
voices have passed it before a release advertises a 32-voice library.

## SRS coverage map

| Requirement family | Count | Backlog coverage |
|---|---:|---|
| VOX-G - Voice library general | 10 | Scope, production model integration, voice-library realization |
| VOX-P - Acoustic design parameters | 7 | Production model integration, voice-library realization, prosody |
| VOX-08 - Binding voice profiles | 32 | Voice-library realization |
| VOX-V - Villain design | 5 | Voice-library realization |
| TXT - Linguistic frontend | 19 | Known defects, linguistic frontend, SSML execution |
| SYN - Synthesis core | 10 | Real-voice slice, production integration, true synthesis and streaming |
| PRO - Prosody and emotion | 13 | Prosody, expression, and SSML execution |
| STR - Streaming | 7 | True synthesis and streaming |
| AUD - Audio and export | 13 | Audio output, mastering, playback, and export |
| CCH - Cache and assets | 7 | Cache, asset delivery, and background jobs |
| PKG - Package | 7 | Governance, package and API completion |
| API - Public API | 8 | Known defects, package and API completion |
| CON - Concurrency | 5 | Known defects, true synthesis and streaming, release testing |
| REL - Reliability | 5 | Known defects, privacy/logging, fuzz and release gates |
| PLT - Platforms | 10 | Platform completion |
| SPA - Spatial audio | 5 | Platform completion, optional work |
| ML-A - Acoustic model | 6 | Training pipeline, production model integration |
| ML-V - Vocoder | 4 | Real-voice slice, training pipeline, production integration |
| ML-C - Core ML | 4 | Training pipeline, production model integration |
| PRF - Performance | 9 | Performance and audio-quality gates |
| QUA - Audio quality | 8 | Voice realization, performance and audio-quality gates |
| SEC - Privacy and ethics | 6 | Governance, privacy and safety |
| ACC - Accessibility | 3 | Accessibility and platform playback |
| LOC - Language/localization | 4 | Governance, voice realization, localization |
| INT - Product integrations | 11 | Required integrations and showcase proof |
| DOC - Documentation | 6 | Voice realization, documentation and release engineering |
| DST - Distribution/maintenance | 5 | Governance, cache versioning, release engineering |
| TST - Testing/acceptance | 10 | Performance gates, documentation, tests, CI, and release engineering |

## Priority 0 - Project truth, scope, and governance

- [ ] Mark all current 0.x builds as pre-alpha engineering releases.
- [ ] Remove production-ready language from public and internal documentation.
- [ ] Re-audit all 239 numbered SRS requirements.
- [ ] Give every requirement exactly one status: complete, partial, failed,
      unmeasured, deferred, withdrawn, or not started.
- [ ] Record evidence for every complete requirement.
- [ ] Record the blocking reason and next action for every incomplete
      requirement.
- [ ] Create a machine-checkable requirement-to-code-to-test traceability map.
- [ ] Make this file and the traceability map the canonical planning sources.
- [ ] Reconcile PROJECT_STATUS.md with actual behaviour.
- [ ] Reconcile IMPROVEMENTS.md with actual behaviour.
- [ ] Keep SRS_CONFORMANCE.md as conformance evidence rather than a product
      marketing document.
- [ ] Decide whether v1 genuinely retains all 32 voices.
- [ ] If scope is reduced, version the SRS amendment and preserve the intended
      future roster.
- [ ] Decide whether watchOS remains a v1 runtime target.
- [ ] Decide whether the complete visionOS spatial layer remains a v1 target.
- [ ] Decide whether both General American and Received Pronunciation output
      remain mandatory for all retained voices in v1.
- [ ] Select one primary synthesis architecture; the recommended path is neural
      acoustic modelling plus a neural low-lookahead vocoder.
- [ ] Remove or quarantine the sample-concatenation experiment if the neural
      architecture is selected.
- [ ] Remove claims that isolated phoneme recordings can recreate anyone's
      natural voice.
- [ ] Resolve the conflict between VoiceSampleLibrary and the SRS prohibition
      on real-person cloning capability.
- [ ] Decide whether the runtime is MIT/open source, proprietary, or split into
      an open runtime and separately licensed model assets.
- [ ] Document that previously distributed MIT versions cannot be clawed back.
- [ ] Correct the SRS contradiction that says six villains in one section and
      eight elsewhere.
- [ ] Require versioned amendments for every future SRS change.
- [ ] Repair the release history in which an old v1.0.0 predates newer v0.x
      releases.
- [ ] Establish separate package, engine, model, voice-asset, and cache-format
      versions.
- [ ] Prevent any new public feature claim without an executable acceptance
      test or documented manual quality gate.

## Priority 0 - One complete real-voice vertical slice

- [ ] Select the first production voice and its target use case.
- [ ] Freeze a standard text and audio evaluation corpus for that voice.
- [ ] Replace MockAcousticModel in the production engine path.
- [ ] Replace MockVocoder in the production engine path.
- [ ] Remove the 200 Hz sine-wave path from normal engine initialization.
- [ ] Ensure test mocks cannot be selected accidentally in production builds.
- [ ] Define the acoustic model architecture.
- [ ] Define the mel-spectrogram representation and preprocessing contract.
- [ ] Define the duration, F0, energy, stress, voicing, and conditioning tensor
      contracts.
- [ ] Train or integrate a genuine acoustic model for the first voice.
- [ ] Train or integrate a genuine neural vocoder.
- [ ] Produce intelligible 48 kHz speech end to end.
- [ ] Make the first voice's pitch, rate, emotion, breathiness, age, and gender
      controls audible where applicable.
- [ ] Implement true progressive synthesis for that voice.
- [ ] Implement playback and export for that voice.
- [ ] Produce a reference audio gallery.
- [ ] Run independent ASR intelligibility testing.
- [ ] Run the artifact and MOS quality gates.
- [ ] Do not begin broad 32-voice scaling until this slice passes.

## Priority 0 - Training data and reproducible model pipeline

- [ ] Identify commercially safe training data.
- [ ] Record the licence and provenance of every dataset.
- [ ] Prohibit scraped or unlicensed speaker data.
- [ ] Prohibit target-speaker cloning data.
- [ ] Define how original designed voices will be constructed without
      imitating identifiable people.
- [ ] Build text cleaning and normalization for training data.
- [ ] Build audio validation and corruption detection.
- [ ] Build phoneme and alignment preprocessing.
- [ ] Define speaker/voice conditioning metadata.
- [ ] Define emotion, style, intensity, and continuous-control labels.
- [ ] Build leakage-safe training, validation, and test splits.
- [ ] Train the shared multi-voice acoustic model.
- [ ] Train structured voice embeddings.
- [ ] Train the quality vocoder.
- [ ] Train or derive the efficient vocoder path.
- [ ] Establish fixed seeds where supported.
- [ ] Pin all training dependencies.
- [ ] Store every training configuration as code.
- [ ] Give each training run a permanent identifier.
- [ ] Archive metrics, logs, checkpoints, and evaluation results per run.
- [ ] Create one documented command per training stage.
- [ ] Build checkpoint evaluation and model-selection tooling.
- [ ] Build scripted Core ML conversion.
- [ ] Make every shipped Core ML asset traceable to a training run and
      conversion configuration hash.
- [ ] Create a complete rebuild-from-scratch runbook.
- [ ] Verify that a clean environment can reproduce models that pass the same
      quality gates.

## Priority 0 - Production model integration

- [ ] Implement CoreMLAcousticModel.predict.
- [ ] Implement real asset discovery and model loading.
- [ ] Make ChoirEngine.initialize load or prepare production components rather
      than install mocks.
- [ ] Provide safe model/vocoder injection for tests and internal tooling.
- [ ] Give every retained voice a stable, unique conditioning ID.
- [ ] Stop mapping voices only to AgeBand.ordinal.
- [ ] Pass the complete VoiceProfile through synthesis.
- [ ] Apply median F0 and F0 range.
- [ ] Apply formant scaling.
- [ ] Apply spectral tilt.
- [ ] Apply breathiness.
- [ ] Apply roughness, jitter, shimmer, and subharmonic texture.
- [ ] Apply voice-specific tempo.
- [ ] Apply pitch dynamism.
- [ ] Add missing pause-style data.
- [ ] Add missing articulation-precision data.
- [ ] Validate model input tensor lengths and shapes before inference.
- [ ] Surface model-load, asset, compute-unit, and inference failures as stable
      typed errors.
- [ ] Implement real graph/model warm-up.
- [ ] Verify ANE execution where supported.
- [ ] Verify GPU execution where supported.
- [ ] Verify CPU fallback.
- [ ] Add automatic per-device compute-unit selection.
- [ ] Add a caller override for testing.
- [ ] Load voice-family assets lazily.
- [ ] Unload assets safely under pressure.

## Priority 0 - Known correctness defects

- [ ] Fix the script-g versus ASCII-g mismatch between the public phoneme
      inventory, G2P output, and PhonemeEncoder.
- [ ] Stop silently dropping unknown phonemes through compactMap.
- [ ] Establish one canonical phoneme representation across every stage.
- [ ] Reject or diagnose unknown phonemes before acoustic-model input.
- [ ] Prevent phoneme, duration, F0, energy, stress, and voicing arrays from
      becoming different lengths.
- [ ] Replace or accurately rename NeuralVocoder.
- [ ] Implement real Griffin-Lim refinement if a Griffin-Lim fallback remains.
- [ ] Remove any unused or deceptive pseudo-vocoder code.
- [ ] Fix a request containing one voice run so it honours that requested
      voice.
- [ ] Execute SSML pitch, rate, and volume attributes.
- [ ] Execute break events rather than discarding them.
- [ ] Decode phoneme-tag content as phonemes rather than ordinary graphemes.
- [ ] Preserve SSML styling through multi-voice rendering.
- [ ] Make every public synthesis entry point use an explicit input mode.
- [ ] Implement production pre-phonemized synthesis.
- [ ] Support optional duration and pitch targets in expert input.
- [ ] Validate streaming chunk size; reject zero and invalid values.
- [ ] Fix engine reentrancy so a second request does not receive a misleading
      not-initialized error.
- [ ] Put cancellation checks inside long front-end, model, vocoder, and export
      loops.
- [ ] Demonstrate compute stops within the required cancellation window.
- [ ] Integrate AssetCache with ChoirEngine or stop claiming engine caching.
- [ ] Fix cache replacement size double-counting.
- [ ] Fix eviction when only transcription or prosody entries occupy the cache.
- [ ] Integrate RealTimeController with live synthesis or remove it from the
      advertised API.
- [ ] Integrate SynthesisSession with actual jobs.
- [ ] Integrate custom pronunciation dictionaries end to end.
- [ ] Integrate ToBI output end to end.
- [ ] Integrate audio-effect chains end to end.
- [ ] Implement ChoirEngine.clearCache.
- [ ] Implement ChoirEngine.exportAudio.
- [ ] Stop returning empty Data for unimplemented encoders.
- [ ] Remove unsupported formats from public API until functional.
- [ ] If sample synthesis remains, resample every recording to the engine rate.
- [ ] If sample synthesis remains, stop always selecting the first sample.
- [ ] If sample synthesis remains, implement genuine overlapping crossfades.
- [ ] If sample synthesis remains, report missing phonemes rather than silently
      omitting them.
- [ ] If sample synthesis remains, add coarticulation/context handling or state
      clearly that it is experimental and non-natural.

## Priority 1 - Linguistic frontend completion

- [ ] Raise held-out OOV phoneme accuracy from 54.2% to at least 92%.
- [ ] Replace the simplistic fallback with a trained neural or serious
      rule-hybrid G2P model.
- [ ] Add morphological handling for prefixes, suffixes, compounds, and
      inflections.
- [ ] Expand the theological/biblical supplement from 196 to at least 2,500
      entries.
- [ ] Cover every canonical biblical personal and place name.
- [ ] Add common patristic names.
- [ ] Add Reformation names.
- [ ] Add Socinian and biblical-Unitarian names.
- [ ] Create the required 300-word theological pronunciation audit.
- [ ] Reach 100% accuracy on that audit.
- [ ] Add explicit fallback behaviour for unsupported characters.
- [ ] Harden emoji, control-character, zero-width, mixed-script, and repeated-
      character handling at the public engine boundary.
- [ ] Complete ellipsis/trailing-off prosody.
- [ ] Complete parenthetical/subordinated prosody.
- [ ] Verify every TXT-010 normalization category with golden cases.
- [ ] Verify every Scripture-reference form and multi-reference list.
- [ ] Verify heteronym selection using real context rather than lookup alone.
- [ ] Verify user-lexicon precedence and persistence in consuming apps.
- [ ] Add audio examples for every stable public phoneme.
- [ ] Document pronunciation resolution order and fallback behaviour.

## Priority 1 - Voice-library realization

The following applies to every retained voice.

- [ ] Create a production voice embedding.
- [ ] Make the binding profile audible.
- [ ] Implement the specified prosody signature.
- [ ] Define and implement the default accent.
- [ ] Define the guaranteed control envelope.
- [ ] Define pause style.
- [ ] Define articulation precision.
- [ ] Measure median F0.
- [ ] Measure F0 range.
- [ ] Measure formant scale.
- [ ] Measure tempo.
- [ ] Measure breathiness and roughness.
- [ ] Verify intelligibility at every required envelope corner.
- [ ] Create neutral, emotive, and character-typical demonstration passages.
- [ ] Render and archive gallery audio.
- [ ] Confirm the voice is perceptually distinct.

Across the library:

- [ ] Make all 32 advertised voices genuinely distinct.
- [ ] Reach at least 90% blinded ABX identification accuracy.
- [ ] Keep child voices stylized and non-imitative.
- [ ] Realize all eight villain voices.
- [ ] Create menace through performance and prosody rather than distortion.
- [ ] Make every villain capable of neutral delivery.
- [ ] Implement and document menace emphasis.
- [ ] Verify continuous age and gender shifts preserve voice identity.
- [ ] Verify profile conformance within required F0 and tempo tolerances.
- [ ] Select at least four watchOS-suitable voices if watchOS remains in scope.
- [ ] Produce a Voice Book page for every voice.

## Priority 1 - Prosody, expression, and SSML execution

- [ ] Apply pitch shift around each voice's base pitch while preserving
      formants.
- [ ] Implement natural 0.6x-2.0x rate control.
- [ ] Scale phonemes and pauses non-linearly like natural speech.
- [ ] Implement real emotion-intensity conditioning.
- [ ] Implement real breathiness control.
- [ ] Add optional breath sounds at valid breath boundaries.
- [ ] Implement independent gain and dynamic-range control.
- [ ] Implement functional age shift.
- [ ] Implement functional gender shift.
- [ ] Implement neutral, joyful, tender, solemn, fearful, angry, sorrowful, and
      suspenseful styles.
- [ ] Make emotion styles coherent acoustic/prosodic behaviours rather than
      inert parameter presets.
- [ ] Support style intensity.
- [ ] Support sub-sentence style regions.
- [ ] Smooth transitions between adjacent style regions.
- [ ] Make emphasis audibly change pitch, duration, and energy.
- [ ] Make explicit breaks accurate within 10 ms.
- [ ] Prevent explicit breaks from doubling automatic pauses.
- [ ] Implement voice-appropriate question intonation.
- [ ] Implement exclamation intonation.
- [ ] Implement quotation intonation.
- [ ] Add a switch to suppress automatic punctuation interpretation.
- [ ] Clamp every control against per-voice safe envelopes.
- [ ] Return diagnostics for every clamp.
- [ ] Validate all supported SSML-C nesting and edge cases.

## Priority 1 - True synthesis and streaming

- [ ] Generate audio progressively while later text is still being processed.
- [ ] Provide an AsyncSequence-based streaming API.
- [ ] Preserve a callback API where useful.
- [ ] Make batch and streaming quality identical.
- [ ] Make seeded batch and streaming output null-test equivalent.
- [ ] Produce seamless chunk boundaries without clicks, gaps, or level jumps.
- [ ] Deliver word, phoneme, mark, and sentence timing incrementally.
- [ ] Support mid-stream cancellation.
- [ ] Support parameter changes at sentence boundaries.
- [ ] Detect inability to sustain real time before underrun.
- [ ] Switch to an efficient model path under thermal/performance pressure.
- [ ] Report every automatic quality downgrade.
- [ ] Build the dialogue-queue API.
- [ ] Support caller-specified inter-utterance gaps.
- [ ] Support gapless multi-character dialogue.
- [ ] Provide an AVAudioEngine source-node integration.
- [ ] Support at least two fair concurrent jobs on iOS/macOS.
- [ ] Support four concurrent jobs on M-series Macs.
- [ ] Provide per-job cancellation.
- [ ] Provide per-job priority and fair scheduling.
- [ ] Verify real-model seeded determinism.
- [ ] Verify bounded natural variation without a seed.
- [ ] Revalidate the duration estimator against real audio to within 10%.

## Priority 1 - Audio output, mastering, playback, and export

- [ ] Change engine-native audio to mono float32 PCM at 48 kHz.
- [ ] Provide Float-array, Data, and AVAudioPCMBuffer accessors.
- [ ] Avoid unnecessary buffer copies.
- [ ] Implement high-quality conversion to 44.1, 24, and 16 kHz.
- [ ] Implement int16 conversion.
- [ ] Implement WAV PCM at 16 and 24 bits.
- [ ] Implement CAF.
- [ ] Implement AAC in m4a at requested bitrates.
- [ ] Implement ALAC in m4a.
- [ ] Treat MP3 as optional and expose it only when functional.
- [ ] Add correct duration, sample-rate, title, artist/voice, and chapter
      metadata.
- [ ] Implement chapter-mark writing.
- [ ] Implement resumable multi-chapter m4b assembly.
- [ ] Add audiobook progress reporting.
- [ ] Verify final audiobook integrity.
- [ ] Implement caller-selectable LUFS normalization.
- [ ] Implement true-peak limiting.
- [ ] Match voice loudness within 0.5 LU.
- [ ] Enforce the DC-offset target.
- [ ] Prevent denormal-related CPU spikes.
- [ ] Add clickless utterance-start and utterance-end fades.
- [ ] Implement a verified optional broadcast mastering preset.
- [ ] Implement pause, resume, stop, and seek.
- [ ] Add completion and playback-state callbacks.
- [ ] Cooperate with caller-controlled AVAudioSession configuration.
- [ ] Handle audio interruptions and route changes.
- [ ] Provide live word-synchronization events.
- [ ] Export per-line timing JSON.
- [ ] Generate SRT and VTT captions.

## Priority 1 - Cache, asset delivery, and background jobs

- [ ] Build a content-addressed rendered-audio cache.
- [ ] Include text, voice, parameters, seed, and engine version in cache keys.
- [ ] Persist cache entries on disk.
- [ ] Use platform-appropriate Caches and Application Support locations.
- [ ] Exclude ordinary entries from backups.
- [ ] Support pinned entries.
- [ ] Support configurable size caps.
- [ ] Implement correct LRU eviction.
- [ ] Implement full purge.
- [ ] Implement selective purge.
- [ ] Expose cache usage and inspection.
- [ ] Preserve compatible caches across package updates.
- [ ] Support fully embedded model assets.
- [ ] If retained, support resumable background/ODR asset packs.
- [ ] Hash-verify every model asset.
- [ ] Load voice families lazily.
- [ ] Unload assets on memory-pressure notifications.
- [ ] Reload assets transparently.
- [ ] Build persistent background-render queues.
- [ ] Integrate BGProcessingTask on iOS.
- [ ] Resume long-running jobs after process restart.

## Priority 1 - Package and API completion

- [ ] Split the package into public, core, assets, and optional spatial modules,
      or formally amend PKG-002.
- [ ] Confine the supported public surface to the intended public module.
- [ ] Run full Swift 6 strict-concurrency checking with zero warnings.
- [ ] Complete Tier 1 one-call synthesis/playback.
- [ ] Complete Tier 2 request/result/export APIs.
- [ ] Complete Tier 3 streaming, phoneme, contour, cache, and asset APIs.
- [ ] Make defaults genuinely voice-specific.
- [ ] Document every public symbol.
- [ ] Compile every documentation example in CI.
- [ ] Add API compatibility checking.
- [ ] Build SpeakButton.
- [ ] Build a voice-picker component.
- [ ] Build synchronized word-highlighting UI.
- [ ] Export a signed XCFramework.
- [ ] Build the real choir-cli, not only choir-benchmark.
- [ ] Test both source and binary package integration.

## Priority 1 - Platform completion

- [ ] Verify full operation on physical iPhones and iPads.
- [ ] Implement background rendering within iOS rules.
- [ ] Implement interruption and route-change state handling.
- [ ] Test calls, Siri, headphones, AirPods, CarPlay, and backgrounding.
- [ ] Monitor thermal state and degrade gracefully.
- [ ] Verify macOS App Sandbox compliance.
- [ ] Verify four-job M-series rendering.
- [ ] Define, document, and enforce the Intel Mac policy.
- [ ] Verify seeded cross-device audio parity.
- [ ] Build the optional CHOIRSpatial module if retained.
- [ ] Implement positioned spatial speakers.
- [ ] Support at least six simultaneous Vision Pro speakers.
- [ ] Support head-tracked movement without artifacts.
- [ ] Add RealityKit entity binding.
- [ ] Implement the documented watchOS subset.
- [ ] Return typed capability errors for unsupported watch features.
- [ ] Keep watch assets under 60 MB.
- [ ] Decide whether phone-assisted watch rendering remains in v1.
- [ ] Either test tvOS fully or remove broad tvOS claims.

## Priority 2 - Performance and audio-quality gates

- [ ] Benchmark production models rather than mocks.
- [ ] Measure batch RTF on every reference device.
- [ ] Measure genuine streaming time to first audio.
- [ ] Measure sustained streaming RTF.
- [ ] Measure cold start including process launch and model loading.
- [ ] Measure CHOIR-attributable peak memory.
- [ ] Run the 60-minute battery test.
- [ ] Measure thermal behaviour and fallback transitions.
- [ ] Verify complete installed and per-family asset budgets.
- [ ] Generate a fresh report for every release and reference device.
- [ ] Write and freeze the MOS listening protocol.
- [ ] Run blinded naturalness testing.
- [ ] Reach at least 4.2/5 naturalness-as-designed.
- [ ] Reach at least 4.5/5 audio cleanliness.
- [ ] Audit every voice for clicks, buzz, ringing, warble, phase artifacts,
      dropped phones, duplicated phones, and gibberish.
- [ ] Make any artifact on the standard corpus release-blocking.
- [ ] Replace the echo-transcriber quality test with independent ASR.
- [ ] Reach at least 98% default intelligibility.
- [ ] Reach at least 96% envelope-corner intelligibility.
- [ ] Run 60-minute loudness, tempo, and timbre drift testing.
- [ ] Conduct 30-minute fatigue tests for narration voices.
- [ ] Archive every release-quality report.

## Priority 2 - Privacy, safety, accessibility, and localization

- [ ] Add an automated zero-network/socket audit.
- [ ] Verify there is no telemetry or identifier collection.
- [ ] Hash-check assets during real loading.
- [ ] Implement privacy-safe structured logging.
- [ ] Never log user text at normal levels.
- [ ] Remove shipped real-person cloning capabilities.
- [ ] Add a responsible-use and disclosure guide.
- [ ] Audit the licences for CMUdict, Harvard sentences, training code,
      datasets, and model assets.
- [ ] Test coexistence with VoiceOver and system speech.
- [ ] Make audio ducking configurable.
- [ ] Document word-highlighting and caption accessibility workflows.
- [ ] Implement General American output.
- [ ] Implement Received Pronunciation for every retained voice, or amend the
      v1 requirement.
- [ ] Document future multilingual architecture.
- [ ] Support common Latin, Greek, and Hebrew names embedded in English.
- [ ] Make API-facing and error strings localization-ready.

## Priority 2 - Required integrations and showcase proof

- [ ] Build a one-call THE ONE verse-synthesis API.
- [ ] Return reliable per-verse timing boundaries.
- [ ] Add correct divine-name and archaic KJV/YLT pronunciations.
- [ ] Document chapter pre-rendering and cache pinning.
- [ ] Document Socinian-corpus footnote handling.
- [ ] Prove a 300-page Ponte document can render resumably.
- [ ] Support per-section files or chaptered m4b output.
- [ ] Define heading, quotation, and footnote markup mapping.
- [ ] Prove dynamic game dialogue at conversational latency.
- [ ] Support interruptible game barks.
- [ ] Load character voice presets from data files.
- [ ] Publish a phoneme-to-viseme mapping.
- [ ] Build manifest-to-audio rendering for video scripts.
- [ ] Produce per-line files, timing sidecars, and captions.
- [ ] Build a reference/showcase application.
- [ ] Ensure the showcase uses public APIs only.

## Priority 2 - Documentation, tests, CI, and release engineering

- [ ] Rewrite README examples against the real API.
- [ ] Replace nonexistent voice aliases.
- [ ] Repair GETTING_STARTED.md.
- [ ] Rewrite STREAMING.md to describe actual behaviour.
- [ ] Remove stale version and deployment-target claims.
- [ ] Regenerate PROJECT_STATUS.md.
- [ ] Regenerate benchmarks for the current release.
- [ ] Make README, DocC, SRS, status, and conformance documents agree.
- [ ] Write the platform-differences article.
- [ ] Write the complete SSML-C reference with validated examples.
- [ ] Write the complete Voice Book.
- [ ] Write the training and maintenance manual.
- [ ] Write integration recipes for THE ONE, Ponte, games, and video.
- [ ] Produce a printable API and voice-ID cheat sheet.
- [ ] Add the engine-version integer used by cache keys.
- [ ] Document voice and audio migration rules.
- [ ] Document additive language, voice, and emotion extension paths.
- [ ] Create a yearly OS-beta smoke-test procedure.
- [ ] Measure and enforce at least 85% front-end coverage.
- [ ] Create the 200-request seeded golden-audio corpus.
- [ ] Add cross-release audio hash/null tests.
- [ ] Run the complete quality gate for every release candidate.
- [ ] Run performance tests on all five reference devices.
- [ ] Add physical-platform integration tests.
- [ ] Run at least 24 machine-hours of fuzzing per release.
- [ ] Preserve every discovered fuzz failure as a regression test.
- [ ] Add the automated network-silence test.
- [ ] Run the four-job, two-hour concurrency and cancellation soak.
- [ ] Add memory-pressure and thermal tests.
- [ ] Replace non-empty-buffer tests with audible-behaviour tests.
- [ ] Test that different voices produce measurably different audio.
- [ ] Test that every advertised parameter changes audio correctly.
- [ ] Test SSML audibly, not only structurally.
- [ ] Test that streaming yields before full rendering completes.
- [ ] Test compressed exports by decoding and validating them.
- [ ] Pin CI actions by immutable commit SHA.
- [ ] Pin the Xcode/Swift toolchain rather than floating latest-stable.
- [ ] Add DocC, coverage, API-breakage, benchmark, and quality CI jobs.
- [ ] Create signed release artifacts and checksums.
- [ ] Block production releases until every retained MUST requirement passes.

## Explicitly optional work

These SRS MAY features must not displace the blockers above.

- [ ] Custom voice designer and interpolation API.
- [ ] Per-voice emotion compatibility matrix.
- [ ] Pitch-contour override API.
- [ ] App Intents and Shortcuts integration.
- [ ] Ambisonic or spatial-bed export.
- [ ] AVSpeechSynthesisProviderAudioUnit system-voice integration.
- [ ] Multiple automatically generated takes per line.
- [ ] Full tvOS product support.
- [ ] Additional languages.
- [ ] Singing synthesis.
- [ ] Live voice conversion.

## Recommended execution order

1. Truthfully re-baseline the SRS and freeze the v1 scope.
2. Build one real voice through a reproducible acoustic-model and neural-vocoder
   pipeline.
3. Repair the known phoneme, voice-ID, SSML, concurrency, and API defects.
4. Make streaming, playback, export, and caching real for the one-voice slice.
5. Pass intelligibility, artifact, MOS, latency, memory, and battery gates.
6. Expand to four production voices and prove the library architecture.
7. Complete the retained platform and integration requirements.
8. Scale to all 32 voices only after the system is demonstrably stable.
9. Repair all public documentation and release engineering.
10. Publish a production release only after the complete retained MUST gate is
    green.

The next meaningful milestone is not another API or another metadata profile.
It is one real, beautiful, intelligible voice running entirely on-device through
the complete production pipeline, with genuine streaming, export, and objective
quality evidence.
