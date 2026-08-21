# Voice Book

Browse the 32 stable voice-profile identities and their design targets.

> Important: These pages document metadata and intended character. CHOIR 0.16
> does not ship the trained multi-voice model, so names, conditioning IDs, and
> parameters must not be represented as 32 currently audible, validated
> voices. Pairings and demo passages are design briefs for later acceptance.

## Library grid

| Age | Male profiles | Female profiles |
|---|---|---|
| Child | <doc:Finch>, <doc:Scout>, <doc:Alder>, <doc:Wick> | <doc:Wren>, <doc:Juniper>, <doc:Clover>, <doc:Briar> |
| Young adult | <doc:Orion>, <doc:Flint>, <doc:Reed>, <doc:Corvin> | <doc:Lyra>, <doc:Isla>, <doc:Nova>, <doc:Sable> |
| Middle-aged | <doc:Garrick>, <doc:Hale>, <doc:Bram>, <doc:Malvern> | <doc:Marion>, <doc:Tamsin>, <doc:Greer>, <doc:Ravenna> |
| Elderly | <doc:Alaric>, <doc:Wilfred>, <doc:Cormac>, <doc:Grimshaw> | <doc:Maeve>, <doc:Odette>, <doc:Hattie>, <doc:Hespera> |

Each cell contains three general profiles and one villain archetype. Stable IDs
are persistence keys; display names are presentation. Resolve stored values
with `Voice(id:)`.

## Reading the parameters

- **F0** is the intended fundamental-frequency median and design range.
- **Formant scale** is a vocal-tract-length proxy relative to the young-adult
  male reference at 1.0.
- **Spectral tilt** is the numeric implementation mapping in dB/octave; the
  adjoining descriptor preserves the authored character target.
- **Breathiness** and **roughness** are normalized design indices.
- **Tempo** is the intended base syllables per second.
- **Pitch dynamism** is the intended intonation-contour standard deviation in
  semitones.

## Parameter envelope

Every profile page records the SRS and constructor envelope: pitch −6...+6
semitones, rate 0.6...2.0×, emotion and breathiness 0...1, and age/gender shift
−1...+1. The production quality guarantee remains pending model integration
and listening/intelligibility evaluation at every corner.

## Demo acceptance

The three passages on each page cover short UI/dialogue, expressive character,
and sustained narration. They become gallery demos only after reviewed audio
is generated with the production model, normalized, checked for licensing and
accessibility, and packaged with provenance. Text alone does not satisfy the
audible-demo requirement.
