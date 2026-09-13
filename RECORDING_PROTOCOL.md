# CHOIR voice recording protocol

**For:** one speaker, one voice, one production model (SRS ML-A, ML-V, item #42)
**Target:** 1–3 hours of usable speech
**Status of this document:** the script below is verified by
`RecordingScriptTests` to exercise all 40 symbols in `PhonemeInventory`. If you
edit the script, the test tells you what you broke.

---

## Before you record anything: the licence question

Your runtime is MIT and your revenue is voice packs, so the recordings and
anything trained on them must be licence-clean for **commercial
redistribution**. `NOTICE` already commits the project to this under PKG-005.

- **Your own voice, your own recordings** — cleanest. You own it outright.
- **A hired speaker** — needs a signed buyout covering synthetic voice creation,
  commercial distribution, and derivative models. A standard voiceover release
  usually does *not* cover training a model. Get this in writing before the
  session, not after.
- **A public dataset** — most are research-only. Check before you train, not
  after. This is unrecoverable if you get it wrong.

For bulk reading material, use the **World English Bible (WEB)**. It is
dedicated to the public domain, it is modern English, and it is your actual
domain. `Scripts/make_reading_sheets.py` turns it into numbered 30-minute
sheets. The King James Bible is also public domain, but its archaic forms
("thee", "cometh") would skew the voice toward speech nobody uses.

---

## Do not record these

The 20 Harvard sentences in `HarvardSentences.standard` are the **QUA-004
evaluation corpus**. Training on them contaminates the only quality measurement
this project has — the model would be scored on sentences it memorised.

Keep them out of the training set. If you want more Harvard sentences for
training, use a different subset of the 720 and record which subset you used.

---

## Technical specification

| Setting | Value | Why |
|---|---|---|
| Sample rate | 48 kHz | Matches `AudioFormat` default; no resampling before training |
| Bit depth | 24-bit | Headroom for post-processing; the engine outputs 16-bit |
| Channels | Mono | The engine is mono end to end |
| Format | WAV (uncompressed) | No lossy artefacts in training data |
| Peak level | about −6 dBFS | Loud enough for SNR, far from clipping |
| Noise floor | below −60 dBFS | Quiet enough that the model learns speech, not room |
| Head/tail silence | 200–300 ms | Consistent boundaries; the model learns utterance edges |

**No processing at record time.** No compression, no limiting, no EQ, no noise
reduction, no de-essing. The engine has its own mastering chain (AUD-020/021)
and baked-in processing cannot be undone. Record flat.

## Session discipline

The model learns whatever is consistent, including your mistakes.

- **One mic, one position, one gain setting** across every session. Mark the
  mic and chair positions. Mouth about 20 cm from the mic, slightly off-axis,
  pop filter in place.
- **One speaker per voice.** Never combine two people's sessions into one
  corpus: the model learns a blend of both and sounds like neither.
  `prepare_dataset.py` refuses to assemble sessions whose `SPEAKER` files
  disagree.
- **One room.** Different rooms sound like different voices.
- **One time of day if you can.** Voices change between morning and evening.
- **Short sessions.** 30 minutes maximum, one per day. Fatigue changes timbre
  and pace, and the model will learn the fatigue.
- **Consistent pace and energy.** Read as if explaining something to one
  attentive person. Not performing, not announcing, not lulling.
- **Re-record the whole utterance**, never punch in. A spliced file has a seam
  the model will learn.
- **Log the discards.** If you re-take a line, keep the take number; do not
  overwrite silently.

## Files and manifest

```
recordings/
  wav/
    choir_0001.wav
    choir_0002.wav
  metadata.csv
```

`metadata.csv`, one line per utterance, pipe-separated, no header:

```
choir_0001|The polished birch bridge crossed a shallow stream.|The polished birch bridge crossed a shallow stream.
```

Fields are `id|raw transcript|normalized transcript`. Keep both: the raw text is
what you read, the normalized text is what the front end would produce, and the
difference is exactly what CHOIR's text normalization is responsible for. For
plain sentences they are identical; for anything with numbers or Scripture
references they will not be, and that difference is worth keeping.

Transcripts must match what you actually said, including any stumble you chose
to keep. A transcript that disagrees with the audio teaches the model a wrong
mapping and is worse than discarding the take.

---

## Part A — calibration (record once per session)

1. **Room tone.** 10 seconds of silence, nobody moving. This is your noise
   floor and your evidence that the room did not change between sessions.
2. **Level check.** Read Part B line 1 at your intended volume. Check the peak
   sits near −6 dBFS. Do not adjust gain after this point.

## Part B — phonetic coverage

Every symbol in `PhonemeInventory` appears here, most of them in several
contexts. Read all of them. Verified by `RecordingScriptTests`.

1. The polished birch bridge crossed a shallow stream.
2. Odd thoughts caught her at the office door.
3. That cat sat on a flat black mat.
4. He cut the rough bread and shut the hut door.
5. About a dozen of them arrived from the station.
6. I ought to have bought the tall walnut cabinet.
7. The brown cow found her way out of the crowded house.
8. I tried to hide the bright kite behind the pile.
9. The nurse heard the early bird chirp in the fern.
10. They ate the plain cake they made yesterday.
11. It is a bit thick, and it will fit in this tin.
12. Each evening we eat a clean meal and read a little.
13. He rowed the old boat home alone over cold water.
14. The boy enjoyed the noisy toy his employer destroyed.
15. She took a good look at the wool hood on the hook.
16. Two blue shoes moved through the room to the pool.
17. Ten eggs fell and left a mess on the wet step.
18. Bob grabbed a rubber tube from the cab beside the club.
19. The chief chose cheap cheese and a rich chocolate cherry.
20. Did the dog dig down under the old red shed?
21. They gathered together, breathing in the smooth weather.
22. Four friends found a fifth flag left in the soft office.
23. The big green flag hung against the rugged gate.
24. He held his hat behind him in the hallway.
25. George urged the judge to enjoy the gentle jury.
26. Take the black kite back to the market kiosk.
27. Lily will fill the little yellow bottle slowly.
28. My mother came home and made him a warm meal.
29. Nine noisy children ran down the narrow lane.
30. Singing and ringing, the young king was banging a long gong.
31. Please put the paper cup on the top step.
32. Our friend carried the red barrel around the corner.
33. The sun rose slowly across the misty grass.
34. She should wash the fresh fish in the shallow dish.
35. Take the little metal kettle out to the front gate.
36. I think the thin path through the north is worth it.
37. Every valve moved over the curved silver cover.
38. We waited a while, watching the wet weather worsen.
39. Yesterday the young lawyer used your yellow folder.
40. The lazy zebra dozed in the zoo, buzzing with bees.
41. The casual measure of pleasure was an unusual decision.
42. Who has the whole thing? He said he had it here.
43. A heavy crate of glass bottles arrived this morning.
44. Fasten the loose sheet to the dark wooden frame.
45. The scent of lemons filled the small warm kitchen.

## Part C — prosody and phrasing

The model learns intonation from what you give it. A script of flat declarative
statements produces a flat voice. These exercise questions, lists, contrast,
breath groups and terminal tones — which is exactly what `ProsodyPredictor` and
the SSML-C break handling are written against.

46. Did you actually read the whole thing, or only the first part?
47. Where are you going?
48. Stop. Put it down and step away from the table.
49. We need bread, milk, two dozen eggs, a bag of flour, and salt.
50. It was not the answer she wanted, but it was the truth.
51. I did not say he stole the money. I said someone did.
52. What a remarkable, extraordinary, entirely unexpected thing to happen.
53. If the weather holds, and if the road is clear, we will leave at dawn.
54. He paused, considered it for a long moment, and then agreed.
55. No. Absolutely not. Not under any circumstances.
56. Wait — did you hear that?
57. She whispered it so quietly that nobody else in the room noticed.
58. The meeting is at half past three on Thursday afternoon.
59. First, we measure. Then we decide. Only then do we build.
60. And that, in the end, is the whole of the matter.

## Part D — domain: Scripture and theology

Your differentiator. These exercise `TheologicalLexicon`, Scripture reference
parsing (TXT-011) and the number handling (TXT-013) all at once.

61. In the beginning God created the heaven and the earth.
62. The book of Ecclesiastes, chapter three, verse one.
63. See First Corinthians thirteen, verses four through seven.
64. Melchizedek, king of Salem, brought forth bread and wine.
65. The letter to the Philippians was written from prison.
66. Habakkuk, Zephaniah, Haggai, Zechariah, and Malachi.
67. Blessed are the peacemakers, for they shall be called the children of God.
68. Read Second Chronicles seven fourteen aloud, slowly.
69. The Nicene Creed speaks of one baptism for the remission of sins.
70. Eschatology, soteriology, and ecclesiology are not the same subject.
71. Deuteronomy six, four. Hear, O Israel.
72. He turned to the Epistle of James and read the first chapter.
73. The Septuagint predates the Masoretic text we use today.
74. Thessalonians, Colossians, Ephesians, and Galatians.
75. Psalm one hundred and nineteen is the longest in the psalter.

---

## Scaling to a full corpus

Parts B–D are about 10 minutes of speech. You need 1–3 hours, so you need
roughly 800–1,500 utterances in total.

Take the rest from the World English Bible: public domain, modern English, in
your domain, and effectively unlimited. Split it into single sentences of 5–20 words,
skip anything over 25 words (long utterances are harder to align), and record
in the same voice and setting as Parts B–D.

Keep Parts B–D at the front of the corpus. If you run out of time or voice, you
will still have full phonetic and prosodic coverage, which matters more than
raw duration.

## When you have the recordings

The training step is item #40 and #42. I can take it from the manifest: the
data goes to a VITS-family recipe, the result converts to Core ML, and the
adapters in `CoreMLAcousticModel` and `CoreMLVocoder` already accept injected
inference closures, so the landing zone exists.

Then point the QUA-004 harness at it:

```bash
swift build -c release
Scripts/make_intelligibility_app.sh build
open build/ChoirIntelligibility.app --args --intelligibility --voice orion --output qua004.md
```

The formant baseline to beat is 8.2% word accuracy. The target is 98%.
