# Performance measurement guide

Current measurements exercise development mocks and must not be used to
predict production neural-model performance. Re-run every gate after the real
acoustic model, vocoder, voice assets, and progressive streaming path exist.

## Metrics

| Metric | Definition | Why it matters |
|---|---|---|
| Cold start | Process launch to first audible sample | First-use experience |
| Warm TTFA | Warm request to first audible sample | Interactive latency |
| Batch RTF | Render time divided by audio duration | Offline throughput |
| Streaming RTF | Sustained compute time divided by emitted audio duration | Underrun risk |
| Peak memory | CHOIR-attributable resident peak | Device viability |
| Energy | Battery consumed over the standard 60-minute workload | Mobile viability |
| Thermal state | Time and quality at each thermal transition | Sustained viability |
| Asset size | Installed total and lazy-loaded family size | Distribution limits |

## Run the harness

```bash
swift run -c release choir-benchmark
```

Record the exact commit, Swift/Xcode version, build configuration, device,
OS, power state, thermal state, model versions, compute-unit selection, and
number of repetitions. A number without this context is not reproducible.

## Real-time factor

For render time $t_r$ and produced audio duration $t_a$:

$$RTF = \frac{t_r}{t_a}$$

An RTF below 1 means synthesis is faster than playback for that sample. It does
not by itself prove low time-to-first-audio, stable long-run streaming, low
memory, or acceptable quality.

## Chunk delivery caveat

`streamSynthesis` currently performs a full batch render and then divides the
buffer. Its first callback measures batch completion, not progressive TTFA,
and its peak memory includes the complete output buffer.

Do not claim streaming memory savings or interactive latency from this path.

## Reference procedure

1. Reboot or otherwise document device preconditioning.
2. Build Release with the pinned toolchain.
3. Record a true cold-start sample in a fresh process.
4. Warm the selected voice and model once.
5. Run the standard short, medium, and long corpora.
6. Repeat enough times to report median, p95, minimum, and maximum.
7. Measure one job, two fair concurrent jobs, and the Mac four-job target.
8. Run the 60-minute playback workload for battery and thermal behavior.
9. Trigger memory pressure and verify safe unloading/reloading.
10. Archive raw observations and the generated report with the release.

## Optimization order

Optimize only after production audio passes correctness and quality gates:

1. eliminate accidental copies and unbounded buffering;
2. stream linguistic and acoustic units incrementally;
3. profile model conversion and compute-unit placement;
4. quantize only with before/after quality evidence;
5. load voice families lazily and unload under pressure;
6. add a tested efficient path for thermal fallback;
7. preserve batch/streaming equivalence and seeded determinism.

## Release blocking conditions

- Missing production-model measurements.
- Measurements taken only in Debug builds or simulators.
- No physical-device memory, battery, or thermal result.
- RTF/TTFA claims based on mocks.
- A quality downgrade without a diagnostic.
- Streaming that begins only after full rendering while described as real-time.
- A benchmark report that omits hardware, OS, model, or build provenance.

See [BENCHMARK.md](./BENCHMARK.md) for the latest recorded report and
[PROJECT_STATUS.md](./PROJECT_STATUS.md) for current implementation truth.
