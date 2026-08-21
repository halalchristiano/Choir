# Choir improvement sprint — items 301–400

This ledger records the fourth non-duplicative set of 100 completed improvements. Items 1–300 remain in `IMPROVEMENT_SPRINT_100.md`, `IMPROVEMENT_SPRINT_200.md`, and `IMPROVEMENT_SPRINT_300.md`. Regression evidence for this set is split across the four `ImprovementSprintFour*Tests.swift` files.

## Frame-safe audio processing and export

- [x] 301. Report whether an interleaved audio buffer ends on a complete frame.
- [x] 302. Count samples trailing after the last complete interleaved frame.
- [x] 303. Add overflow-safe sample lookup by frame and channel.
- [x] 304. Add complete-frame lookup without exposing interleaved index arithmetic.
- [x] 305. Report normalized peak amplitude for an individual channel.
- [x] 306. Report normalized signed DC offset for an audio buffer.
- [x] 307. Report normalized mean absolute amplitude for an audio buffer.
- [x] 308. Calculate a bounded, non-finite-safe silence ratio.
- [x] 309. Trim silent leading and trailing frames without breaking multichannel alignment.
- [x] 310. Slice audio by validated frame ranges while preserving its format.
- [x] 311. Split audio into bounded, frame-aligned chunks.
- [x] 312. Reject non-positive split limits and malformed source buffers.
- [x] 313. Concatenate compatible audio buffers with overflow-safe capacity planning.
- [x] 314. Reject concatenation across mismatched formats or incomplete frames.
- [x] 315. Expose an equatable, codable kind for every audio-output representation.
- [x] 316. Retrieve encoded output bytes without an exhaustive case switch.
- [x] 317. Retrieve raw PCM output without an exhaustive case switch.
- [x] 318. Validate streaming chunks against their PCM format and channel alignment.
- [x] 319. Calculate finite streaming-chunk end timestamps.
- [x] 320. Expose the WAV header size and predict encoded byte counts before allocation.
- [x] 321. Preallocate WAV and raw PCM output storage from safe byte counts.
- [x] 322. Add a validated raw-PCM encoding path.
- [x] 323. Assemble streaming chunks into WAV while rejecting early final markers and overlapping timestamps.
- [x] 324. Validate effect names and every effect parameter against safe signal-processing envelopes.
- [x] 325. Validate and process whole audio buffers through effect chains while preserving PCM metadata.

## Sample-based voice synthesis

- [x] 326. Add value equality for phoneme recordings.
- [x] 327. Replace unsupported recording sample rates with a safe default.
- [x] 328. Replace negative and non-finite recording pitches with zero.
- [x] 329. Trim and canonicalize recording phoneme keys.
- [x] 330. Expose direct recording sample counts.
- [x] 331. Expose exact recording PCM byte counts.
- [x] 332. Expose recording empty-state inspection.
- [x] 333. Measure normalized recording peaks without overflowing on full-scale negative PCM.
- [x] 334. Measure normalized recording RMS amplitude.
- [x] 335. Trim voice names and supply a stable fallback for blank names.
- [x] 336. Reject empty and keyless recordings from voice libraries.
- [x] 337. Canonicalize voice-library lookup keys.
- [x] 338. Retrieve every recorded variant for a phoneme.
- [x] 339. Select the recorded variant nearest a preferred pitch.
- [x] 340. Remove all variants for a phoneme atomically.
- [x] 341. Clear a voice library and report the number of removed recordings.
- [x] 342. Add value equality for voice-library statistics.
- [x] 343. Report exact PCM byte totals in voice-library statistics.
- [x] 344. Linearly resample recordings whose rates differ from the output rate.
- [x] 345. Replace incoming-only fades with true overlap crossfades.
- [x] 346. Sanitize synthesizer sample-rate and fade configuration.
- [x] 347. Preserve intentionally quiet audio instead of normalizing it to full scale.
- [x] 348. Add cooperative cancellation checks throughout sample synthesis.
- [x] 349. Bound and sanitize synthetic recording-generator inputs.
- [x] 350. Make simple synthesis honor configured sample-rate and fade settings in its output format.

