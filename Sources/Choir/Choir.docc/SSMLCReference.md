# SSML-C Reference

Use CHOIR's deliberately small XML-like markup dialect with an explicit
``SynthesisInput/markup(_:)`` request.

## Supported elements

| Element | Attributes and accepted values | Behavior |
|---|---|---|
| `<speak>` | None | Optional document wrapper |
| `<break/>` | `time`: nonnegative milliseconds, `Nms`, or `Ns`; `strength`: `none`, `weak`, `medium`, `strong`, `paragraph` | Emits a pause event; explicit time wins |
| `<emphasis>` | `level`: `none`, `reduced`, `moderate`, `strong`; default `moderate` | Sets emphasis on enclosed speech |
| `<prosody>` | `pitch`: signed semitones with optional `st`; `rate`: positive percent, bare multiplier ≤3, or bare percent >3; `volume`: signed dB with optional `dB` | Adds pitch/volume and compounds rate across nesting |
| `<phoneme>` | `ph`: whitespace-separated pronunciation text | Overrides pronunciation of enclosed text |
| `<say-as>` | `interpret-as`: `characters`, `number`, `ordinal`, `date`, `scripture` | Selects normalization intent for enclosed text |
| `<voice>` | `id`: stable voice ID, display name, or case name | Selects a profile for enclosed speech |
| `<mark/>` | `name`: nonempty string | Emits a named timing event |

`<break>` and `<mark>` are void elements and should be self-closing. Container
elements may nest. Attribute names and tag names are case-insensitive;
enumerated attribute values are normalized to lowercase.

## Complete example

```swift
let markup = #"""
<speak>
  <mark name="opening"/>
  <voice id="choir.eld.female.maeve">
    <prosody rate="92%" pitch="-1st">
      <emphasis level="moderate">Blessed</emphasis> is the one
      <break time="300ms"/>
      who walks in wisdom.
    </prosody>
  </voice>
  <voice id="GARRICK">
    <say-as interpret-as="scripture">John 3:16</say-as>
    <phoneme ph="m ɛ l k ɪ z ə d ɛ k">Melchizedek</phoneme>
  </voice>
</speak>
"""#

let result = try await engine.synthesize(
    input: .markup(markup),
    voice: .isla,
    parameters: SynthesisParameters(seed: 9)
)

for warning in result.metadata.warnings {
    print(warning.message)
}
```

The parser validates this syntax and produces events. Production acoustic
realization of every style and clickless multi-voice joins is not yet proven.

## Break resolution

| Strength | Nominal duration |
|---|---:|
| `none` | 0 ms |
| `weak` | 100 ms |
| `medium` | 300 ms |
| `strong` | 600 ms |
| `paragraph` | 1,000 ms |

With neither valid `time` nor valid `strength`, a break resolves to 300 ms.
Negative or non-finite durations are rejected by the scalar parser and become
a warning plus the strength/default fallback.

## Nesting rules

Nested pitch and volume offsets add. Nested rate values multiply. Inner
emphasis, voice, phoneme, and say-as values replace the enclosing value for
their run. Closing a non-topmost open tag implicitly closes inner tags and
records a diagnostic.

```xml
<prosody rate="80%">
  outer
  <prosody rate="125%" pitch="+2st">inner at 100% effective rate</prosody>
</prosody>
```

## Entity handling

Spoken text decodes `&lt;`, `&gt;`, `&amp;`, `&quot;`, `&apos;`, `&#39;`, `&nbsp;`, and
valid decimal/hexadecimal numeric character references. Decode happens after
tag scanning, so `&lt;voice&gt;` is spoken text rather than manufactured markup.

Use `.plainText` instead of `.markup` when all angle brackets must be literal.

## Graceful and strict parsing

The synthesis front end uses non-strict parsing. Unknown or malformed markup
records warnings; text outside stripped tags remains speakable. Use the parser
directly for strict validation before accepting authored content:

```swift
let parser = SSMLCParser(strict: true)
_ = try parser.parse(authoredMarkup)
```

Strict mode throws ``ChoirError/textProcessingFailed(reason:)`` on the first
reported issue.

## Edge-case corpus

These inputs define the expected parser contract and should remain in tests
when the dialect evolves:

| Case | Input | Expected parser outcome |
|---|---|---|
| Plain wrapper | `<speak>Hello.</speak>` | One speech run, no diagnostic |
| Explicit pause | `A<break time="1.5s"/>B` | Speech, 1,500 ms pause, speech |
| Time precedence | `<break time="20ms" strength="strong"/>` | 20 ms pause |
| Default emphasis | `<emphasis>word</emphasis>` | `moderate` emphasis |
| Compounded rate | `<prosody rate="80%"><prosody rate="1.25">x</prosody></prosody>` | Inner effective rate 100% |
| Mark | `<mark name="v1"/>Text` | Mark named `v1`, then speech |
| Entity safety | `5 &lt; 7 &amp;&amp; 8 &gt; 3` | Literal comparison text |
| Unknown tag | `<unknown>text</unknown>` | Content spoken, diagnostics recorded |
| Unclosed tag | `<prosody pitch="2st">text` | Style to end, warning recorded |
| Mismatch | `<emphasis><prosody>text</emphasis>` | Implicit close, warning recorded |
| Invalid break | `<break time="-2s"/>` | Medium fallback plus warning |
| Empty mark | `<mark name=""/>` | No mark, warning recorded |
| Void not closed | `<break>text` | Pause and warning; text remains |
| Unsupported style | `<style name="joyful">text</style>` | Content spoken with warnings; style not applied |

Executable counterparts live in `TXT040SSMLTests.swift`,
`LinguisticFrontendTests.swift`, and `ImprovementSprintTwoTests.swift`. Validate
the parser corpus from a clean checkout with:

```bash
swift test --filter SSML
swift test --filter TXT040SSMLTests
```

A documentation edit that changes an expected outcome must update the test
corpus in the same change; prose alone cannot redefine parser behavior.

## Unsupported SSML

CHOIR does not claim W3C SSML compatibility. Elements such as `<audio>`,
`<sub>`, `<p>`, `<s>`, `<lang>`, `<lexicon>`, and the planned expressive
`<style>` element are unsupported. Validate content against this page rather
than assuming another speech engine's SSML will work unchanged.
