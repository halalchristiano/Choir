# Integration Recipes

Map CHOIR's public building blocks to the five product scenarios in the
requirements. Each recipe distinguishes code that exists from the production
capabilities that remain gated.

## THE ONE: verse-addressed playback

Represent each verse as a stable application-level record and place a named
mark before its text:

```swift
struct Verse: Sendable {
    let id: String
    let text: String
}

let verses = [
    Verse(id: "John.3.16", text: "For God so loved the world…"),
    Verse(id: "John.3.17", text: "For God sent not his Son…")
]

let markup = "<speak>" + verses.map {
    #"<mark name="\#($0.id)"/>\#($0.text)"#
}.joined(separator: #"<break strength="medium"/>"#) + "</speak>"

let result = try await engine.synthesize(
    input: .markup(markup),
    voice: .maeve,
    parameters: SynthesisParameters(seed: 1)
)

let verseStarts = Dictionary(uniqueKeysWithValues: verses.compactMap { verse in
    result.metadata.time(ofMark: verse.id).map { (verse.id, $0) }
})
```

Use ``NormalizationPolicy`` with the selected ``ScriptureStyle`` when building
a custom ``LinguisticFrontend`` and ``SynthesisPipeline``. A ``UserLexicon``
snapshot can supply app-specific pronunciations:

```swift
let lexicon = UserLexicon()
await lexicon.register(word: "Socinus", respelling: "so SEE nus")

let policy = NormalizationPolicy(
    expandsScriptureReferences: true,
    scriptureStyle: .spokenFull
)
let frontend = LinguisticFrontend(
    normalizer: TextNormalizer(policy: policy)
).withUserLexicon(await lexicon.snapshot())

let pipeline = SynthesisPipeline(
    linguisticFrontend: frontend,
    acousticModel: productionAcousticModel,
    vocoder: productionVocoder
)
```

The app can persist the original verse boundaries and resulting mark offsets
for highlighting and seek. One-call translation/book/chapter lookup,
background chapter rendering, persistent pinning, complete divine-name rules,
and production timing validation remain to be implemented.

## THE ONE corpus: long theological works

Normalize source structure before synthesis:

1. Convert headings to chapter records and a strong break.
2. Convert footnotes to either omitted text or a deferred notes chapter; do
   not rely on an unsupported `<sub>` or `<skip>` tag.
3. Register names in ``UserLexicon`` and review its snapshot before rendering.
4. Assign one stable seed per chapter.
5. Render one chapter per resumable work unit and atomically persist its WAV
   plus timing/provenance sidecar.
6. Resume by checking the source hash, parameters, engine version, and output
   integrity—not merely the presence of a file.

The package provides persistent synthesis-cache pinning, but not the durable
job controller or chaptered M4B assembler required for a one-call corpus
workflow.

## Ponte: translated document to audiobook

Map document semantics rather than sending visually extracted text unchanged:

| Document element | Speech mapping |
|---|---|
| Title | Separate chapter, paragraph break, pitch reset |
| Heading | Chapter/section boundary and named mark |
| Paragraph | Paragraph-strength break |
| Block quote | Separate segment with a restrained parameter shift |
| Footnote marker | Omit from body or replace with a notes reference |
| Footnote body | Skip, defer to end of section, or render as notes chapter |
| Page header/footer | Remove during extraction |
| Table | Supply an app-authored linear reading order |

Persist a manifest containing source-document hash, section IDs and hashes,
voice ID, validated parameters, seed, package/engine/model/asset versions,
output URL, byte count, checksum, duration, and status. On restart, invalidate
only sections whose inputs changed.

The current batch API can render independent strings and report per-item
failures; ``TimelineAudioExporter`` creates WAV/timing/SRT/VTT line bundles.
It does not persist job progress across launches or create M4B, AAC, ALAC, or
CAF containers. A 150,000-word acceptance render is still required on
production models.

## Games: dialogue, interruption, and lip-sync

Store stable voice identifiers and parameters in game data:

```json
{
  "character": "gatekeeper",
  "voice": "choir.mid.male.garrick",
  "parameters": {
    "pitchShift": -1.0,
    "rate": 0.92,
    "emotionalIntensity": 0.55,
    "breathiness": 0.08,
    "seed": 8128
  }
}
```

Resolve with `Voice(id:)`, reject unknown IDs, and cancel the active task when
game state invalidates a bark. The engine offers task cancellation,
phrase-progressive timing callbacks, and ``DialogueQueue``; the spatial layer
and production-device latency evidence are not implemented.

### Reference phoneme-to-viseme map

Treat this as a portable starting map, then calibrate timing and blend shapes
for the target rig. Silence and pauses use `REST`.

| Viseme | IPA phonemes | Typical mouth cue |
|---|---|---|
| `PP` | p, b, m | Lips closed |
| `FF` | f, v | Lower lip to upper teeth |
| `TH` | θ, ð | Tongue at teeth |
| `DD` | t, d, n, l | Tongue behind upper teeth |
| `KK` | k, ɡ, ŋ | Back tongue raised |
| `CH` | tʃ, dʒ, ʃ, ʒ | Rounded, forward constriction |
| `SS` | s, z | Narrow teeth |
| `RR` | r | Lips slightly rounded |
| `AA` | ɑ, ʌ, aɪ, aʊ | Open jaw |
| `E` | ɛ, æ, eɪ | Mid-open, spread |
| `I` | ɪ, iː, j | Narrow, spread |
| `O` | ɔ, oʊ, ɔɪ | Rounded |
| `U` | ʊ, uː, w | Tight rounding |
| `SCHWA` | ə, ɝ | Relaxed neutral |
| `REST` | h and non-speech gaps | Neutral/rest |

At playback time, query `metadata.phoneme(at:)`, map its `content`, and ease
between the previous and next viseme. Coarticulation, anticipatory rounding,
rig-specific blend weights, and engine/plugin integration remain application
responsibilities.

## Video: deterministic script-to-takes

Use a versioned manifest in source control:

```json
{
  "schemaVersion": 1,
  "lines": [
    {
      "id": "scene-04-line-012",
      "character": "narrator",
      "voice": "choir.eld.female.maeve",
      "text": "The road narrowed at dusk.",
      "seed": 44012,
      "rate": 0.95
    }
  ]
}
```

For each line, resolve the voice, build validated parameters, synthesize with
metadata, write the implemented WAV form atomically, and create a sidecar with
duration and timing. Store a SHA-256 digest of the manifest entry and output.
Never overwrite an approved take without retaining its prior manifest.

Per-line rendering can be assembled from public APIs now. Package-owned JSON
sidecars, SRT/VTT generation, multiple-take selection, and the complete
script-to-takes convenience API remain unimplemented.

## Showcase app: public API proof

Build every screen in a separate consuming target that imports only `Choir`.
Do not use `@testable import`, source-relative asset paths, or internal model
hooks. At minimum, the showcase should exercise:

- all stable voice IDs and metadata;
- parameter validation and clamping reports;
- plain-text and explicit markup input;
- timing metadata and diagnostics;
- cancellation, lifecycle, and typed errors;
- WAV export and app-owned playback/session policy;
- the production model only after its assets and quality gates pass.

Gallery audio for all voices, production export formats, progressive
streaming, spatial playback, and validated live controls remain release gates.
