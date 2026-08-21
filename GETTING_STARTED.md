# Getting started with CHOIR

> CHOIR v0.16 is pre-alpha infrastructure. The default engine produces a mock
> waveform, not intelligible speech. Use it to develop and test integrations,
> or inject your own `SynthesisPipeline` containing real model implementations.

## Installation

```swift
.package(url: "https://github.com/halalchristiano/Choir.git", from: "0.16.0")
```

The declared minimums are iOS 17, macOS 14, visionOS 1, watchOS 10, and tvOS
17. Physical-device conformance is not yet established.

## Run the development pipeline

```swift
import Choir

let engine = ChoirEngine()
try await engine.initialize()

let audio = try await engine.synthesize(
    text: "Hello, CHOIR.",
    voice: .isla,
    parameters: SynthesisParameters(rate: 0.95)
)

print(audio.samples.count)
print(audio.format.sampleRate)
```

`AudioBuffer.samples` contains interleaved 16-bit PCM. The default format is
48 kHz mono. The mock-backed buffer is useful for integration plumbing but is
not evidence of speech quality.

## Choose a voice profile

`Voice` has 32 stable cases. Examples include `.finch`, `.wren`, `.orion`,
`.isla`, `.garrick`, `.marion`, `.alaric`, and `.maeve`.

```swift
let narrators = Voice.voices(for: .narration)
let villains = Voice.villains
let profile = Voice.garrick.profile

print(profile.identifier)
print(profile.medianF0)
print(Voice.garrick.conditioningID)
```

Profiles and conditioning IDs are real metadata. Distinct audible timbres are
not bundled yet.

## Stream natural phrase units

```swift
try await engine.streamSynthesis(
    text: "Render and deliver this passage phrase by phrase.",
    voice: .orion,
    options: StreamingOptions(chunkSize: 2_400)
) { chunk in
    audioPlayer.enqueue(chunk.samples)
}
```

The front end prepares request-wide text and prosody, then acoustic/vocoder
inference runs one natural phrase at a time. Each phrase is emitted before the
next one runs, with synchronized timing and cancellation checks. See
[STREAMING.md](./STREAMING.md) for the precise boundary and remaining gates.

## Export WAV

```swift
let output = try await engine.exportAudio(audio, format: .wav)

if case .wav(let data) = output {
    try data.write(to: destinationURL, options: .atomic)
}
```

WAV export validates the PCM format and writes a RIFF header. MP3, AAC, and
FLAC currently throw `ChoirError.audioEncodingFailed`; they never return a
misleading empty file.

## Inject a configured pipeline

```swift
let pipeline = SynthesisPipeline(
    acousticModel: myAcousticModel,
    vocoder: myVocoder
)

let engine = ChoirEngine(pipeline: pipeline)
try await engine.initialize()
```

Both injected values must conform to `AcousticModelProtocol` and
`VocoderProtocol`. Acoustic inputs are validated before inference: every
phoneme-aligned tensor must have the same nonzero length and contain valid,
finite values.

## Error handling

```swift
do {
    _ = try await engine.synthesize(text: "", voice: .isla)
} catch let error as ChoirError {
    print(error.code)
    print(error.errorDescription ?? "")
    print(error.recoverySuggestion ?? "")
}
```

`ChoirError.engineBusy` is distinct from `.notInitialized`, invalid chunk
sizes fail before rendering, and unavailable codecs fail explicitly.

## Releasing resources

```swift
await engine.clearCache()
try await engine.initialize() // required before the next synthesis
```

`clearCache()` releases the initialized pipeline when no request is active.

## Next references

- [README.md](./README.md) — current scope and API overview
- [STREAMING.md](./STREAMING.md) — chunk delivery behavior
- [ERROR_HANDLING.md](./ERROR_HANDLING.md) — typed error contract
- [Production backlog PR](https://github.com/halalchristiano/Choir/pull/1) — work remaining before production
- [Sources/Choir/Demo/ChoirDemo.swift](./Sources/Choir/Demo/ChoirDemo.swift) — source examples