## Linguistic normalization and stress integrity

- [x] 351. Make normalization policies and normalizers codable, hashable value types.
- [x] 352. Collapse all Unicode whitespace runs consistently in prose and verbatim modes.
- [x] 353. Prevent contraction expansion inside larger lexical tokens.
- [x] 354. Prevent abbreviation expansion inside larger lexical tokens.
- [x] 355. Use singular grammar for exactly one dollar.
- [x] 356. Speak fractional currency as dollars and cents.
- [x] 357. Accept canonically comma-grouped dollar amounts.
- [x] 358. Accept negative currency signs before or after the dollar symbol.
- [x] 359. Add a validated, canonical, codable Scripture-reference value type.
- [x] 360. Extract structured Scripture references in source order.
- [x] 361. Add public rendering of validated Scripture references.
- [x] 362. Accept whitespace around Scripture-reference colons.
- [x] 363. Accept fullwidth colons in Scripture references.
- [x] 364. Preserve enclosing punctuation during Scripture expansion.
- [x] 365. Reject zero-valued Scripture chapters and verses.
- [x] 366. Enforce book-specific canonical chapter ceilings.
- [x] 367. Enforce the canon-wide maximum verse number.
- [x] 368. Reject descending verse ranges without partially rewriting them.
- [x] 369. Apply corrected lexical stress patterns to vowel nuclei rather than raw phoneme offsets.
- [x] 370. Ensure rule-based assignment never stresses consonants.
- [x] 371. Clamp custom stress levels to the supported 0...2 range.
- [x] 372. Normalize custom-pattern keys and lookup words consistently.
- [x] 373. Preserve authoritative vowel stress while repairing consonant stress.
- [x] 374. Fall back to rule-based assignment for empty custom patterns.
- [x] 375. Expose sanitized stress-pattern lookup publicly.

## Benchmark evidence and deterministic corpora

- [x] 376. Add typed pass, fail, untargeted, and invalid benchmark judgements.
- [x] 377. Clamp negative benchmark sample counts to zero.
- [x] 378. Discard non-finite measurement-range endpoints.
- [x] 379. Normalize reversed measurement ranges.
- [x] 380. Validate measurement metadata, sample counts, and range coherence.
- [x] 381. Prevent non-finite measurement values or targets from passing.
- [x] 382. Expose signed target margins with consistent pass-positive semantics.
- [x] 383. Expose passed measurements on benchmark reports.
- [x] 384. Keep invalid evidence separate from genuine target failures.
- [x] 385. Expose valid untargeted measurements on benchmark reports.
- [x] 386. Expose invalid measurements on benchmark reports.
- [x] 387. Calculate target pass rate from valid targeted evidence only.
- [x] 388. Make all-targets-met require at least one valid targeted measurement.
- [x] 389. Add trimmed, case-insensitive requirement lookup.
- [x] 390. Add deterministic requirement and measurement ordering with stable duplicate order.
- [x] 391. Render benchmark numbers with fixed POSIX decimal formatting.
- [x] 392. Escape and line-fold caller-provided Markdown report fields.
- [x] 393. Include categorical pass, fail, untargeted, and invalid counts in Markdown reports.
- [x] 394. Ignore non-finite samples when calculating medians.
- [x] 395. Prevent overflow when averaging even-sized median pairs.
- [x] 396. Add finite-only interpolated percentiles with quantile validation.
- [x] 397. Add finite-only unbiased sample standard deviation using Welford's algorithm.
- [x] 398. Parse reference devices from trimmed, case-insensitive IDs or display names.
- [x] 399. Add safe one-based Harvard sentence-list lookup.
- [x] 400. Add deterministic, unique, balanced, and bounded seeded Harvard corpus selection.

## Verification

- This ledger contains exactly 100 checked items, numbered 301–400.
- The four `ImprovementSprintFour*Tests.swift` files add exactly 100 focused regression tests, 25 per improvement area.
- `git diff --check` must pass before publication.
- GitHub Actions remains the authoritative Swift 6.3 build and multi-platform test gate because this workspace has no local Swift toolchain.
