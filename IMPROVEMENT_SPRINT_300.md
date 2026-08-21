# Choir improvement sprint — items 201–300

This ledger records the third non-duplicative set of 100 completed improvements. Items 1–100 and 101–200 remain in `IMPROVEMENT_SPRINT_100.md` and `IMPROVEMENT_SPRINT_200.md`. Regression evidence for this set is in `Tests/ChoirTests/ImprovementSprintThreeTests.swift`.

## Prosody value integrity

- [x] 201. Make `ProsodyFeatures` equatable and codable.
- [x] 202. Replace non-finite fundamental frequency with the documented default.
- [x] 203. Replace non-finite segment duration with the documented default.
- [x] 204. Replace non-finite energy with the documented default.
- [x] 205. Replace non-finite voicing probability with the documented default.
- [x] 206. Clamp fundamental frequency to 50...400 Hz.
- [x] 207. Clamp segment duration to 10...500 ms.
- [x] 208. Clamp energy to -60...0 LUFS.
- [x] 209. Clamp voicing probability to 0...1.
- [x] 210. Normalize unknown pitch-accent labels to `none`.
- [x] 211. Normalize unknown boundary-tone labels to `none`.
- [x] 212. Make annotated phonemes equatable and codable.
- [x] 213. Make timing information equatable and codable.
- [x] 214. Replace non-finite timing starts with zero.
- [x] 215. Prevent negative timing starts.
- [x] 216. Replace non-finite timing ends with the sanitized start.
- [x] 217. Prevent timing ends from preceding their starts.
- [x] 218. Add timing midpoint and empty-state queries.
- [x] 219. Add finite, half-open timing containment queries.
- [x] 220. Add safe timing shifts that cannot create negative spans.
- [x] 221. Remove non-finite contour points.
- [x] 222. Sort contour points chronologically.
- [x] 223. Resolve duplicate contour times deterministically by keeping the last value.
- [x] 224. Normalize unsupported interpolation names to linear.
- [x] 225. Make interpolation names case-insensitive.
- [x] 226. Implement true step interpolation.
- [x] 227. Reject non-finite contour query times.
- [x] 228. Add contour empty, time-range, duration, minimum, and maximum queries.
- [x] 229. Calculate utterance duration from the latest phoneme end rather than array order.
- [x] 230. Add duration-count and invalid-duration structural validation to prosody descriptions.

## Voice-quality analysis

- [x] 231. Make quality metrics equatable and codable.
- [x] 232. Add a public, sanitizing quality-metric initializer.
- [x] 233. Replace non-finite loudness values with safe silence values.
- [x] 234. Prevent negative reported peak magnitudes.
- [x] 235. Replace non-finite or negative dynamic range with zero.
- [x] 236. Replace non-finite or negative SNR with zero.
- [x] 237. Clamp clipping percentage to 0...100.
- [x] 238. Replace non-finite or negative zero-crossing rate with zero.
- [x] 239. Add peak dBFS, clipping-fraction, and silence queries.
- [x] 240. Prevent silent audio from producing negative-infinite dynamic range.
- [x] 241. Prevent silent audio from producing negative SNR.
- [x] 242. Prevent invalid sample rates from producing infinite zero-crossing rates.
- [x] 243. Keep full-scale negative PCM analysis within representable peak bounds.
- [x] 244. Make quality reports equatable and codable.
- [x] 245. Clamp quality-report ratings to 1...5 and replace non-finite ratings.
- [x] 246. Prevent five-star reports from computing a negative empty-star count.
- [x] 247. Add issue count, issue presence, and recommended-use queries.
- [x] 248. Render silent peak level as negative infinity rather than `nan` in reports.

## Number, Roman-numeral, date, and time expansion

