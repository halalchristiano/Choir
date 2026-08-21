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
| `TXT-020` 120,000-word lexicon, ≥92% OOV accuracy | MUST | **Partial** | Lexicon implemented — 135,166 CMUdict entries with stress, 8 tests in `BuiltInLexiconTests`. The ≥92% OOV accuracy target is unmeasured: it needs a held-out test set |
| `TXT-021` ≥60 heteronyms disambiguated by part of speech | MUST | Implemented | 79 heteronyms, 7 tests in `HeteronymTests` |
| `TXT-022` runtime user lexicon API | MUST | Implemented | 9 tests in `UserLexiconTests` |
| `TXT-023` biblical/theological proper-noun supplement (≥2,500) | SHOULD | **Partial** | 111 curated entries against a target of 2,500; 6 tests in `TheologicalLexiconTests` |
| `TXT-024` documented, stable phoneme inventory | MUST | Implemented | 39 phonemes, ARPAbet↔IPA, 8 tests in `PhonemeInventoryTests` |
| `TXT-030` sentence and phrase segmentation | MUST | Implemented | 10 tests in `SegmentationTests` — abbreviations, initials, decimals, dialogue punctuation, `PhraseBoundary` strength |
| `TXT-031` breath groups for long sentences | MUST | Implemented | 9 tests in `BreathGroupTests` — word cap and duration ceiling |
| `TXT-032` paragraph/section pauses and pitch reset | SHOULD | **Partial** | `PhraseBoundary` carries pause length and a pitch-reset flag; the prosody model does not yet act on them |
| `TXT-040` SSML-C dialect | MUST | Implemented | 13 tests in `SSMLCParsingTests` — all seven tag types, nestable prosody |
| `TXT-041` graceful degradation + markup diagnostics | MUST | Implemented | 9 tests in `SSMLDegradationTests` — degradation, diagnostics, strict mode |
| `TXT-042` `<voice>` mid-text switching | MUST | **Partial** | Parsed and carried per segment (`testVoiceSwitching`); synthesis does not yet render segments in different voices |
| `SYN-002` deterministic output given a seed | MUST | Implemented | 8 tests in `DeterminismTests` |
| `SYN-003` controlled variation without a seed | MUST | Implemented | `testUnseededVaries`, `testVariationBounded` — **was violated**: every render was bit-identical |
| `SYN-005` timing metadata (per word/phoneme, marks) | MUST | Implemented | 14 tests across `SynthesisMetadataTests` and `SynthesisMarkTests` |
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
independent estimate. `marks` and `diagnostics` are now populated from the SSML-C stream, so
`SYN-005` is complete. A mark sits between words, so its time is the start of
the following word, or the end of the audio when it trails the final word.

Part III is where the bulk of the remaining work sits. `TXT-020` through
`TXT-024` (lexicon, heteronyms, user pronunciations) are the largest block and
are prerequisites for the acoustic model being useful, since a trained voice
saying the wrong phonemes is not an improvement.

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


### The lexicon block

`TXT-020` is satisfied by vendoring CMUdict (135,166 entries, 15,166 above the
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


### Known issue — two markup parsers

`SSMLCParser` implements the SSML-C dialect that `TXT-040`/`TXT-041` specify.
The older `SSMLParser` remains in place because `LinguisticFrontend` still
depends on it for segment styling, so the package currently carries two markup
parsers: one specification-conformant, one not.

The synthesis path reads marks and diagnostics from `SSMLCParser`, so the
metadata is correct, but text styling still flows through the older parser and
therefore ignores `phoneme`, `say-as` and `voice`. Migrating the front end is
the next step and is deliberately not bundled with this change, because it
alters phonemization output and wants its own diff.


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
