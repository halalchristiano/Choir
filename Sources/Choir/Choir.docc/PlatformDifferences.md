# Platform Differences

Understand the distinction between a declared SwiftPM target and a validated
product feature.

## Support matrix

| Platform | Declared minimum | Available package surface | Evidence still required |
|---|---:|---|---|
| iOS/iPadOS | 17 | Base public API and AVFoundation playback where available | Physical-device model, interruption, route, background, thermal, battery, VoiceOver, export |
| macOS | 14 | Base public API, AVFoundation playback, benchmark executable | Production-model performance, four-job concurrency, sandbox asset/file access, Intel policy |
| visionOS | 1 | Base public API | Spatial module, positioned playback, RealityKit binding, six-speaker scene |
| watchOS | 10 | Package target | Supported voice subset, asset budget, playback, memory pressure, phone-assisted workflow |
| tvOS | 17 | Package target | Product scope and end-to-end validation |

No trained production model ships, so no platform currently has validated
speech quality or seeded cross-device audio parity.

## Shared public surface

The base module exposes the same core types wherever SwiftPM can build it:

```swift
let engine = ChoirEngine()
try await engine.initialize()
let audio = try await engine.synthesize(text: "Hello.", voice: .isla)
```

The current default path is mock-backed everywhere. Platform-specific compile
availability must not be described as production synthesis support.

## Playback and audio-session ownership

On Apple platforms with AVFoundation, Tier 1 playback uses `AVAudioPlayer`.
CHOIR does not configure or own an application's `AVAudioSession`. The app
selects its category, mode, route, mixing/ducking policy, interruption policy,
and background entitlement.

On iOS-family platforms, configure the session before playback:

```swift
#if os(iOS)
import AVFoundation

let session = AVAudioSession.sharedInstance()
try session.setCategory(
    .playback,
    mode: .spokenAudio,
    options: [.duckOthers]
)
try session.setActive(true)
#endif
```

Test calls, Siri, alarms, Bluetooth, AirPods, CarPlay, route changes,
backgrounding, and VoiceOver on physical hardware. A consuming app—not the
package—decides whether an interruption pauses, ducks, resumes, or stops.

## Files and sandboxing

The implemented WAV encoder returns `Data`; the consuming app chooses and
authorizes the destination URL. On macOS, use security-scoped URLs when a
sandboxed user selects a location. Persistent synthesis-cache pinning now has
a package primitive; model-download, on-demand-resource, and resumable
audiobook-export storage flows are not implemented yet.

## Streaming

`streamSynthesis` prepares request-wide linguistic/prosody state, then renders
and emits natural phrase units sequentially. That removes full-request audio
buffering and produces the first phrase before later inference, but the
request-wide front end remains proportional to text length. Do not treat this
alone as evidence for watchOS viability or conversational latency.

## Hardware policy

The intended production baseline is A14 and later and all M-series Apple
silicon. The package manifest does not enforce a processor generation. Intel
Mac behavior has not been formally supported or excluded; make no Intel
compatibility promise until the release decision is encoded and tested.

## Release evidence per retained platform

Archive the hardware and OS build, package/model/asset versions, build mode,
functional suite, seeded parity result, TTFA/RTF, peak memory, asset size,
energy and thermal runs, audio-session matrix, accessibility result, and every
known limitation. Follow <doc:MaintenanceManual> for the yearly-beta smoke
procedure.