- [x] 249. Spell negative integer strings instead of returning them unchanged.
- [x] 250. Trim numeric-string whitespace before integer parsing.
- [x] 251. Spell negative `Int64` values with a `minus` prefix.
- [x] 252. Spell `Int64.min` without magnitude overflow.
- [x] 253. Add quadrillion-scale number spelling.
- [x] 254. Add quintillion-scale number spelling.
- [x] 255. Preserve grammatical ordinal conversion for negative values.
- [x] 256. Reject non-canonical subtractive Roman numerals.
- [x] 257. Reject repeated Roman forms such as `IIII`.
- [x] 258. Preserve case-insensitive parsing for canonical Roman numerals.
- [x] 259. Reject 13...23 hour values when an AM/PM suffix is present.
- [x] 260. Validate month-specific day counts in ISO dates.
- [x] 261. Validate month-specific day counts in slash dates.
- [x] 262. Apply the Gregorian divisible-by-400 leap-year rule.
- [x] 263. Reject century leap days not divisible by 400.

## Sentence and breath-group segmentation

- [x] 264. Add nominal pause seconds to phrase boundaries.
- [x] 265. Add document-boundary classification to phrase boundaries.
- [x] 266. Trim outer whitespace when constructing breath groups.
- [x] 267. Add breath-group empty-state.
- [x] 268. Report zero syllables for empty text.
- [x] 269. Report zero syllables for punctuation-only text.
- [x] 270. Return finite zero duration for non-finite speaking tempo.
- [x] 271. Clamp the maximum breath-group word count to at least one.
- [x] 272. Replace non-finite breath-duration ceilings with nine seconds.
- [x] 273. Replace non-positive breath-duration ceilings with nine seconds.
- [x] 274. Keep ellipses attached to their sentence.
- [x] 275. Keep combined `?!` and `!?` punctuation attached to their sentence.
- [x] 276. Allow terminal abbreviations such as `etc.` to end before a capitalized sentence.
- [x] 277. Keep personal titles non-terminal before names.
- [x] 278. Keep Scripture and month abbreviations non-terminal before their values.
- [x] 279. Return no breath groups for empty input.
- [x] 280. Replace invalid segmentation tempo with a safe default.

## Explainable intelligibility scoring

- [x] 281. Normalize curly apostrophes while preserving contraction distinctions.
- [x] 282. Convert ASCII, non-breaking, en, and em hyphens into word boundaries.
- [x] 283. Add a codable edit-operation model for matches, substitutions, deletions, and insertions.
- [x] 284. Add a codable word-error breakdown result.
- [x] 285. Report reference and hypothesis word counts separately.
- [x] 286. Report substitution, deletion, insertion, and correct-word counts separately.
- [x] 287. Expose total errors, exact-match state, WER, and accuracy on breakdowns.
- [x] 288. Add deterministic dynamic-programming word alignment.
- [x] 289. Preserve word order in returned alignment operations.
- [x] 290. Route the existing WER API through the explainable breakdown.
- [x] 291. Route the existing accuracy API through the explainable breakdown.
- [x] 292. Add hypothesis count and separate error counts to sentence scores.
- [x] 293. Add total-error and exact-match queries to sentence scores.
- [x] 294. Add corpus word/error totals and exact-sentence accuracy to intelligibility reports.
- [x] 295. Add failed-sentence and empty-report queries.
- [x] 296. Trim, remove empty entries, and de-duplicate harness corpora.
- [x] 297. Propagate recognizer failures instead of converting them into false zero scores.

## G2P evaluation evidence

- [x] 298. Sanitize impossible G2P report counts and expose missing/invalid reference counts.
- [x] 299. Reject malformed ARPAbet ground truth and expose PER, skipped words, inexact matches, and usable-sample state.
- [x] 300. Make zero/negative sampling empty and distribute deterministic samples across the full sorted lexicon.

## Verification

- This ledger contains exactly 100 checked items, numbered 201–300.
- `ImprovementSprintThreeTests.swift` adds 76 focused regression tests.
- Existing breath-group tests now encode the corrected zero-syllable behavior for empty input.
- `git diff --check` must pass before publication.
- GitHub Actions remains the authoritative Swift 6.3 build and test gate.
