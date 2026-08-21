# Experimental sample-based synthesis

CHOIR contains `VoiceSampleLibrary`, `PhonemeSample`,
`SampleBasedSynthesizer`, and `SimpleSynthesizer` as an experimental
concatenative path. It does not
ship recorded voice libraries, and it must not be described as the production
implementation of CHOIR's 32 synthetic profiles.

## What exists

- An actor-backed in-memory library for caller-supplied phoneme samples.
- Multiple samples per phoneme and deterministic selection when a seed is
  supplied.
- A simple synthesizer that requests samples from the library and returns PCM.
- Library statistics and typed failures for missing/unusable samples.

## What does not exist

- No bundled human recordings or license/consent manifests.
- No claim that a few dozen isolated phones reproduce a speaker naturally.
- No diphone/unit-selection inventory, coarticulation model, full prosody
  transfer, or production concatenation-quality evidence.
- No validated latency, memory, CPU, intelligibility, naturalness, or
  long-form stability figures.
- No mapping from a sample library to the 32 ``Voice`` cases.
- No permission to clone or impersonate an identifiable person.

## Exercise the API with owned test material

```swift
import Choir

let library = VoiceSampleLibrary(voiceName: "DevelopmentFixture")

let accepted = await library.addSample(
    PhonemeSample(
        phoneme: "h",
        audioData: ownedTestPCM,
        sampleRate: 48_000,
        averagePitch: 180
    )
)

guard accepted else {
    throw ChoirError.invalidParameter(
        parameter: "sample",
        reason: "The sample was empty or unusable"
    )
}

let synthesizer = SimpleSynthesizer(library: library)
let audio = try await synthesizer.synthesize(text: "Hello")
```

Use recordings only when you have documented consent and distribution rights.
Do not use this path to imitate a person or suggest that its output is a CHOIR
profile. See the in-package DocC article **Responsible Use**.

## Recording-fixture guidance

If a developer creates private test fixtures:

1. capture written consent and an explicit license before recording;
2. use a quiet, consistent environment and retain the raw source;
3. record contextual units, not just one isolated example of each phoneme;
4. preserve sample rate, channel, microphone, session, transcript, and take
   metadata;
5. segment nondestructively and keep checksums for source and derived clips;
6. separate fixtures from production assets and exclude restricted material
   from public repositories;
7. evaluate artifacts and intelligibility before using the output for any
   product decision.

The stable public phoneme inventory is documented in
`Sources/Choir/Choir.docc/PhonemeInventoryReference.md`. It contains 40
entries (16 vowels/diphthongs and 24 consonants), not the smaller inventory
previous versions of this guide listed.

## Production direction

The product requirements call for a licensed, reproducible, trained
multi-voice acoustic model and a production 48 kHz vocoder. The sample-based
types may remain useful for experiments and fixtures, but they do not replace
those model, quality, platform, and release gates.
