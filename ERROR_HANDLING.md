# Error handling

CHOIR exposes `ChoirError`, a `Sendable`, `Equatable`, `LocalizedError` enum.
Every case has a stable `code`, an `errorDescription`, a
`recoverySuggestion`, and an `isRetryable` classification.

## Cases

| Case | Code | Retryable | Meaning |
|---|---|---:|---|
| `modelLoadFailed(reason:)` | CHOIR-1001 | No | Required model assets could not be loaded |
| `textProcessingFailed(reason:)` | CHOIR-1002 | No | Normalization, markup, or phonemization failed |
| `synthesisError(reason:)` | CHOIR-1003 | Yes | Model or waveform generation failed |
| `audioEncodingFailed(reason:)` | CHOIR-1004 | No | Export or codec preparation failed |
| `notInitialized` | CHOIR-1005 | No | `initialize()` has not completed |
| `cancelled` | CHOIR-1006 | No | The caller cancelled the task |
| `invalidParameter(parameter:reason:)` | CHOIR-1007 | No | A value is outside its accepted contract |
| `outOfMemory` | CHOIR-1008 | Yes | The operation could not obtain enough memory |
| `timeout` | CHOIR-1009 | Yes | The operation exceeded its time budget |
| `engineBusy` | CHOIR-1010 | Yes | The same engine is initializing or synthesizing |
| `unknown(String)` | CHOIR-1999 | Yes | An unclassified failure occurred |

Codes already assigned to older cases are never renumbered when a new case is
added.

## Basic handling

```swift
do {
    let audio = try await engine.synthesize(
        text: userText,
        voice: .isla
    )
    consume(audio)
} catch let error as ChoirError {
    logger.error("\(error.code): \(error.errorDescription ?? "")")

    if error.isRetryable {
        scheduleRetry()
    } else {
        show(error.recoverySuggestion ?? "The request could not be completed.")
    }
}
```

Do not retry `.cancelled`. Cancellation is an expected control-flow outcome,
not a transient synthesis failure.

## Invalid input

Empty text, text beyond the documented character ceiling, zero or negative
streaming chunk sizes, unsupported PCM formats, unknown phonemes, mismatched
acoustic tensors, non-finite model values, and invalid codec bitrates report
`invalidParameter` before unsafe work begins.

```swift
do {
    try StreamingOptions(chunkSize: 0).validate()
} catch ChoirError.invalidParameter(let parameter, let reason) {
    print("\(parameter): \(reason)")
}
```

## Engine lifecycle

```swift
let engine = ChoirEngine()

do {
    try await engine.initialize()
    _ = try await engine.synthesize(text: "Hello.", voice: .garrick)
} catch ChoirError.notInitialized {
    // initialize() was not called, or clearCache() released the pipeline.
} catch ChoirError.engineBusy {
    // Wait, queue the request, or use a separate engine instance.
}
```

`engineBusy` is intentionally distinct from `notInitialized`; callers should
not respond to contention by repeatedly loading the engine.

## Export errors

```swift
do {
    let output = try await engine.exportAudio(audio, format: .wav)
    if case .wav(let data) = output {
        try data.write(to: destination, options: .atomic)
    }
} catch ChoirError.audioEncodingFailed(let reason) {
    print(reason)
}
```

WAV is implemented for valid 16-bit PCM. MP3, AAC, and FLAC currently throw a
typed error instead of producing an empty file.

## Cancellation

```swift
let task = Task {
    try await engine.streamSynthesis(text: text, voice: .orion) { chunk in
        enqueue(chunk)
    }
}

task.cancel()
```

The pipeline checks cancellation between major stages and between delivered
chunks. True model-internal cancellation still depends on production model and
vocoder implementations adding checks inside their own long-running work.

## Retry only retryable errors

```swift
func synthesizeWithOneRetry(
    engine: ChoirEngine,
    text: String,
    voice: Voice
) async throws -> AudioBuffer {
    do {
        return try await engine.synthesize(text: text, voice: voice)
    } catch let error as ChoirError where error.isRetryable {
        try await Task.sleep(for: .milliseconds(250))
        return try await engine.synthesize(text: text, voice: voice)
    }
}
```

Avoid logging user text at normal levels. Log the stable code, operation,
engine/model version, and non-sensitive diagnostics instead.
