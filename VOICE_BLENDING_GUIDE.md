# Voice parameter blending

> `VoiceBlending` interpolates `SynthesisParameters`. It does not blend model
> embeddings, vocal timbre, or two audio waveforms. With the current
> mock-backed pipeline it must not be presented as voice morphing.

## Blend two parameter profiles

```swift
let blending = VoiceBlending()

let calmOrion = VoiceBlending.VoiceProfile(
    voice: .orion,
    parameters: SynthesisParameters(
        pitchShift: -1,
        rate: 0.85,
        emotionalIntensity: 0.2,
        breathiness: 0.1
    )
)

let brightLyra = VoiceBlending.VoiceProfile(
    voice: .lyra,
    parameters: SynthesisParameters(
        pitchShift: 3,
        rate: 1.15,
        emotionalIntensity: 0.9,
        breathiness: 0.25
    )
)

let midpoint = blending.blend(calmOrion, with: brightLyra, mix: 0.5)
```

`mix` is clamped to `0...1`. A value of zero returns the first parameter set;
one returns the second; intermediate values linearly interpolate pitch, rate,
emotional intensity, breathiness, age shift, and gender shift.

The returned value is only `SynthesisParameters`. The caller still selects the
single `Voice` passed to `ChoirEngine.synthesize`.

```swift
let audio = try await engine.synthesize(
    text: "A parameter blend, using Orion's voice selection.",
    voice: .orion,
    parameters: midpoint
)
```

## Transition helpers

```swift
let genderSteps = blending.genderTransition(
    from: .orion,
    to: .lyra,
    steps: 5
)

let ageSteps = blending.ageTransition(
    from: .finch,
    to: .alaric,
    steps: 5
)
```

These functions return arrays of parameter values. They do not render audio,
crossfade clips, preserve identity, or guarantee a natural perceptual path.

## Current limitations

- `VoiceProfile.voice` is metadata in the blending calculation; the current
  `blend` method interpolates only its accompanying parameters.
- Linear interpolation is not perceptually uniform.
- The production model does not yet establish safe per-voice envelopes.
- Age and gender controls are not verified to preserve identity.
- Streaming cannot apply parameter changes mid-utterance; the current chunk
  callbacks begin after full rendering.
- No ABX, naturalness, artifact, or intelligibility result exists for blends.

## Requirements for real voice interpolation

Before CHOIR advertises voice morphing, it needs:

1. trained and disentangled voice embeddings;
2. a documented interpolation space and safe envelope;
3. formant-aware, identity-preserving conditioning;
4. continuous parameter changes at defined synthesis boundaries;
5. artifact and intelligibility tests across the interpolation grid;
6. blinded identity and naturalness evaluation;
7. safeguards against reconstructing or cloning an identifiable real person.

Use `VoiceBlending` today as a parameter-animation utility, not a production
voice-design system.
