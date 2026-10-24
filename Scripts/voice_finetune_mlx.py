#!/usr/bin/env python3
"""Local Qwen3-TTS speaker adaptation using MLX LoRA.

Uses the installed MLX-Audio generation prefix verbatim, all 16 audio
codebooks as teacher-forced context, and next-token codebook-0 loss. The
residual code predictor, speaker encoder, and tokenizer remain frozen.
This is a small speaker-adaptation experiment, not the full Qwen SFT recipe.
"""
import argparse
import json
import math
import random
import time
from pathlib import Path

import mlx.core as mx
import mlx.nn as nn
import mlx.optimizers as optim
import numpy as np
import soundfile as sf
from mlx.utils import tree_flatten
from mlx_audio.tts.utils import load_model

MODEL = "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
MODEL_REVISION = "50f45ef0047cde7e84c2ef04326acb8ada2436a7"


class LoRALinear(nn.Module):
    def __init__(self, base, rank=8, alpha=16):
        super().__init__()
        self.base = base
        self.base.freeze()
        if isinstance(base, nn.QuantizedLinear):
            input_dim = base.weight.shape[1] * (32 // base.bits)
        else:
            input_dim = base.weight.shape[1]
        output_dim = base.weight.shape[0]
        self.lora_a = mx.random.uniform(-1 / math.sqrt(input_dim), 1 / math.sqrt(input_dim), (input_dim, rank))
        self.lora_b = mx.zeros((rank, output_dim))
        self.scale = alpha / rank

    def __call__(self, x):
        return self.base(x) + (x @ self.lora_a.astype(x.dtype) @ self.lora_b.astype(x.dtype)) * self.scale


def add_lora(model, rank, layers):
    model.freeze()
    for layer in model.talker.model.layers[-layers:]:
        for name in ("q_proj", "k_proj", "v_proj", "o_proj"):
            setattr(layer.self_attn, name, LoRALinear(getattr(layer.self_attn, name), rank, 2 * rank))
    count = sum(v.size for _, v in tree_flatten(model.trainable_parameters()))
    assert count > 0
    print(f"Trainable LoRA parameters: {count:,}", flush=True)
    return count


def read_rows(path):
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()]


def codec_file(root, row):
    return root / "codes" / (row["id"] + ".npy")


def encode(args, model):
    root = args.root
    (root / "codes").mkdir(exist_ok=True)
    rows = read_rows(root / "corpus/train.jsonl") + read_rows(root / "corpus/validation.jsonl")
    for i, row in enumerate(rows):
        path = codec_file(root, row)
        if path.exists():
            continue
        wav, sr = sf.read(row["audio"], dtype="float32")
        assert sr == 24000 and wav.ndim == 1
        codes = model.speech_tokenizer.encode(mx.array(wav)[None, None, :])
        mx.eval(codes)
        codes = np.asarray(codes[0].T).astype(np.int32)
        assert codes.ndim == 2 and codes.shape[1] == 16 and codes.min() >= 0 and codes.max() < 2048, codes.shape
        np.save(path, codes)
        mx.clear_cache()
        if i % 10 == 0:
            print(f"ENCODE {i+1}/{len(rows)} {codes.shape}", flush=True)


def reference(root):
    rows = read_rows(root / "corpus/train.jsonl")
    candidates = [r for r in rows if "choir recording 1" in r["source"] and 5 <= r["seconds"] <= 10]
    row = max(candidates or rows, key=lambda r: r["mean_word_confidence"])
    (root / "reference.json").write_text(json.dumps(row, indent=2))
    return row


def training_input(model, root, row, ref_audio):
    prefix, _, pad = model._prepare_generation_inputs(row["text"], language="english", ref_audio=ref_audio)
    codes = mx.array(np.load(codec_file(root, row)))
    emb = model.talker.get_input_embeddings()(codes[None, :, 0])
    for i in range(1, 16):
        emb = emb + model.talker.code_predictor.codec_embedding[i - 1](codes[None, :, i])
    inputs = mx.concatenate([prefix, emb + pad], axis=1)
    labels = mx.concatenate([codes[:, 0], mx.array([model.config.talker_config.codec_eos_token_id])])
    mx.eval(inputs, labels)
    return mx.stop_gradient(inputs), labels, prefix.shape[1] - 1


def loss_fn(model, inputs, labels, start):
    return talker_loss_fn(model.talker, inputs, labels, start)


def talker_loss_fn(talker, inputs, labels, start):
    logits, _ = talker(inputs_embeds=inputs)
    logits = logits[0, start:, :].astype(mx.float32)
    assert logits.shape[0] == labels.shape[0]
    return nn.losses.cross_entropy(logits, labels, reduction="mean")


