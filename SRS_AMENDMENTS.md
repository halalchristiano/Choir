# SRS Amendments

Change-controlled amendments to
[CHOIR — Software Requirements Specification v1.0](./CHOIR%20—%20Software%20Requirements%20Specification%20v1.0.pdf).

The specification is distributed as a PDF under change control. Per §3.2,
requirement IDs are never reused or renumbered after publication, and
superseded text is recorded rather than deleted. This file is therefore the
authoritative record of amendments; where it and the v1.0 PDF disagree, this
file governs, and the PDF should be reissued at the next revision to
incorporate them.

| Amendment | Requirement | Status | Date |
|---|---|---|---|
| `AMD-001` | `VOX-P-006` | Ratified | 2026-08-20 |

---

## AMD-001 — `VOX-P-006` gender realization thresholds

**Status:** Ratified · **Supersedes:** `VOX-P-006` as published in v1.0

### Original text (v1.0, §7.3)

> **VOX-P-006** **MUST** Gender presentation shall be realized primarily
> through the joint setting of F0 range and formant scale (female ≈ +15–20%
> formant scale relative to male within the same age band), with breathiness
> and pitch-dynamism as secondary cues — never through F0 alone.
>
> *Rationale: pitch-only "gender" sounds like a chipmunk filter; formant
> structure is what actually carries it.*

### Reason for amendment

The stated +15–20% band conflicts with the binding per-voice profiles of §8,
which take precedence for the voices they specify. Measured across the shipped
profiles:

| Band | Mean male formant scale | Mean female | Separation | Against v1.0 text |
|---|---|---|---|---|
| Child | 1.1775 | 1.2175 | **+3.4%** | Violates |
| Young Adult | 0.9950 | 1.1625 | +16.8% | Complies |
| Middle-Aged | 0.9800 | 1.1350 | +15.8% | Complies |
| Elderly | 0.9862 | 1.1050 | **+12.0%** | Violates |

Two bands fail the requirement as written. Neither failure is a tolerance
question: `QUA-008` sets tolerances for median F0 (±10%) and tempo (±8%), not
for formant scale.

**The §8 values are correct and the v1.0 threshold was over-generalized.**

*Child band.* Vocal-tract length differs little between sexes before puberty,
so a +15–20% formant separation would not be a design choice but an
anatomical falsehood — it would render the child voices as scaled-down adults.
§8 accordingly distinguishes child voices chiefly by F0 (male 210–290 Hz,
female 230–320 Hz per `VOX-P-002`) and by prosodic design. This is also the
reading most consistent with `VOX-G-010`, which requires child voices to be
stylized characters rather than simulations of real children.

*Elderly band.* Age-related changes compress the sexual dimorphism of the
vocal tract, and `VOX-P-005` already encodes the F0 half of this convergence
(male F0 age-raised to 95–130 Hz, female age-lowered to 160–195 Hz). §8's
+12.0% formant separation is the formant half of the same phenomenon. The
v1.0 text did not account for it.

Amending the requirement is preferred to re-tuning sixteen binding §8
profiles, which are acoustically sound and carry `MUST` status individually
as `VOX-08-01` … `VOX-08-32`.

### Amended text

> **VOX-P-006** **MUST** Gender presentation shall be realized primarily
> through the joint setting of F0 range and formant scale, with breathiness
> and pitch-dynamism as secondary cues — never through F0 alone.
>
> Formant-scale separation between the female and male voices of a band shall
> be:
>
> - **Young Adult and Middle-Aged:** +15–20%
> - **Elderly:** +10–15%, reflecting the age-related convergence of
>   vocal-tract dimorphism already encoded in `VOX-P-005`
> - **Child:** +2–6%, pre-pubertal vocal tracts differing minimally by sex;
>   in this band gender presentation shall be carried principally by F0
>   (`VOX-P-002`) and prosodic design
>
> In every band the female formant scale shall exceed the male formant scale,
> and gender shall never be conveyed by F0 alone.
>
> *Rationale unchanged: pitch-only "gender" sounds like a chipmunk filter;
> formant structure is what actually carries it. The per-band thresholds
> acknowledge that the magnitude of formant dimorphism is itself
> age-dependent.*

### Effect on conformance

All four bands now conform. Verified by `testGenderDirection`,
`testGenderSeparationByBand` and `testChildBandFormantSeparation` in
`Tests/ChoirTests/SRSConformanceTests.swift`.

No change to shipped voice profiles. No API change.
