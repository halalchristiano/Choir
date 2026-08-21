# Streaming synthesis

> **Development status:** CHOIR v0.16 prepares request-wide linguistic and
> prosody state, then renders and emits one natural phrase before starting
> acoustic/vocoder inference for the next. The default path remains mock-backed;
> production-model real-time behavior is not established.

This document describes the implemented progressive boundary and the evidence
still required before calling it real-time production streaming.

## Current API

```swift
let engine = ChoirEngine()
try await engine.initialize()

try await engine.streamSynthesis(
    text: "This request is rendered and delivered phrase by phrase.",
    voice: .isla,
    options: StreamingOptions(chunkSize: 2_400)
) { chunk in
    audioPlayer.enqueue(chunk.samples)
    if chunk.isFinal {
        print("Finished")
    }
}
```

Each `AudioChunk` contains interleaved 16-bit PCM samples, an `isFinal` flag,
and a timestamp measured from the start of the request. At the default
48 kHz mono format, 2,400 samples represent 50 ms.

## Validation and failure behavior

- `chunkSize` must be greater than zero. Zero and negative values throw
  `ChoirError.invalidParameter` before synthesis starts.
- Cancellation is checked before rendering stages and between emitted chunks.
- An error thrown by `onChunk` stops delivery and propagates to the caller.
- One engine admits at least two jobs with FIFO permits; each job remains
  independently cancellable.
- `streamChunks` uses an acknowledged, bounded eight-chunk handoff. A slow
  consumer suspends synthesis rather than dropping PCM or growing memory, and
  ending iteration cancels the producer. The source-compatible `stream`
  adapter preserves its historical lossless, unbounded buffering behavior;
  new long-running consumers should prefer `streamChunks` for bounded memory.
- The current default engine is mock-backed and does not produce speech.

## Choosing a chunk size

Chunk size controls callback frequency within each rendered phrase. Phrase
length and production model speed still dominate first-audio latency.

| Samples at 48 kHz | Audio duration | Current tradeoff |
|---:|---:|---|
| 1,200 | 25 ms | More callback overhead |
| 2,400 | 50 ms | Default |
| 4,800 | 100 ms | Less callback overhead |

Do not publish fixed CPU, memory, or first-audio numbers from this mock-backed
path. Measure them again after the production acoustic model and vocoder are
integrated.

## What production streaming must still prove

Release acceptance still requires it to:

1. meet TTFA and real-time-factor limits with the production models;
2. pass clickless/gapless joins and batch-equivalence audio comparisons;
3. keep peak memory inside each platform budget on long documents;
4. validate word/phoneme/mark timing against aligned production output;
5. stop model and vocoder compute promptly on cancellation;
6. survive sustained playback on every reference device;
7. report any automatic quality downgrade.

Until those gates pass, describe this as **phrase-progressive infrastructure**,
not verified real-time production synthesis.