def train(args, model):
    root = args.root
    run = root / args.run
    run.mkdir(parents=True, exist_ok=True)
    random.seed(args.seed)
    mx.random.seed(args.seed)
    row = reference(root)
    audio, sr = sf.read(row["audio"], dtype="float32")
    ref_audio = mx.array(audio)
    # Cache a frozen x-vector; avoid running the speaker encoder every step.
    speaker_embedding = model.extract_speaker_embedding(ref_audio)
    mx.eval(speaker_embedding)
    model.extract_speaker_embedding = lambda *a, **kw: speaker_embedding
    count = add_lora(model, args.rank, args.layers)
    train_rows = [r for r in read_rows(root / "corpus/train.jsonl") if codec_file(root, r).exists()]
    val_rows = [r for r in read_rows(root / "corpus/validation.jsonl") if codec_file(root, r).exists()]
    assert train_rows and val_rows
    random.shuffle(train_rows)
    (run / "training-order.jsonl").write_text("".join(json.dumps({k: r[k] for k in ("id", "source", "seconds")}) + "\n" for r in train_rows))
    val_rows = random.sample(val_rows, min(args.validation_samples, len(val_rows)))
    val_inputs = [training_input(model, root, r, ref_audio) for r in val_rows]
    config = {"base_model": MODEL, "base_revision": MODEL_REVISION, "rank": args.rank, "layers": args.layers, "seed": args.seed,
              "learning_rate": args.learning_rate, "trainable_parameters": count,
              "objective": "next_codebook_0_with_all_16_codebooks_teacher_forced",
              "train_examples": len(train_rows), "validation_examples": [r["id"] for r in val_rows],
              "reference": row, "max_steps": args.steps,
              "residual_code_predictor_trained": False}
    (run / "config.json").write_text(json.dumps(config, indent=2))
    mx.save_safetensors(str(run / "speaker.safetensors"), {"embedding": speaker_embedding})
    optimizer = optim.AdamW(learning_rate=args.learning_rate, weight_decay=.01)
    # Only the talker is differentiated. MLX-Audio compiles its independent
    # vocoder decoder into a callable, which is not an updatable Module tree.
    grad_fn = nn.value_and_grad(model.talker, talker_loss_fn)
    log = (run / "metrics.jsonl").open("w", buffering=1)

    def evaluate(step):
        model.eval()
        values = []
        for x in val_inputs:
            value = loss_fn(model, *x)
            mx.eval(value)
            values.append(float(value))
        score = float(np.mean(values))
        record = {"step": step, "validation_loss": score, "seconds": time.time() - begun}
        print(json.dumps(record), flush=True)
        log.write(json.dumps(record) + "\n")
        model.train()
        return score

    def save(name):
        weights = {"talker." + k: v for k, v in tree_flatten(model.talker.trainable_parameters())}
        assert weights and all("lora_" in k for k in weights)
        mx.save_safetensors(str(run / name), weights)

    begun = time.time()
    best = evaluate(0)
    baseline = best
    for step in range(1, args.steps + 1):
        row = train_rows[(step - 1) % len(train_rows)]
        inp = training_input(model, root, row, ref_audio)
        value, grads = grad_fn(model.talker, *inp)
        grads, norm = optim.clip_grad_norm(grads, 1.)
        optimizer.update(model.talker, grads)
        mx.eval(model.talker.trainable_parameters(), optimizer.state, value, norm)
        if not math.isfinite(float(value)) or not math.isfinite(float(norm)):
            raise RuntimeError("Non-finite training value")
        if step % 5 == 0 or step == 1:
            record = {"step": step, "train_loss": float(value), "gradient_norm": float(norm),
                      "seconds": time.time() - begun, "peak_memory_gb": mx.get_peak_memory() / 1e9}
            print(json.dumps(record), flush=True)
            log.write(json.dumps(record) + "\n")
        if step % args.eval_every == 0 or step == args.steps:
            score = evaluate(step)
            save("latest.safetensors")
            if score < best:
                best = score
                save("best.safetensors")
                (run / "best.json").write_text(json.dumps({"step": step, "validation_loss": best, "baseline_validation_loss": baseline}, indent=2))
        mx.clear_cache()
    log.close()
    print("TRAINING_COMPLETE", flush=True)


