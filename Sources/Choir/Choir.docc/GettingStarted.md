# Getting Started

Add CHOIR to an app and exercise its public API in under ten minutes.

## Add the package

In Xcode, choose **File > Add Package Dependencies** and enter the repository
URL. For a `Package.swift` dependency, use:

```swift
dependencies: [
    .package(
        url: "https://github.com/halalchristiano/Choir.git",
        from: "0.16.0"
    )
]
```

Add the `Choir` product to the target that imports it. The package declares
iOS/iPadOS 17, macOS 14, visionOS 1, watchOS 10, and tvOS 17. A declaration is
not physical-device validation; see <doc:PlatformDifferences>.

## Exercise the one-line API

```swift
import Choir

let audio = try await Choir.synthesize(
    "Hello from CHOIR.",
    voice: .isla
)

print(audio.frameCount)
print(audio.duration)
```

`Choir.speak` also plays the returned buffer on platforms where AVFoundation
playback is available:

```swift
try await Choir.speak("A short playback check.", voice: .maeve)
```

> Note: With the package's default dependencies, these calls produce a test
> waveform. They verify integration, lifecycle, and audio plumbing only.

## Reuse an engine

Create one engine for repeated work, initialize it once, and keep it alive:

```swift
let engine = ChoirEngine()
try await engine.initialize()

let parameters = SynthesisParameters(
    pitchShift: -1,
    rate: 0.92,
    emotionalIntensity: 0.4,
    seed: 42
)

let result = try await engine.synthesizeWithMetadata(
    text: "A reusable engine avoids repeated initialization.",
    voice: .garrick,
    parameters: parameters
)

print(result.metadata.totalDurationMs)
```

Call `clearCache()` only when the engine is idle. It releases the configured
pipeline; call `initialize()` again before the next request.

## Use explicit input modes

CHOIR never guesses whether angle brackets are markup:

```swift
let result = try await engine.synthesize(
    input: .markup(
        #"<speak>Hello <break time="250ms"/> again.</speak>"#
    ),
    voice: .isla
)
```

Use `.plainText` when markup characters must be spoken literally. The
`.phonemes` front-end path validates public IPA symbols, but end-to-end
pre-phonemized synthesis still requires an injected production acoustic model.
See <doc:SSMLCReference> and <doc:PhonemeInventoryReference>.

## Export a development render

```swift
let rendered = try await engine.synthesize(
    text: "Write this buffer as WAV.",
    voice: .orion
)

if case .wav(let data) = try await engine.exportAudio(rendered, format: .wav) {
    try data.write(to: destinationURL, options: .atomic)
}
```

WAV is the currently implemented export path. AAC, MP3, FLAC, CAF, ALAC, and
chaptered audiobook export are not production-ready.

## Handle typed failures

```swift
do {
    _ = try await engine.synthesize(text: "", voice: .isla)
} catch let error as ChoirError {
    logger.error("\(error.code): \(error.errorDescription ?? "")")
}
```

Never include the user's text in normal logs. See <doc:ResponsibleUse>.

## Next steps

- Choose the appropriate level of control in <doc:APITiers>.
- Select metadata profiles in <doc:VoiceBook>.
- Follow a product workflow in <doc:IntegrationRecipes>.
- Read <doc:DocumentationStatus> before describing a feature as complete.
