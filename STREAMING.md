# Streaming synthesis

> **Development status:** CHOIR v0.15 renders the complete utterance before it
> emits chunks. The API provides chunked delivery, timestamps, cancellation
> checks, and bounded callback buffers, but it is **not yet incremental neural
> synthesis** and does not reduce time to first audio or peak render memory.

This document describes the behavior that exists today. True progressive
synthesis remains tracked in `REMAINING_WORK.md` and must not be claimed until
audio is produced while later text is still being processed.

## Current API

```swift
let engine = ChoirEngine()
try await engine.initialize()

try await engine.streamSynthesis(
    text: "This result is delivered in chunks after rendering completes.",
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
and a timestamp measured from the start of the rendered buffer. At the default
48 kHz mono format, 2,400 samples represent 50 ms.

## Validation and failure behavior

- `chunkSize` must be greater than zero. Zero and negative values throw
  `ChoirError.invalidParameter` before synthesis starts.
- Cancellation is checked before rendering stages and between emitted chunks.
- An error thrown by `onChunk` stops delivery and propagates to the caller.
- A second request on the same engine while one is active throws
  `ChoirError.engineBusy`; use separate engine instances if parallel work is
  required by the current development build.
- The current default engine is mock-backed and does not produce speech.

## Choosing a chunk size

Chunk size controls callback frequency after rendering, not synthesis latency.

| Samples at 48 kHz | Audio duration | Current tradeoff |
|---:|---:|---|
| 1,200 | 25 ms | More callback overhead |
| 2,400 | 50 ms | Default |
| 4,800 | 100 ms | Less callback overhead |

Do not publish fixed CPU, memory, or first-audio numbers from this mock-backed
path. Measure them again after the production acoustic model and vocoder are
integrated.

## What “true streaming” must add

The streaming implementation is complete only when it:

1. emits the first audible chunk before the full utterance is rendered;
2. processes later linguistic/acoustic units while earlier audio plays;
3. keeps peak memory bounded independently of utterance length;
4. produces click-free boundaries and batch-equivalent audio;
5. delivers word, phoneme, sentence, and mark timing incrementally;
6. stops model and vocoder compute promptly on cancellation;
7. survives sustained real-time playback on the documented reference devices;
8. reports any automatic quality downgrade.

Until those gates pass, describe this feature as **chunked delivery**, not
real-time or progressive synthesis.