def generate(args, model):
    root = args.root
    run = root / args.run
    if args.adapter:
        config = json.loads((run / "config.json").read_text())
        if not isinstance(model.talker.model.layers[-1].self_attn.q_proj, LoRALinear):
            add_lora(model, config["rank"], config["layers"])
        model.load_weights(str(run / args.adapter), strict=False)
        row = config["reference"]
        # Bake the saved x-vector into the same reserved speaker-token slot
        # used by Qwen's official fine-tuning export. Inference then needs
        # only the adapter, speaker vector, and pinned base model.
        speaker = mx.load(str(run / "speaker.safetensors"))["embedding"]
        embedding = model.talker.get_input_embeddings()
        assert not isinstance(embedding, nn.QuantizedEmbedding)
        weight = embedding.weight
        weight[3000] = speaker.reshape(-1).astype(weight.dtype)
        embedding.weight = weight
        model.config.talker_config.spk_id = {"choirreading": 3000}
        model.supported_speakers = ["choirreading"]
        conditioning = {"voice": "choirreading"}
    else:
        row = reference(root)
        conditioning = {"ref_audio": row["audio"]}
    model.eval()
    mx.random.seed(args.seed)
    outputs = []
    for result in model.generate(text=args.text, **conditioning, lang_code="english",
                                 max_tokens=500, temperature=.7, top_p=.9, repetition_penalty=1.05):
        mx.eval(result.audio)
        outputs.append(np.asarray(result.audio).reshape(-1))
    wav = np.concatenate(outputs)
    assert np.isfinite(wav).all() and len(wav) > 24000 and np.sqrt(np.mean(wav ** 2)) > .002
    args.output.parent.mkdir(parents=True, exist_ok=True)
    sf.write(args.output, wav, model.sample_rate, subtype="PCM_16")
    args.output.with_suffix(".json").write_text(json.dumps({"text": args.text, "seed": args.seed,
        "sample_rate": model.sample_rate, "seconds": len(wav) / model.sample_rate,
        "adapter": str(run / args.adapter) if args.adapter else None,
        "mode": "fine_tuned" if args.adapter else "pretrained_reference_conditioned_baseline",
        "reference": "saved speaker embedding" if args.adapter else row["audio"]}, indent=2))
    print(f"GENERATED {args.output}: {len(wav)/model.sample_rate:.2f}s", flush=True)


def pipeline(args, model):
    # Cache the completed transcripts while longer recordings finish ASR.
    encode(args, model)
    expected = list((args.root / "raw/readiong 1221_data/clips").glob("*.wav"))
    if not expected:
        raise RuntimeError("No extracted project recordings found")
    while True:
        pending = [p for p in expected if not (args.root / "transcripts" / p.stem.replace(" ", "_") / "combined.json").exists()]
        if not pending:
            break
        print(f"Waiting for {len(pending)} remaining recording transcripts", flush=True)
        time.sleep(30)
    from prepare_voice_corpus import main as prepare
    prepare([str(args.root)])
    encode(args, model)
    fit(args, model)


def fit(args, model):
    if args.steps <= 0:
        args.steps = len(read_rows(args.root / "corpus/train.jsonl"))
    train(args, model)
    args.adapter = "best.safetensors"
    if not (args.root / args.run / args.adapter).exists():
        raise RuntimeError("Fine-tuning did not improve held-out loss; do not publish as a successful voice")
    args.output = args.root / "previews/fine-tuned-reading.wav"
    generate(args, model)
    args.text = "A careful argument deserves a patient hearing. We can disagree about a conclusion while still treating one another with respect."
    args.output = args.root / "previews/fine-tuned-reflection.wav"
    generate(args, model)
    print("PIPELINE_COMPLETE", flush=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("action", choices=["encode", "train", "generate", "pipeline", "fit"])
    p.add_argument("root", type=Path)
    p.add_argument("--run", default="voice-run-01")
    p.add_argument("--rank", type=int, default=8)
    p.add_argument("--layers", type=int, default=12)
    p.add_argument("--steps", type=int, default=400)
    p.add_argument("--learning-rate", type=float, default=2e-5)
    p.add_argument("--eval-every", type=int, default=50)
    p.add_argument("--validation-samples", type=int, default=16)
    p.add_argument("--seed", type=int, default=20261024)
    p.add_argument("--adapter")
    p.add_argument("--text", default="Today, we pause to listen carefully, to seek understanding, and to carry kindness into the world.")
    p.add_argument("--output", type=Path)
    args = p.parse_args()
    args.root = args.root.resolve()
    from huggingface_hub import snapshot_download
    model_path = snapshot_download(MODEL, revision=MODEL_REVISION)
    model = load_model(model_path)
    model.eval()
    assert model.speech_tokenizer is not None and model.speech_tokenizer.has_encoder
    {"encode": encode, "train": train, "generate": generate, "pipeline": pipeline, "fit": fit}[args.action](args, model)


if __name__ == "__main__":
    main()
