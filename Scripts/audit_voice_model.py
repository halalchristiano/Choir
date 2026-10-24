#!/usr/bin/env python3
"""Compare base/adapted models on all held-out examples, including unused ones."""
import argparse
import json
from pathlib import Path

import mlx.core as mx
import numpy as np
import soundfile as sf
from huggingface_hub import snapshot_download
from mlx_audio.tts.utils import load_model
from voice_finetune_mlx import MODEL, MODEL_REVISION, add_lora, read_rows, training_input, loss_fn


def main():
    p = argparse.ArgumentParser()
    p.add_argument("root", type=Path)
    p.add_argument("--run", default="voice-run-02")
    args = p.parse_args()
    run = args.root / args.run
    config = json.loads((run / "config.json").read_text())
    model = load_model(snapshot_download(MODEL, revision=MODEL_REVISION))
    add_lora(model, config["rank"], config["layers"])
    model.eval()
    speaker = mx.load(str(run / "speaker.safetensors"))["embedding"]
    model.extract_speaker_embedding = lambda *a, **kw: speaker
    reference, sr = sf.read(config["reference"]["audio"], dtype="float32")
    assert sr == 24000
    ref = mx.array(reference)
    rows = read_rows(args.root / "corpus/validation.jsonl")
    inputs = [training_input(model, args.root, r, ref) for r in rows]
    # Confirm that future codec frames cannot affect the first prediction.
    x, y, start = inputs[0]
    changed = mx.concatenate([x[:, :start+1], mx.zeros_like(x[:, start+1:])], axis=1)
    a = model.talker(inputs_embeds=x)[0][:, start]
    b = model.talker(inputs_embeds=changed)[0][:, start]
    error = float(mx.max(mx.abs(a.astype(mx.float32)-b.astype(mx.float32))))
    assert error < 1e-4, f"Causal leakage: {error}"
    scores = {}
    for phase in ("base", "adapted"):
        if phase == "adapted":
            model.load_weights(str(run / "best.safetensors"), strict=False)
        scores[phase] = []
        for item in inputs:
            loss = loss_fn(model, *item)
            mx.eval(loss)
            scores[phase].append(float(loss))
        print(phase, float(np.mean(scores[phase])), flush=True)
    selected = set(config["validation_examples"])
    unseen = [i for i, r in enumerate(rows) if r["id"] not in selected]
    summary = {"validation_examples": len(rows), "checkpoint_selection_examples": len(selected),
               "unused_during_checkpoint_selection": len(unseen), "causal_prefix_max_error": error,
               "base_mean_loss": float(np.mean(scores["base"])),
               "adapted_mean_loss": float(np.mean(scores["adapted"])),
               "base_unused_mean_loss": float(np.mean([scores["base"][i] for i in unseen])),
               "adapted_unused_mean_loss": float(np.mean([scores["adapted"][i] for i in unseen])),
               "note": "Codec prediction loss is not a listening or speaker-similarity assessment."}
    (run / "held-out-audit.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary), flush=True)


if __name__ == "__main__":
    main()
