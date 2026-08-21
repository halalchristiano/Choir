# Platform integration status

CHOIR declares these Swift package targets:

| Platform | Minimum | Current evidence |
|---|---:|---|
| iOS / iPadOS | 17 | Package and CI compile target; physical-device synthesis unverified |
| macOS | 14 | Package and CI compile target; sandbox/model performance unverified |
| visionOS | 1 | Package compile target; spatial module not implemented |
| watchOS | 10 | Package compile target; memory, asset, speaker, and subset requirements unverified |
| tvOS | 17 | Package compile target; product behavior unverified |

Do not convert a declared deployment target into a claim that every feature has
been tested on that platform.

## Shared integration

```swift
import Choir

let engine = ChoirEngine()
try await engine.initialize()

let audio = try await engine.synthesize(
    text: "Platform integration test.",
    voice: .isla
)
```

The default pipeline is mock-backed on every platform. A consuming app can
inject a configured `SynthesisPipeline` with its own acoustic model and vocoder.

## Apple audio-session ownership

CHOIR does not own the consuming app's `AVAudioSession`. On iOS-family
platforms, the app should select a category, mode, routing policy, ducking
behavior, and interruption policy appropriate to its product.

```swift
#if canImport(AVFoundation) && os(iOS)
import AVFoundation

let session = AVAudioSession.sharedInstance()
try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
try session.setActive(true)
#endif
```

Background modes and playback permissions belong to the app target, not the
Swift package.

## Chunk delivery

```swift
try await engine.streamSynthesis(
    text: text,
    voice: .orion,
    options: StreamingOptions(chunkSize: 2_400)
) { chunk in
    enqueue(chunk.samples)
}
```

This currently renders the whole utterance before callbacks begin. It is not a
watchOS memory optimization and is not evidence of real-time performance.

## iOS and iPadOS work still required

- Test calls, Siri, alarms, route changes, headphones, AirPods, Bluetooth,
  CarPlay, backgrounding, and audio interruptions.
- Establish memory and thermal behavior on the reference devices.
- Implement and verify background rendering within system limits.
- Verify VoiceOver coexistence and configurable ducking.

## macOS work still required

- Verify App Sandbox file and model-asset access.
- Measure one-job and four-job rendering on the documented M-series devices.
- Define and enforce the Intel Mac policy.
- Verify output parity across supported compute units.

## visionOS work still required

The base package currently returns ordinary PCM. Positioned speakers,
head-tracked motion, RealityKit binding, six-speaker rendering, and an optional
`CHOIRSpatial` module remain unimplemented.

## watchOS work still required

The package declares watchOS 10, but the product subset is not complete. Before
claiming watch support, select and validate the supported voices, keep assets
within the SRS budget, return typed capability errors for unsupported features,
test memory pressure and speaker output, and decide whether phone-assisted
rendering remains in scope.

## tvOS work still required

tvOS is a declared compile target, not a verified product target. Either run
the complete platform integration suite or narrow the public claim.

## Release evidence

For every retained platform, archive:

1. exact OS and hardware versions;
2. package, engine, model, and asset versions;
3. build and test results;
4. latency, real-time factor, memory, battery, and thermal measurements;
5. interruption, routing, background, cancellation, and accessibility results;
6. any feature limitations or automatic quality downgrade.

See [STREAMING.md](./STREAMING.md) for the current chunk-delivery contract and
[PROJECT_STATUS.md](./PROJECT_STATUS.md) for overall product truth.
