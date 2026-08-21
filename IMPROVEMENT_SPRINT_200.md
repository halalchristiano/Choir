# Choir improvement sprint — items 101–200

This ledger records the second, non-duplicative set of 100 completed improvements. The first set remains in [`IMPROVEMENT_SPRINT_100.md`](IMPROVEMENT_SPRINT_100.md). Each item below is implemented in production code and, where practical, exercised by `ImprovementSprintTwoTests.swift`.

## SSML-C correctness and recovery

- [x] 101. Clamp explicitly negative break durations to zero when resolved.
- [x] 102. Replace non-finite resolved break durations with the medium default.
- [x] 103. Diagnose closing tags that have no tag name.
- [x] 104. Diagnose attributes placed on closing tags.
- [x] 105. Leave the style stack intact when an unmatched closing tag appears.
- [x] 106. Find the actual matching opener when closing malformed nested markup.
- [x] 107. Close intervening nested styles during mismatched-tag recovery.
- [x] 108. Report which intervening tags were implicitly closed.
- [x] 109. Diagnose invalid explicit break times instead of silently dropping them.
- [x] 110. Diagnose unknown break strengths instead of silently dropping them.
- [x] 111. Make invalid break scalars throw in strict parsing mode.
- [x] 112. Trim whitespace around mark names.
- [x] 113. Diagnose whitespace-only mark names distinctly from missing names.
- [x] 114. Decode decimal XML numeric character references.
- [x] 115. Decode hexadecimal XML numeric character references.
- [x] 116. Preserve single-pass decoding for double-escaped numeric references.
- [x] 117. Reject negative parsed SSML durations.
- [x] 118. Reject non-finite parsed SSML durations.
- [x] 119. Reject non-finite prosody pitch offsets.
- [x] 120. Reject zero, negative, and non-finite prosody rates.
- [x] 121. Reject non-finite prosody volume offsets.

## DSP and audio safety

- [x] 122. Map non-finite PCM narrowing inputs to silence instead of trapping.
- [x] 123. Make high-pass filtering a no-op for invalid sample rates.
- [x] 124. Make high-pass filtering a no-op for invalid cutoff values.
- [x] 125. Constrain high-pass cutoffs below Nyquist.
- [x] 126. Avoid allocating filter output for empty high-pass input.
- [x] 127. Make low-pass filtering a no-op for invalid sample rates.
- [x] 128. Make low-pass filtering a no-op for invalid cutoff values.
- [x] 129. Constrain low-pass cutoffs below Nyquist.
- [x] 130. Avoid allocating filter output for empty low-pass input.
- [x] 131. Replace non-finite normalization targets with the documented default.
- [x] 132. Clamp normalization targets to the documented -20...0 dB range.
- [x] 133. Replace non-finite soft-clip thresholds with the documented default.
- [x] 134. Clamp soft-clip thresholds to the 0...1 envelope before Int16 conversion.
- [x] 135. Make de-essing a no-op for empty input.
- [x] 136. Make de-essing a no-op for invalid sample rates.
- [x] 137. Make de-essing a no-op for invalid center frequencies.
- [x] 138. Replace non-finite compressor thresholds with a safe default.
- [x] 139. Clamp compressor thresholds to a safe decibel envelope.
- [x] 140. Prevent compressor ratios below 1 from expanding the signal.
- [x] 141. Replace non-finite compressor ratios with unity.
- [x] 142. Make reverb a no-op for invalid sample rates and empty input.
- [x] 143. Clamp reverb wet mix to 0...1.
- [x] 144. Replace non-finite reverb wet mix with a dry signal.

## Audio value APIs

