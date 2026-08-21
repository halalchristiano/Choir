# SRS Conformance Report

Traceability between [CHOIR — Software Requirements Specification v1.0](./CHOIR%20—%20Software%20Requirements%20Specification%20v1.0.pdf)
and the implementation, plus defects found in the specification itself while
implementing Part II.

Conformance is enforced by `Tests/ChoirTests/SRSConformanceTests.swift`, which
implements each requirement's `Acceptance:` criterion literally rather than
paraphrasing it.

---

## Part II — The Voice Library

| Requirement | Priority | Status | Verified by |
|---|---|---|---|
| `VOX-G-001` 32 voices, 4 bands x 2 genders x 4, 1 villain per cell | MUST | Implemented | `testVoiceCount`, `testCellStructure`, `testCellsPartitionLibrary` |
| `VOX-G-002` original synthetic designs, no real-person imitation | MUST | Satisfied by design | No speaker-encoder path exists |
| `VOX-G-003` perceptual distinctness, ≥90% ABX | MUST | **Not verifiable yet** | Requires trained models and a listening test |
| `VOX-G-004` immutable metadata per voice | MUST | Implemented | `testMetadataCompleteness`, `testIdentifierShape` |
| `VOX-G-005` permanent identifiers | MUST | Implemented | `testIdentifierUniqueness`, `testRawValueIsIdentifier` |
| `VOX-G-006` shared acoustic model via conditioning | MUST | **Not implemented** | Blocked on the acoustic model |
| `VOX-G-007` intelligible across customization envelope | MUST | **Not verifiable yet** | Requires QUA-004 ASR harness |
| `VOX-G-008` three demo passages per voice | SHOULD | **Not implemented** | — |
| `VOX-G-009` voice designer API | MAY | Partial | `VoiceBlending` interpolates profiles |
| `VOX-G-010` child voices are stylized characters | MUST | Satisfied by design | `testChildVillainsRemainChildlike` |
| `VOX-P-001` full designed parameter set stored per voice | MUST | Implemented | `testParameterRanges`, `testMedianWithinRange` |
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
precision are not quantified per voice in §8 and are not yet modelled.

---

## Part III — Functional Requirements

| Requirement | Priority | Status | Verified by |
|---|---|---|---|
| `TXT-001` accept 1 … 1,000,000 characters | MUST | Implemented | `testSingleCharacter`, `testLargeRepeatedInput` |
| `TXT-002` never crash, hang, or produce unbounded output | MUST | **Implemented — was violated** | `testNormalizerRobustness`, `testFrontendRobustness` (29 adversarial inputs) |
| `TXT-003` input mode selected explicitly, never guessed | MUST | **Not implemented** | The engine still infers SSML from content |
| `TXT-010` full normalization inventory | MUST | **Partial** | Cardinals, currency and abbreviations only; ordinals, decimals, fractions, percentages, dates, times, phone numbers, years, Roman numerals, units, URLs and ranges outstanding |
| `TXT-011` Scripture reference formats | MUST | Implemented | 14 tests in `ScriptureNormalizationTests` |
| `TXT-012` configurable `NormalizationPolicy` | SHOULD | Implemented | `testConfigurableStyle`, `testCanBeDisabled`, `testVerbatimMode` |
| `TXT-013` typography (smart quotes, dashes, ellipses, caps) | SHOULD | **Not implemented** | — |
| `TXT-020` 120,000-word lexicon, ≥92% OOV accuracy | MUST | **Not implemented** | Needs a lexicon and a held-out test set |
| `TXT-021` ≥60 heteronyms disambiguated by part of speech | MUST | **Not implemented** | — |
| `TXT-022` runtime user lexicon API | MUST | Implemented | 9 tests in `UserLexiconTests` |
| `TXT-023` biblical/theological proper-noun supplement (≥2,500) | SHOULD | **Not implemented** | Pairs naturally with `TXT-011` |
| `TXT-024` documented, stable phoneme inventory | MUST | **Not implemented** | — |
| `TXT-030` sentence and phrase segmentation | MUST | **Partial** | Splitting exists; phrase-boundary strength is not passed to prosody |
| `TXT-031` breath groups for long sentences | MUST | **Not implemented** | — |
| `TXT-040` SSML-C dialect | MUST | **Partial** | `prosody`, `emphasis` and `break` parse; `phoneme`, `say-as`, `voice` and `mark` do not |
| `TXT-041` graceful degradation + markup diagnostics | MUST | **Partial** | Malformed markup is tolerated, but no diagnostics list is returned and there is no strict mode |
| `TXT-042` `<voice>` mid-text switching | MUST | **Not implemented** | — |
| `SYN-002` deterministic output given a seed | MUST | **Not implemented** | No seed parameter exists |
| `SYN-005` timing metadata (per word/phoneme, marks) | MUST | **Partial** | 10 tests in `SynthesisMetadataTests`; `<mark>` positions await `TXT-040` parsing |
| `SYN-008` failures surface as typed errors, never traps | MUST | Implemented | `testFrontendRobustness`; 16 traps fixed across 0.2.x–0.3.x |
| `SYN-010` duration estimate API | SHOULD | **Not implemented** | — |

`TXT-022` is implemented as an actor with a replaceable persistence store,
defaulting to `UserDefaults`. Registrations take precedence over the built-in
lexicon and are resolved through an immutable snapshot taken once per synthesis
request, so the synchronous per-word phonemization path never awaits.

`SYN-005` returns total duration, per-word and per-phoneme spans, sentence
ranges, the effective parameter set and the voice, with `word(at:)` and
`phoneme(at:)` queries for verse highlighting and lip-sync. Timings derive from
the prosody model's predicted phoneme durations — the same values that drive the
acoustic model — so the metadata describes the audio produced rather than an
independent estimate. The `marks` array is present and always empty until
`TXT-040` parses `<mark>` tags; likewise `diagnostics` awaits `TXT-041`. Both
requirements are therefore recorded as partial rather than complete.

Part III is where the bulk of the remaining work sits. `TXT-020` through
`TXT-024` (lexicon, heteronyms, user pronunciations) are the largest block and
are prerequisites for the acoustic model being useful, since a trained voice
saying the wrong phonemes is not an improvement.

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
