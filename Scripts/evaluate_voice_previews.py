#!/usr/bin/env python3
"""Back-transcribe generated speech and report automatic intelligibility checks.

Whisper WER is a diagnostic, not a substitute for a listening assessment.
"""
import argparse
import hashlib
import json
import math
import re
from pathlib import Path

import mlx_whisper
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly


def words(s):
    return re.findall(r"[a-z0-9]+(?:'[a-z]+)?", s.lower().replace("’", "'"))


def distance(a, b):
    row = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        nxt = [i]
        for j, y in enumerate(b, 1):
            nxt.append(min(nxt[-1] + 1, row[j] + 1, row[j-1] + (x != y)))
        row = nxt
    return row[-1]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("root", type=Path)
    args = p.parse_args()
    b = args.root
    training = [json.loads(s)["text"] for s in (b / "corpus/train.jsonl").read_text().splitlines()]
    training_text = " ".join(" ".join(words(s)) for s in training)
    results = []
    for metadata in sorted((b / "previews").glob("*.json")):
        info = json.loads(metadata.read_text())
        if "text" not in info or "mode" not in info:
            continue
        path = metadata.with_suffix(".wav")
        wav, sr = sf.read(path, dtype="float32")
        assert wav.ndim == 1 and np.isfinite(wav).all()
        g = math.gcd(sr, 16000)
        audio = resample_poly(wav, 16000 // g, sr // g).astype(np.float32)
        transcription = mlx_whisper.transcribe(audio, path_or_hf_repo="mlx-community/whisper-large-v3-turbo",
            language="en", temperature=0., condition_on_previous_text=False, verbose=None)
        actual = transcription["text"].strip()
        expected_words = words(info["text"])
        row = {"audio": str(path), "mode": info["mode"], "expected_text": info["text"],
               "recognized_text": actual, "word_error_rate": distance(expected_words, words(actual)) / len(expected_words),
               "seconds": len(wav)/sr, "peak": float(np.abs(wav).max()),
               "rms": float(np.sqrt(np.mean(wav ** 2))),
               "clipped_fraction": float(np.mean(np.abs(wav) >= .999)),
               "exact_prompt_in_training": " ".join(expected_words) in training_text,
               "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        results.append(row)
        print(json.dumps(row), flush=True)
    (b / "preview-evaluation.json").write_text(json.dumps({"method": "automatic ASR back-transcription",
        "human_listening_review_completed": False, "results": results}, indent=2))


if __name__ == "__main__":
    main()
