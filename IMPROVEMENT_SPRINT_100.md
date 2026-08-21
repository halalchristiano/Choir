# CHOIR 100-improvement sprint

**Branch:** `agent/choir-100-improvements`
**Date:** 21 August 2026

This ledger records 100 bounded changes completed in this sprint. A checked
item means the repository change exists; it does not mean the missing
production models, trained voices, listening tests, or device conformance have
been completed.

## Phoneme and voice identity

- [x] 001. Canonicalize ASCII `g` phoneme input to IPA U+0261 script-g.
- [x] 002. Use script-g in the internal English consonant set.
- [x] 003. Derive `PhonemeEncoder` vocabulary from `PhonemeInventory`.
- [x] 004. Add strict phoneme encoding that throws on unknown symbols.
- [x] 005. Add strict phoneme decoding that throws on unknown indices.
- [x] 006. Report unknown phoneme symbols once in first-seen order.
- [x] 007. Give every advertised voice a unique conditioning ID.
- [x] 008. Make the 32 conditioning IDs explicit and stable.
- [x] 009. Pass the unique voice conditioning ID into acoustic input.
- [x] 010. Honor a single explicit SSML voice run instead of discarding it.

## Acoustic tensor integrity

- [x] 011. Reject empty acoustic-model input.
- [x] 012. Require all phoneme-aligned tensors to have equal lengths.
- [x] 013. Reject negative phoneme indices.
- [x] 014. Require finite, positive phoneme durations.
- [x] 015. Require finite, non-negative fundamental frequencies.
- [x] 016. Require finite energy values.
- [x] 017. Restrict stress values to 0, 1, or 2.
- [x] 018. Restrict finite voicing values to `0...1`.
- [x] 019. Reject negative voice IDs.
- [x] 020. Validate the complete tensor contract before model inference.

## Model and pipeline behavior

- [x] 021. Make mock acoustic features deterministic for identical inputs.
- [x] 022. Clamp invalid mock frame-rate and frequency-bin configuration.
- [x] 023. Report missing Core ML assets as `modelLoadFailed`.
- [x] 024. Allow callers to inject a configured pipeline into `ChoirEngine`.
- [x] 025. Expose whether acoustic feature frames are rectangular.
- [x] 026. Expose whether acoustic feature values are all finite.
- [x] 027. Make zero-frame-rate feature duration safe.
- [x] 028. Validate audio format before direct pipeline synthesis.
- [x] 029. Expose the acoustic input row count.
- [x] 030. Preserve strict input validation in both audio and metadata paths.

## Engine lifecycle and errors

- [x] 031. Add a distinct `ChoirError.engineBusy` case.
- [x] 032. Assign busy a new code without renumbering existing stable codes.
- [x] 033. Add actionable recovery guidance for engine contention.
- [x] 034. Classify engine contention as retryable.
- [x] 035. Give engine contention a distinct localized description.
- [x] 036. Make state validation distinguish uninitialized, busy, and error states.
- [x] 037. Enter the initializing state during initialization.
- [x] 038. Persist invalid-format initialization as a typed error state.
- [x] 039. Make `clearCache()` release the idle initialized pipeline.
- [x] 040. Support clean reinitialization after pipeline release.

## Chunk delivery safety

- [x] 041. Add public `StreamingOptions` validation.
- [x] 042. Validate streaming options before engine work starts.
- [x] 043. Validate chunk size inside direct streaming-pipeline use.
- [x] 044. Reject a zero chunk size.
- [x] 045. Reject a negative chunk size.
- [x] 046. Avoid overflow when calculating the next chunk boundary.
- [x] 047. Check cancellation between emitted chunks.
- [x] 048. Document that callbacks begin after full rendering.
- [x] 049. Document callback-overhead tradeoffs without false latency claims.
- [x] 050. Define eight concrete gates for genuine progressive streaming.

## Audio format and export

