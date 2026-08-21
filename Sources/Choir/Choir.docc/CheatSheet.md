# CHOIR Cheat Sheet

Print this page for the common Tier 1, Tier 2, and voice-ID references.

## Tier 1

```swift
import Choir

let audio = try await Choir.synthesize("Text", voice: .isla)
try await Choir.speak("Text", voice: .maeve)
```

The default 0.16 pipeline produces a test waveform, not speech.

## Tier 2

```swift
let engine = ChoirEngine()
try await engine.initialize()

let p = SynthesisParameters(
    pitchShift: 0,             // SRS envelope: -6...6 st
    rate: 1,                   // SRS envelope: 0.6...2.0
    emotionalIntensity: 0.5,  // 0...1
    breathiness: 0,           // 0...1
    ageShift: 0,              // -1...1
    genderShift: 0,           // -1...1
    seed: 42
)

let audio = try await engine.synthesize(
    text: "Text", voice: .isla, parameters: p
)
let result = try await engine.synthesizeWithMetadata(
    text: "Text", voice: .isla, parameters: p
)
```

These are the SRS and constructor envelopes. They are not yet proven
artifact-free for trained voices. Inspect `p.wasClamped` and `p.clampings`
after construction or call `validated()` after direct mutation.

## Output and lifecycle

```swift
if case .wav(let data) = try await engine.exportAudio(audio, format: .wav) {
    try data.write(to: url, options: .atomic)
}

let estimate = engine.estimateDuration(text: "Text", voice: .isla)
let health = await engine.verify()
await engine.clearCache()
```

Only WAV export is complete. `clearCache()` requires a later `initialize()`.

## Voice IDs

| Age | Presentation | Profiles and stable IDs |
|---|---|---|
| Child | Male | FINCH `choir.child.male.finch`; SCOUT `choir.child.male.scout`; ALDER `choir.child.male.alder`; WICK `choir.child.male.villain.wick` |
| Child | Female | WREN `choir.child.female.wren`; JUNIPER `choir.child.female.juniper`; CLOVER `choir.child.female.clover`; BRIAR `choir.child.female.villain.briar` |
| Young adult | Male | ORION `choir.ya.male.orion`; FLINT `choir.ya.male.flint`; REED `choir.ya.male.reed`; CORVIN `choir.ya.male.villain.corvin` |
| Young adult | Female | LYRA `choir.ya.female.lyra`; ISLA `choir.ya.female.isla`; NOVA `choir.ya.female.nova`; SABLE `choir.ya.female.villain.sable` |
| Middle-aged | Male | GARRICK `choir.mid.male.garrick`; HALE `choir.mid.male.hale`; BRAM `choir.mid.male.bram`; MALVERN `choir.mid.male.villain.malvern` |
| Middle-aged | Female | MARION `choir.mid.female.marion`; TAMSIN `choir.mid.female.tamsin`; GREER `choir.mid.female.greer`; RAVENNA `choir.mid.female.villain.ravenna` |
| Elderly | Male | ALARIC `choir.eld.male.alaric`; WILFRED `choir.eld.male.wilfred`; CORMAC `choir.eld.male.cormac`; GRIMSHAW `choir.eld.male.villain.grimshaw` |
| Elderly | Female | MAEVE `choir.eld.female.maeve`; ODETTE `choir.eld.female.odette`; HATTIE `choir.eld.female.hattie`; HESPERA `choir.eld.female.villain.hespera` |

Resolve data-driven values with `Voice(id:)`; persist the full stable ID.

## Input modes

```swift
.plainText("5 < 7")
.markup(#"<speak>Hello <break time="200ms"/></speak>"#)
.phonemes([Phoneme("h"), Phoneme("ɛ", stress: 1), Phoneme("l"), Phoneme("oʊ")])
```

## Production stop signs

Do not claim intelligible voices, verified real-time/production streaming, complete codecs,
audiobook export, spatial playback, physical-device conformance, or quality
scores until the corresponding implementation and archived evidence exist.
