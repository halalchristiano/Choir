# Training a CHOIR voice

**Status:** this document specifies the path. It has not been executed
end to end, because it needs a GPU and a corpus that does not exist yet. The
commands are written from the recipes' documentation, not from a run in this
repository, and should be treated as a starting point rather than verified
output. Everything upstream of this file — recording, splitting, alignment,
dataset validation — *has* been run against real audio.

---

## Before spending GPU time

```bash
python3 Scripts/prepare_dataset.py recordings/evan/*/ --out dataset
```

It refuses to call a corpus ready below 60 minutes, and that threshold is the
point. Training on four minutes produces a model that imitates a handful of
sentences; it does not produce something that speaks. The GPU hours are the
same either way, so the cheap check comes first.

Each argument is one session directory; every session must name the same
speaker in its `SPEAKER` file, because a model trained on two people learns a
blend of both.

It also fails the corpus for mixed sample rates, clipped takes, empty
transcripts and utterances that are too short or too long. Most recipes would
silently resample or accept these, and the result is a voice that is subtly
wrong on material you cannot trace back.

## The licensing trap

This is the one mistake that cannot be undone after the fact, and it is
specific to CHOIR's business model: the runtime is MIT and the voice packs are
commercial, so the trained weights must be clean for commercial redistribution
(PKG-005).

**Fine-tuning inherits the licence of the checkpoint you start from.** Most
low-data TTS guides tell you to fine-tune a pretrained multi-speaker model,
because it works with 30–60 minutes instead of 20 hours. That is good advice
technically and dangerous legally: a derivative of a research-only checkpoint
is research-only, no matter whose voice is in it.

Before using any checkpoint, establish what it was trained on:

- **LibriTTS** and **VCTK** are CC BY 4.0. Commercial use is permitted with
  attribution; record that attribution in `NOTICE`.
- Many community checkpoints do not state their training data at all. Treat an
  unstated provenance as unusable, not as probably fine.
- Training from scratch on your own recordings avoids the question entirely,
  at the cost of needing several hours of audio rather than one.

Decide this before training, and write the decision into `NOTICE`. It is
item #41 and #86 in the backlog for exactly this reason.

## Recipe

**Piper** (`rhasspy/piper`) is the closest fit: MIT licensed, VITS-based, built
for on-device inference, exports ONNX, and documents a fine-tuning path for
small corpora. Any VITS-family recipe reads the LJSpeech layout that
`prepare_dataset.py` emits, so the choice is not load-bearing.

```bash
# Environment (Linux box or rented GPU; not this Mac)
python3 -m venv .venv && source .venv/bin/activate
pip install piper-tts torch torchaudio

# Preprocess the LJSpeech-layout dataset
python3 -m piper_train.preprocess \
    --language en-gb \
    --input-dir dataset \
    --output-dir training \
    --dataset-format ljspeech \
    --single-speaker \
    --sample-rate 22050

# Train. --resume_from_checkpoint is the fine-tuning path; omit it to train
# from scratch, which needs far more audio but no provenance question.
python3 -m piper_train \
    --dataset-dir training \
    --batch-size 16 \
    --validation-split 0.05 \
    --max_epochs 4000 \
    --precision 16
```

CHOIR records and stores at 48 kHz. Most VITS recipes train at 22.05 kHz.
Downsampling for training is normal and expected; keep the 48 kHz originals,
because you can always go down and never back up.

## Converting to Core ML

The adapters already exist and already validate what they are given. They take
closures, not files:

```swift
// Sources/Choir/Models/AcousticModel.swift
public typealias Inference = @Sendable (AcousticModelInput) async throws -> AcousticFeatures

// Sources/Choir/Models/Vocoder.swift
public typealias Inference = @Sendable (AcousticFeatures, Int) async throws -> [Int16]
```

So the work is: export the trained model, convert it, and write a closure that
maps CHOIR's types onto the model's tensors.

```bash
pip install coremltools onnx
```

`AcousticModelInput` carries `phonemeIndices`, `durations`,
`fundamentalFrequency`, `energy` and `stress` as parallel arrays.
`AcousticFeatures` is a `[[Float]]` of time × frequency. A VITS model is
end-to-end — phonemes straight to waveform — so it does not split along CHOIR's
two-stage boundary. Two options:

1. **Wrap the whole model as the vocoder** and have the acoustic stage pass
   phonemes through as features. Simplest, and gives up CHOIR's separation.
2. **Export the two halves separately**, matching the existing interfaces.
   More faithful to the architecture, more conversion work.

Option 1 first, to get a voice out and measurable. Option 2 once there is
something worth refining.

## Packaging it as a voice pack

A converted model ships inside a `.choirvoice` bundle. Build it with the script,
which hashes every file and reads the engine's version constants from the
Swift sources, then verify it with the engine's own loader:

```bash
python3 Scripts/build_voice_pack.py build/Evan.choirvoice \
    --pack-id studio.bothmade.evan --pack-version 1.0.0 \
    --voice choir.ya.male.orion --sample-rate 22050 \
    --vocoder converted/evan.mlmodelc.zip \
    --speaker-name "Evan" --kind real-person \
    --release-ref "Evan voice release, signed PDF" \
    --signed-on 2026-09-20 --use "commercial CHOIR voice pack"

swift run choir-benchmark --verify-pack build/Evan.choirvoice
```

A real person's pack is refused without a release reference, a signing date,
and permitted uses, and every export from it is labelled synthetic. The date is
when the release was actually signed; the builder refuses one in the future.

The pack format cannot know the model's tensor names, so the last piece is a
`VoicePackModelBinding` that turns the verified pack's files into an
`AcousticModelProtocol` and a `VocoderProtocol`. It receives only packs that
have already passed verification:

```swift
let binding = VoicePackModelBinding { pack in
    let vocoderURL = pack.url(for: .vocoder)!
    // load the compiled model at vocoderURL and wrap it
    return (acoustic: PassThroughAcoustic(), vocoder: EvanVocoder(url: vocoderURL))
}
let library = VoicePackLibrary(directory: voicePacksDirectory)
let engine = try ChoirEngine.preferred(for: .orion, library: library, binding: binding)
print(engine.synthesisSource)   // .voicePack(id: "studio.bothmade.evan", version: "1.0.0")
```

## Then measure it

```bash
swift build -c release
Scripts/make_intelligibility_app.sh build
open build/ChoirIntelligibility.app --args \
    --intelligibility --voice orion --output qua004_trained.md
```

The baselines to beat, both measured in this repository:

| Path | Word accuracy | Target |
|---|---:|---:|
| Mock (default) | ~0% | — |
| Rule-based formant | 8.2% | 98% |
| Trained model | to be measured | 98% |

Record the result next to `QUA004_FORMANT.md` and update `SRS_CONFORMANCE.md`.
`DocumentedFiguresTests` will fail the build if the number in the documents
disagrees with the measurement.

## What this does not cover

- Perceptual distinctness across 32 voices (VOX-G-003). One voice is one voice.
- Naturalness and listening-fatigue gates, which need human listeners, not ASR.
- Real-device performance (PRF), which needs the reference hardware.

Those stay open in `REMAINING_WORK.md` and no amount of training closes them.
