# Maintenance Manual

Rebuild, validate, and release CHOIR without relying on unwritten project
knowledge.

> Important: The repository currently contains the Swift runtime and benchmark
> harness, but not the production training pipeline, licensed speech dataset,
> trained acoustic/vocoder checkpoints, Core ML conversion tools, or final
> voice assets. Sections below define the reproducibility contract those
> deliverables must satisfy; commands that exist today are labeled **current**.

## 1. Establish a clean release workspace

Record the candidate commit and build only from a clean checkout. Do not build
release assets from an uncommitted notebook or an operator's home directory.

**Current commands:**

```bash
git status --short
git rev-parse HEAD
swift --version
swift package resolve
swift test
swift build -c release
```

Archive the commit, tag candidate, Swift version, Xcode build, macOS build,
SDK versions, and dependency resolution. CHOIR has no third-party runtime
packages, but training dependencies must be locked separately when added.

## 2. Required reproducibility layout

Before production training begins, add version-controlled equivalents of:

```text
Training/
  configs/              immutable reviewed experiment configurations
  manifests/            licensed source and split manifests
  preprocessing/        deterministic resample/text/alignment pipeline
  acoustic/             model definition and training entry point
  vocoder/              model definition and training entry point
  evaluation/           objective and listening-set preparation
Conversion/
  export_coreml/        checkpoint-to-mlprogram conversion
  quantization/         candidate generation and comparison
Assets/
  manifests/            runtime asset manifests and hashes
  build/                deterministic packager, no checked-in scratch output
ReleaseEvidence/
  <version>/            reports referenced by the release tag
```

Directory names may differ, but every role must exist and every release
command must be derivable from one checked-in top-level runbook. Generated
secrets, licensed raw data, and large checkpoints may live in controlled
storage; their immutable IDs and checksums belong in the repository.

## 3. Create the data manifest

Every recording needs a stable ID and these fields:

- speaker/pseudonymous identity and assigned voice-family role;
- source URI or controlled-storage object version;
- SHA-256 digest, duration, sample rate, channels, and encoding;
- exact transcript plus transcript revision;
- language, accent, recording conditions, and quality flags;
- consent/license identifier, permitted commercial uses, restrictions, and
  withdrawal/deletion state;
- train/validation/test split fixed before model selection.

No person may appear in more than one split. Deduplicate text and near-duplicate
audio across splits. Keep the quality/MOS corpus separate from data used for
training or tuning. A manifest change creates a new dataset version and must
never mutate an already released version in place.

## 4. Preprocess deterministically

The preprocessing job must accept a dataset-manifest version and configuration
and emit a new immutable feature-manifest version. Pin and record:

1. decoder, channel policy, resampler, target rate, and amplitude policy;
2. silence/VAD, clipping, noise, and minimum/maximum-duration decisions;
3. text normalization revision and language/accent selection;
4. phoneme inventory revision, lexicon revision, and G2P revision;
5. aligner model/version and alignment rejection thresholds;
6. mel configuration, F0 extractor, energy measure, and frame/hop sizes;
7. every excluded item and machine-readable reason.

Re-running the same manifest/configuration must produce byte-identical
manifests and features or a documented deterministic-tolerance policy.

## 5. Train the acoustic model

The production training entry point must take only versioned inputs: config,
dataset/feature manifest, code commit, initialization checkpoint if any, and
seed. Its run record must include hardware, framework/CUDA/Metal versions,
optimizer/scheduler, batch/accumulation settings, precision, step count,
checkpoint cadence, losses, and interruption/resume history.

The conditioning design must allocate stable IDs for all 32 ``Voice`` cases
and make pitch, rate, emotion, breathiness, age, and gender controls genuine
trained inputs. Never infer a production voice from the metadata profiles
alone. Select a checkpoint using frozen validation criteria, then evaluate
exactly that checkpoint—do not copy or rename an unrecorded local result.

Required output record:

```text
run ID + source commit + config digest + data/feature manifest digests
+ seed + selected checkpoint digest + evaluation report IDs
```

## 6. Train the vocoder

Train at the engine-native 48 kHz output rate against acoustic features that
match the selected acoustic model contract. Record its receptive field and
lookahead, conditioning, losses, and checkpoint lineage. Evaluate clean,
breathy, rough, elderly, villain, sibilant, plosive, whisper-adjacent, and
long-sustained material—not only average narration.

A debug waveform generator, Griffin-Lim experiment, or mock vocoder is not a
release asset. The final vocoder must pass latency, artifact, stability,
intelligibility, and voice-character gates together.

## 7. Run checkpoint evaluation

Before conversion, freeze a candidate pair and run:

- pronunciation and held-out G2P sets;
- seeded determinism and repeat-without-seed variation checks;
- every voice at default and all documented envelope corners;
- standard artifact corpus, long-form stability render, and silence/click/DC
  checks;
- blinded naturalness/cleanliness MOS protocol;
- ASR intelligibility at default and envelope corners;
- voice-distinctness and villain neutral/warm capability studies;
- control monotonicity for pitch, rate, intensity, breathiness, age, and
  gender.

Archive raw observations and analysis, not only a pass/fail summary. A failed
mandatory gate rejects the checkpoint pair.

## 8. Convert to Core ML