- [x] 051. Implement WAV export through `ChoirEngine.exportAudio`.
- [x] 052. Validate sample-rate bounds before PCM/WAV work.
- [x] 053. Validate channel-count bounds before PCM/WAV work.
- [x] 054. Reject unsupported PCM bit depths.
- [x] 055. Reject incomplete interleaved channel frames.
- [x] 056. Reject RIFF payloads that exceed the 32-bit WAV size field.
- [x] 057. Remove force-unwrapped string encoding from WAV headers.
- [x] 058. Make unavailable MP3 export throw instead of returning empty data.
- [x] 059. Make unavailable AAC and FLAC export throw instead of returning empty data.
- [x] 060. Validate compressed-codec bitrate requests.

## Cache correctness

- [x] 061. Prevent acoustic-feature replacement from double-counting size.
- [x] 062. Prevent transcription replacement from double-counting size.
- [x] 063. Prevent prosody replacement from double-counting size.
- [x] 064. Allow LRU eviction when only transcription entries exist.
- [x] 065. Allow LRU eviction when only prosody entries exist.
- [x] 066. Refuse oversized feature entries that cannot fit the cache.
- [x] 067. Refuse oversized transcription and prosody entries.
- [x] 068. Clamp negative cache capacity to zero.
- [x] 069. Bound reported utilization to `0...100`.
- [x] 070. Report remaining capacity and whether the cache is empty.

## Regression coverage

- [x] 071. Add full public-phoneme-inventory round-trip coverage.
- [x] 072. Add ASCII/script-g canonicalization coverage.
- [x] 073. Add uniqueness and contiguous-range tests for all 32 voice IDs.
- [x] 074. Add a recording-model test for single-run SSML voice selection.
- [x] 075. Add invalid acoustic tensor tests for every validated field.
- [x] 076. Add deterministic and invalid-dimension mock-model tests.
- [x] 077. Add audio-format boundary and safe-duration tests.
- [x] 078. Add WAV, codec-failure, and bitrate regression tests.
- [x] 079. Add cache replacement, eviction, oversize, and capacity tests.
- [x] 080. Add engine clear, reinitialize, error-state, and busy-error tests.

## Public API documentation truth

- [x] 081. Update README status from v0.1.0 to v0.15.0 pre-alpha.
- [x] 082. Replace nonexistent README voice aliases with real enum cases.
- [x] 083. State that the default path uses both mock acoustic and mock vocoder components.
- [x] 084. Replace README real-time claims with post-render chunk-delivery wording.
- [x] 085. Rewrite Getting Started against APIs that actually compile.
- [x] 086. Rewrite Error Handling against the real `ChoirError` cases and codes.
- [x] 087. Rewrite the Streaming guide around actual current behavior.
- [x] 088. Rewrite the platform guide to separate declared targets from verification.
- [x] 089. Rewrite voice blending as parameter interpolation, not timbre morphing.
- [x] 090. Rewrite performance guidance to reject mock-based product claims.

## Status and release documentation

- [x] 091. Replace the “ready for production” project status with a truthful pre-alpha report.
- [x] 092. Correct benchmark documentation to name the default mock vocoder.
- [x] 093. Correct development documentation to current deployment targets.
- [x] 094. Update DocC from v0.2.0 to v0.15.0.
- [x] 095. Correct DocC real-time streaming wording.
- [x] 096. Update package-install examples to version 0.15.0.
- [x] 097. Document iOS 17, macOS 14, watchOS 10, visionOS 1, and tvOS 17 minimums.
- [x] 098. Mark physical-device platform conformance as unverified.
- [x] 099. State that infrastructure test success is not speech-quality evidence.
- [x] 100. Record all completed work in this exact, auditable 100-item ledger.

## Verification limits

`git diff --check` and repository-level static inspections can run in the
current environment. Swift is not installed here, so compilation and tests
must be verified by GitHub Actions before this branch is merged.
