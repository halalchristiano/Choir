# Local voice fine-tuning experiment

This workflow adapts Qwen3-TTS on Apple Silicon using MLX. It produces actual
learned LoRA weights and WAV previews. Its artifacts are separate from Choir's
existing Swift voice-pack runtime; a successful experiment does not by itself
make the model runnable inside The One on iPhone.

## Data and reproducibility

The current private working directory is
`/Volumes/UnitarianArchive/Choir-Voice-2026-10-24`.
It contains the untouched downloaded recordings, extracted project audio,
source-relative word timestamps, filtered audio/text pairs, codec tokens,
environment lock file, training metrics, adapters, and generated previews.
Recordings and model weights must stay outside this repository.

`prepare_voice_corpus.py` converts completed Whisper `combined.json` files
into 24 kHz mono PCM16 examples. It rejects low-confidence transcriptions,
near-silence, excessive clipping, and unsuitable example lengths. The last
10% of each source is reserved for validation with a boundary buffer. Exact
repeated text is removed from training when it also occurs in validation.
Examples with more than half of their five-word phrases occurring in
validation are also removed, including overlapping passages from retakes.
These checks are automatic; they do not claim human transcript verification.

`extract_audacity_clips.py` follows the project XML's sample-block order and
trims. It supports mono clips without pitch/time changes and refuses
unsupported layouts. Audacity int24 samples occupy signed 32-bit containers;
the exporter converts those values to packed PCM24 rather than copying their
bytes directly. It reads the source database immutably. The official project's
XML export can repeat attributes; this script reports those and retains the
last value, matching the project's reader.

## Adaptation

`voice_finetune_mlx.py` pins the MLX model revision in its source. It freezes
the pretrained model and inserts rank-8 LoRA adapters into the query, key,
value, and output projections of the final 12 talker layers. It uses the
model's own generation-prefix builder, a fixed speaker embedding, and all
16 audio codebooks as teacher-forced context. The loss predicts codebook 0
and the end-of-speech token. The residual code predictor stays frozen.

This is a limited speaker adaptation recipe, not a reproduction of the
official full-parameter Qwen supervised fine-tuning recipe. Training logs
record held-out loss before training and at regular checkpoints. `best` is
saved only when held-out loss improves; the pipeline fails if no checkpoint
improves. Loss alone does not establish naturalness or speaker likeness.

Example commands after setting up the recorded environment:

```sh
RUN=/Volumes/UnitarianArchive/Choir-Voice-2026-10-24
export HF_HOME="$RUN/cache/huggingface"
"$RUN/venv/bin/python" Scripts/prepare_voice_corpus.py "$RUN"
"$RUN/venv/bin/python" Scripts/voice_finetune_mlx.py encode "$RUN"
"$RUN/venv/bin/python" Scripts/voice_finetune_mlx.py train "$RUN" --steps 400
"$RUN/venv/bin/python" Scripts/voice_finetune_mlx.py generate "$RUN" \
  --adapter best.safetensors --output "$RUN/previews/custom.wav" \
  --text "A new sentence that does not appear in the training recordings."
```

The `pipeline` command additionally waits for all four extracted Audacity
clips to have complete transcripts, refreshes the corpus, encodes new
examples, trains, and generates two previews. It assumes this session's
directory layout. For another session use the individual commands.

For a complete pass over an already encoded corpus, use `fit --steps 0`.
Adapted inference uses the saved speaker vector in reserved speaker token
3000, so it does not need the original reference recording. The separate
`audit_voice_model.py` command checks causal masking and compares all held-out
examples against the base model. `evaluate_voice_previews.py` measures ASR
word error rate and clipping on generated WAV files.

## Result from 24 October 2026

The completed `voice-run-02` used 840 training examples (101.20 minutes),
with 93 examples (10.51 minutes) reserved. All 840 training steps completed.
Checkpoint 800 had the best selection score: 0.78814, compared with 0.98068
before adaptation. A subsequent audit of all 93 held-out examples improved
mean loss from 1.00915 to 0.83571. The 77 examples unused for checkpoint
selection also improved, from 1.01507 to 0.84559. The causal-mask test passed.

The adapter contains 983,040 trainable parameters. Two unseen-text previews
generated from the saved speaker vector had zero ASR word errors and no
clipped samples. These are automatic checks; human listening assessment of
likeness and naturalness remains outstanding. Full metrics and source
hashes are saved with the private run artifacts.

Before app integration, assess unseen text for intelligibility and speaker
likeness, benchmark memory/latency on the intended devices, and implement a
compatible inference path. No app release or deployment is performed by
these scripts.