The conversion tool must read the selected checkpoint by digest and export a
Core ML `mlprogram` with explicit, versioned tensor names, shapes, dtypes,
dynamic-range constraints, and state semantics. For each model:

1. export an unquantized reference;
2. run fixed vectors through training-runtime and Core ML implementations;
3. compare intermediate/output tensors under a stated tolerance;
4. generate each quantized candidate from that same reference;
5. run full quality, intelligibility, determinism, and performance deltas;
6. select quantization only when the documented quality ceiling holds;
7. record converter/tool versions, flags, source/checkpoint digest, output
   digest, compute-unit results, and report IDs.

Never accept a model because it loads. A successful load is only the first
conversion smoke test.

## 9. Build runtime asset packs

Create a deterministic manifest for every pack:

```json
{
  "schemaVersion": 1,
  "engineVersion": 1,
  "modelID": "acoustic-quality-v1",
  "modelSHA256": "…",
  "vocoderID": "vocoder-quality-v1",
  "vocoderSHA256": "…",
  "voiceIDs": ["choir.child.male.finch"],
  "phonemeInventoryVersion": 1,
  "lexiconVersion": "…",
  "minimumPackageVersion": "…"
}
```

The build must verify every input hash, reject unknown/duplicate IDs, stage to
a fresh directory, sign/package where required, compute final hashes, and
verify by reopening the finished pack. Test embedded mode independently from
downloaded/on-demand mode. The latter may never be the only way to obtain the
assets required for offline use.

## 10. Integrate and verify assets

Replace development mocks only through an explicit production configuration.
At startup, verify manifest compatibility and hashes before model load and
return a typed error for missing/corrupt assets. `engine.verify()` must be
extended to check real hashes, load real models, and perform the required
smoke render; its current mock-backed result is not sufficient release
evidence.

Keep the mock path available to unit tests, but make production-vs-development
status impossible to confuse in applications, logs, benchmarks, and reports.

## 11. Run the benchmark procedure

**Current command:**

```bash
swift run -c release choir-benchmark
```

Run from a Release build on each reference device, not a simulator. Record
exact hardware, OS, power source/level, Low Power Mode, thermal state, free
storage, background activity, package/model/asset versions, compute units,
voice, text corpus, warm-up, and iteration count.

Measure cold start, warm time-to-first-audio, batch RTF, sustained streaming
RTF, peak CHOIR-attributable memory, installed/lazy pack sizes, 60-minute
battery usage, thermal transitions, and one/two/four-job concurrency where
applicable. Report raw samples, median, p95, minimum, and maximum. Current
mock-backed numbers are baselines only and must be replaced after each model or
runtime change.

## 12. Run functional and quality acceptance

At minimum, archive:

- `swift test` and Release build output;
- front-end coverage and all normalization/golden cases;
- at least 200 seeded golden-audio results across every voice;
- malformed/fuzz input and crash-isolation runs;
- platform integration matrix from <doc:PlatformDifferences>;
- no-network audit and log-redaction audit;
- codec/container metadata and audiobook-integrity tests;
- accessibility, long-form, MOS, artifact, intelligibility, distinctness, and
  listener-fatigue reports.

An acceptance waiver names the requirement, owner, rationale, user impact,
expiry, and replacement gate. Never silently omit a failed or unmeasured gate.

## 13. Yearly Apple OS beta smoke procedure

Run this procedure for the first developer beta, an API-stable late beta, and
the release candidate of each retained OS:

1. update the dedicated compatibility branch and pin the tested Xcode beta;
2. compile every package target with complete Swift concurrency checking;
3. collect compiler and linker deprecation warnings and assign every warning;
4. run the full public-API compile client and unit suite;
5. initialize/verify real assets and render a seeded short/long request;
6. compare seeded output with the previous released OS under the parity rule;
7. run export, file access, cancellation, memory-pressure, and corruption
   recovery;
8. on iOS/iPadOS, run interruption, route, background, VoiceOver, battery, and
   thermal smoke tests;
9. on macOS, run sandbox and four-job/CLI smoke tests;
10. on visionOS, run the spatial scene when that module exists;
11. on watchOS, run the documented subset and phone-assisted path when it
    exists;
12. publish the matrix with pass/fail/unavailable, issue links, and retest
    dates.

No deprecated API warning may remain unowned at ship time. Remove or migrate a
deprecated dependency before the corresponding final OS release unless a
documented platform exception is approved.

## 14. Version, release, and rollback

Before tagging:

- decide the semantic package version;
- implement and set the separate audio-output engine version (currently
  missing), bumping it whenever identical requests can change audibly;
- verify stable voice IDs and append-only phoneme semantics;
- produce migration notes for cache/model/schema changes;
- regenerate DocC and inspect unresolved links/warnings;
- archive all reports under the candidate version;
- sign artifacts, verify them after download, and test the exact artifact in a
  clean consuming app;
- confirm App Store review in an embedded shipping app before claiming it.

Rollback means restoring the last known-good package, model, vocoder, lexicon,
and manifest as one compatible set. Never roll back code alone across an asset
schema boundary. Keep prior signed assets addressable until every supported app
version has migrated or expired.

## 15. Release record

The final record must let a future maintainer answer: what shipped, which
inputs produced it, how it was measured, which requirements passed, which were
waived, how to reproduce it, and how to roll it back. If any answer depends on
a private message or a machine that no longer exists, the release is not
reproducible.
