#!/usr/bin/env python3
"""Make auditable 24 kHz speech/text pairs from locally generated Whisper JSON.

This is automatic filtering, not a claim of human transcript verification.
Source recordings are never modified. Validation uses held-out time blocks.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy.signal import resample_poly


def main(argv=None):
    p = argparse.ArgumentParser()
    p.add_argument("root", type=Path)
    args = p.parse_args(argv)
    root = args.root.resolve()
    out = root / "corpus"
    (out / "audio").mkdir(parents=True, exist_ok=True)
    rows, rejected, sources = [], [], []
    for transcript in sorted((root / "transcripts").glob("*/combined.json")):
        data = json.loads(transcript.read_text())
        source = Path(data["source"])
        info = sf.info(source)
        sources.append({k: data[k] for k in ("source", "sha256", "seconds", "sample_rate")})
        words = []
        for seg in data["segments"]:
            for w in seg.get("words", []):
                words.append({**w, "logprob": seg.get("avg_logprob", -99),
                              "no_speech": seg.get("no_speech_prob", 1)})
        groups, group = [], []
        for w in words:
            if group and (w["end"] - group[0]["start"] > 11.5 or w["start"] - group[-1]["end"] > 1.1):
                groups.append(group)
                group = []
            group.append(w)
            if w["end"] - group[0]["start"] >= 4 and re.search(r"[.!?][\"’']?$", w["word"]):
                groups.append(group)
                group = []
        if group:
            groups.append(group)
        with sf.SoundFile(source) as f:
            for group in groups:
                start = max(0., group[0]["start"] - .12)
                end = min(data["seconds"], group[-1]["end"] + .18)
                text = "".join(w["word"] for w in group).strip()
                corrections = []
                if "readiong 1221_data" in str(source) and re.search(r"\bKrellius\b", text):
                    text = re.sub(r"\bKrellius\b", "Crellius", text)
                    corrections.append("Author spelling checked against supplied Crellius PDF")
                duration = end - start
                reason = None
                if not 2.0 <= duration <= 12.0 or len(text.split()) < 4:
                    reason = "length"
                elif min(w["logprob"] for w in group) < -.65 or max(w["no_speech"] for w in group) > .3:
                    reason = "asr_segment_confidence"
                elif np.mean([w["probability"] for w in group]) < .90 or min(w["probability"] for w in group) < .15:
                    reason = "asr_word_confidence"
                elif len(re.findall(r"[A-Za-z]", text)) < .65 * len(text):
                    reason = "non_speech_text"
                # Reserve the end of each recording; a 2-second buffer prevents
                # examples adjacent to the split from sharing samples.
                boundary = data["seconds"] * .9
                split = "validation" if start >= boundary + 2 else "train"
                if start < boundary + 2 and end > boundary - 2:
                    reason = "split_boundary_buffer"
                item_id = hashlib.sha256(f"{data['sha256']}:{start:.4f}:{end:.4f}".encode()).hexdigest()[:20]
                row = {"id": item_id, "text": text, "source": str(source),
                       "source_sha256": data["sha256"], "start": start, "end": end,
                       "seconds": duration, "split": split,
                       "mean_word_confidence": float(np.mean([w["probability"] for w in group])),
                       "text_corrections": corrections,
                       "transcript_status": "automatically_transcribed_and_filtered"}
                if reason:
                    rejected.append({**row, "reason": reason})
                    continue
                f.seek(round(start * info.samplerate))
                wave = f.read(round(duration * info.samplerate), dtype="float32", always_2d=True).mean(axis=1)
                peak = float(np.max(np.abs(wave)))
                clipped = float(np.mean(np.abs(wave) >= .999))
                rms = float(np.sqrt(np.mean(wave ** 2)))
                if clipped > .0005 or rms < .003:
                    rejected.append({**row, "reason": "clipping_or_near_silence", "peak": peak, "rms": rms})
                    continue
                from math import gcd
                divisor = gcd(info.samplerate, 24000)
                wave = resample_poly(wave, 24000 // divisor, info.samplerate // divisor).astype(np.float32)
                # Uniform peak headroom only; never alter pitch or timing.
                gain = min(3., .89 / max(peak, 1e-7))
                wave *= gain
                target = out / "audio" / f"{item_id}.wav"
                sf.write(target, wave, 24000, subtype="PCM_16")
                rows.append({**row, "audio": str(target), "gain": gain, "peak": peak, "rms": rms})
    # A repeated transcript must not occur on both sides of the split.
    validation_text = {re.sub(r"\W+", " ", r["text"]).lower().strip() for r in rows if r["split"] == "validation"}
    def fivegrams(text):
        tokens = re.findall(r"[a-z]+", text.lower())
        return {tuple(tokens[i:i+5]) for i in range(len(tokens)-4)}
    validation_grams = set().union(*(fivegrams(r["text"]) for r in rows if r["split"] == "validation"))
    clean = []
    for row in rows:
        if row["split"] == "train" and re.sub(r"\W+", " ", row["text"]).lower().strip() in validation_text:
            rejected.append({**row, "reason": "duplicate_validation_text"})
        elif row["split"] == "train" and len(fivegrams(row["text"])) >= 4 and len(fivegrams(row["text"]) & validation_grams) / len(fivegrams(row["text"])) > .5:
            rejected.append({**row, "reason": "overlapping_validation_passage"})
        else:
            clean.append(row)
    rows = clean
    for split in ("train", "validation"):
        (out / f"{split}.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows if r["split"] == split))
    (out / "rejected.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rejected))
    report = {"sources": sources, "raw_minutes": sum(s["seconds"] for s in sources) / 60,
              "kept_minutes": sum(r["seconds"] for r in rows) / 60,
              "counts": {s: sum(r["split"] == s for r in rows) for s in ("train", "validation")},
              "rejected_examples": len(rejected), "transcripts_human_verified": False}
    (out / "report.json").write_text(json.dumps(report, indent=2))
    print(json.dumps({k: v for k, v in report.items() if k != "sources"}, indent=2), flush=True)


if __name__ == "__main__":
    main()
