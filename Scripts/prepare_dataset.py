#!/usr/bin/env python3
"""Validates a recorded corpus and assembles it for training.

Runs between the ingest pipeline and the trainer. Every check here exists
because the failure it catches is either invisible or expensive later:

- A corpus that is too small trains to something that imitates rather than
  speaks, and you only learn that after the GPU time is spent.
- One file at a different sample rate is silently resampled by most recipes,
  and teaches the model a slightly different voice for those lines.
- A clipped take teaches the model to clip.
- An empty or mismatched transcript teaches a wrong mapping, and the damage is
  invisible until synthesis sounds subtly wrong on unrelated words.

Output is the LJSpeech layout, which every VITS-family recipe reads.

Usage:
    python3 Scripts/prepare_dataset.py recordings [--out dataset] [--min-minutes 60]
"""
import argparse
import math
import os
import struct
import sys
from collections import Counter

MIN_UTTERANCE = 0.4
MAX_UTTERANCE = 20.0
CLIP_DBFS = -0.5
QUIET_DBFS = -32.0


def read_wav(path):
    with open(path, "rb") as handle:
        raw = handle.read()
    if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise ValueError("not a RIFF/WAVE file")
    pos, fmt, data = 12, None, None
    while pos + 8 <= len(raw):
        cid = raw[pos:pos + 4]
        size = struct.unpack("<I", raw[pos + 4:pos + 8])[0]
        body = raw[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt = struct.unpack("<HHIIHH", body[:16])
        elif cid == b"data":
            data = body
        pos += 8 + size + (size & 1)
    if fmt is None or data is None:
        raise ValueError("missing fmt or data chunk")
    _, channels, rate, _, _, bits = fmt
    return data, rate, channels, bits


def peak_dbfs(pcm, bits):
    """Peak level without decoding every sample into a list."""
    step = bits // 8
    full = float(1 << (bits - 1))
    peak = 0
    for i in range(0, len(pcm) - step + 1, step):
        if bits == 16:
            value = int.from_bytes(pcm[i:i + 2], "little", signed=True)
        else:
            value = int.from_bytes(pcm[i:i + 3], "little", signed=True)
        if value < 0:
            value = -value
        if value > peak:
            peak = value
    return 20 * math.log10(peak / full) if peak else -999.0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", help="directory holding metadata.csv and wav/")
    parser.add_argument("--out", default=None, help="assemble a dataset here")
    parser.add_argument("--min-minutes", type=float, default=60.0)
    args = parser.parse_args()

    manifest_path = os.path.join(args.root, "metadata.csv")
    wav_dir = os.path.join(args.root, "wav")
    if not os.path.exists(manifest_path):
        raise SystemExit(f"no manifest at {manifest_path}")

    entries = []
    for line in open(manifest_path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("|")
        if len(parts) < 2:
            continue
        entries.append((parts[0], parts[1], parts[-1]))

    problems, rates, depths, durations = [], Counter(), Counter(), []
    usable = []

    for name, raw_text, norm_text in entries:
        path = os.path.join(wav_dir, name + ".wav")
        if not os.path.exists(path):
            problems.append(f"{name}: no audio file")
            continue
        try:
            pcm, rate, channels, bits = read_wav(path)
        except ValueError as error:
            problems.append(f"{name}: {error}")
            continue

        rates[rate] += 1
        depths[bits] += 1
        seconds = len(pcm) / (rate * channels * bits // 8)
        durations.append(seconds)

        ok = True
        if channels != 1:
            problems.append(f"{name}: {channels} channels, expected mono")
            ok = False
        if not norm_text.strip():
            problems.append(f"{name}: empty transcript")
            ok = False
        if seconds < MIN_UTTERANCE:
            problems.append(f"{name}: {seconds:.2f}s, too short to be speech")
            ok = False
        if seconds > MAX_UTTERANCE:
            problems.append(f"{name}: {seconds:.1f}s, probably two lines")
            ok = False

        peak = peak_dbfs(pcm, bits)
        if peak > CLIP_DBFS:
            problems.append(f"{name}: peaks {peak:+.1f} dBFS, clipped or near it")
            ok = False
        elif peak < QUIET_DBFS:
            problems.append(f"{name}: {peak:+.1f} dBFS, too quiet to use")
            ok = False

        if ok:
            usable.append((name, norm_text, path, seconds))

    total = sum(d for *_, d in usable) / 60
    print(f"{len(entries)} manifest entries, {len(usable)} usable")
    print(f"{total:.1f} minutes of usable speech\n")

    if len(rates) > 1:
        print(f"MIXED SAMPLE RATES: {dict(rates)}")
        print("  Every file must share one rate. Most recipes resample silently,")
        print("  which teaches the model a different voice for the odd files.\n")
    else:
        print(f"sample rate   {list(rates)[0] if rates else 'n/a'} Hz (consistent)")
    if len(depths) > 1:
        print(f"MIXED BIT DEPTHS: {dict(depths)}\n")
    else:
        print(f"bit depth     {list(depths)[0] if depths else 'n/a'}-bit (consistent)")

    if durations:
        ordered = sorted(durations)
        print(f"utterances    min {ordered[0]:.1f}s  "
              f"median {ordered[len(ordered)//2]:.1f}s  max {ordered[-1]:.1f}s")

    # Readiness is the number that decides whether to spend GPU time.
    print()
    if total >= args.min_minutes:
        print(f"READY: {total:.1f} min meets the {args.min_minutes:.0f} min minimum.")
    else:
        needed = args.min_minutes - total
        sessions = math.ceil(needed / 30)
        print(f"NOT READY: {total:.1f} min of {args.min_minutes:.0f} min.")
        print(f"  About {needed:.0f} more minutes, or {sessions} more "
              f"30-minute session{'s' if sessions != 1 else ''}.")
        print("  Training on this now produces a model that imitates a few")
        print("  sentences rather than one that speaks.")

    if problems:
        print(f"\n{len(problems)} problems:")
        for problem in problems[:20]:
            print(f"  {problem}")
        if len(problems) > 20:
            print(f"  ... and {len(problems)-20} more")

    if args.out:
        import shutil
        out_wav = os.path.join(args.out, "wavs")
        os.makedirs(out_wav, exist_ok=True)
        with open(os.path.join(args.out, "metadata.csv"), "w",
                  encoding="utf-8") as handle:
            for name, text, path, _ in usable:
                shutil.copy2(path, os.path.join(out_wav, name + ".wav"))
                handle.write(f"{name}|{text}|{text}\n")
        print(f"\nassembled {len(usable)} utterances into {args.out}/")
        print("LJSpeech layout: metadata.csv plus wavs/")

    return 0 if not problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
