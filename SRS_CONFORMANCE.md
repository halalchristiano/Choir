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
| `VOX-P-006` gender via F0 *and* formant scale | MUST | Implemented, **1 defect** | `testGenderDirection`, `testGenderSeparationAdultBands` |
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

## Specification defects found

Four conflicts between §7's per-band realization rules and §8's binding
per-voice profiles surfaced the first time the conformance tests ran. Three are
resolved by the specification's own tolerance; one is not.

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

### Unresolved — `VOX-P-006` versus §8 in the child band

**`VOX-P-006` requires** female formant scale approximately **+15–20%** above
male within the same age band. Measured across §8's profiles:

| Band | Mean male | Mean female | Separation | Meets VOX-P-006 |
|---|---|---|---|---|
| Child | 1.1775 | 1.2175 | **+3.4%** | **No** |
| Young Adult | 0.9950 | 1.1625 | +16.8% | Yes |
| Middle-Aged | 0.9800 | 1.1350 | +15.8% | Yes |
| Elderly | 0.9862 | 1.1050 | +12.0% | Approximately |

The child band misses by a wide margin. This is not a tolerance question:
`QUA-008` sets tolerances for F0 and tempo, not formant scale, and +3.4%
against +15% is far outside any of them.

**Assessment.** §8's values are the physically defensible ones. Pre-pubertal
vocal tracts differ little by sex, which is why child voices are distinguished
chiefly by F0 and prosody rather than by vocal-tract length. `VOX-P-006` reads
as an adult-band generalization applied too broadly.

**Recommendation.** Amend `VOX-P-006` to exempt the child band, rather than
re-tune the eight child profiles, which are binding under §8 and acoustically
sound. Pending that decision, the deviation is pinned by
`testChildBandFormantSeparationDeviation` so it cannot drift unnoticed, and the
test carries instructions to retire it once the requirement is clarified.

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