- [x] 145. Expose effect count on audio effect chains.
- [x] 146. Expose whether an audio effect chain is empty.
- [x] 147. Expose ordered effect names for inspection and debugging.
- [x] 148. Expose the effect chain sample rate.
- [x] 149. Make audio formats equatable, hashable, and codable.
- [x] 150. Make streaming options equatable, hashable, and codable.
- [x] 151. Make audio buffers equatable.
- [x] 152. Expose raw PCM byte count on audio buffers.
- [x] 153. Expose empty-state on audio buffers.
- [x] 154. Expose normalized peak amplitude on audio buffers.
- [x] 155. Expose normalized RMS amplitude on audio buffers.
- [x] 156. Extract a requested channel from interleaved PCM safely.
- [x] 157. Reject out-of-range channel extraction without trapping.
- [x] 158. Validate audio-buffer format and interleaved frame alignment.
- [x] 159. Make audio outputs equatable and expose empty-state.
- [x] 160. Make audio chunks equatable.
- [x] 161. Sanitize negative and non-finite audio-chunk timestamps.
- [x] 162. Expose audio-chunk sample and byte counts.
- [x] 163. Expose audio-chunk empty-state and format-aware duration.

## Blending and parameter integrity

- [x] 164. Make voice-blending profiles equatable.
- [x] 165. Treat a non-finite blend factor as the first endpoint.
- [x] 166. Preserve the nearer endpoint's deterministic seed during blending.
- [x] 167. Make zero-step gender transitions return one valid source endpoint.
- [x] 168. Make negative-step gender transitions return one valid source endpoint.
- [x] 169. Derive gender-transition endpoints from the requested voices.
- [x] 170. Respect the requested gender-transition direction.
- [x] 171. Make zero-step age transitions return one valid source endpoint.
- [x] 172. Make negative-step age transitions return one valid source endpoint.
- [x] 173. Map age bands across the documented -5...5 age-shift envelope.
- [x] 174. Make speaking styles equatable.
- [x] 175. Add trimmed, case-insensitive predefined-style lookup.
- [x] 176. Replace every non-finite synthesis scalar with its documented default.
- [x] 177. Record non-finite parameter replacement as a clamping event.
- [x] 178. Keep non-finite clamping reports JSON-encodable.
- [x] 179. Add a public clamping initializer and explanatory reason.
- [x] 180. Add `validated()` to repair parameters after direct property mutation.

## Lexicon, inventory, timing, cache, and sessions

- [x] 181. Expose whether a user pronunciation has usable content.
- [x] 182. Ignore empty user-lexicon keys.
- [x] 183. Ignore empty user phoneme sequences and respellings.
- [x] 184. Trim and compact registered phoneme symbols.
- [x] 185. Trim registered respellings.
- [x] 186. Persist bulk lexicon registration once instead of once per entry.
- [x] 187. Avoid redundant persistence when clearing an already-empty lexicon.
- [x] 188. Expose deterministically sorted words on lexicon snapshots.
- [x] 189. Normalize ARPAbet case and surrounding whitespace.
- [x] 190. Add public ARPAbet-symbol validation.
- [x] 191. Add lossless ARPAbet conversion results with unknown-token reporting.
- [x] 192. Sanitize non-finite duration-estimator rates and result fields.
- [x] 193. Sanitize timed-span, mark, and total-duration bounds.
- [x] 194. Add timed-span midpoint, empty-state, and clamped progress queries.
- [x] 195. Make word and phoneme lookup correct even for unordered caller metadata.
- [x] 196. Add duplicate-mark, duration, diagnostic, and structural metadata queries.
- [x] 197. Add typed cache containment, deterministic key listing, and selective removal.
- [x] 198. Add total-count, utilization-fraction, and at-capacity cache statistics.
- [x] 199. Add guarded session start/reset, cache controls, and last-result statistics.
- [x] 200. Add deterministic session ordering and accurate async manager cache totals.

## Verification

- The ledger contains exactly 100 checked items (101–200).
- Regression coverage is in `Tests/ChoirTests/ImprovementSprintTwoTests.swift`.
- Existing gender-transition coverage was corrected to assert the requested male-to-female direction.
- `git diff --check` is required before publication.
- GitHub Actions is the authoritative Swift 6.3 build and test environment.
