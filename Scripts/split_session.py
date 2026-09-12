#!/usr/bin/env python3
"""Splits a recording session into single-utterance files and a manifest.

A session is one continuous take of a numbered reading sheet, with roughly a
second of silence between lines. This finds those gaps, cuts the audio at them,
and writes one file per utterance plus the pipe-separated manifest the training
step consumes.

Audio is sliced at byte offsets in the original file. Nothing is decoded,
resampled or re-encoded, so the 24-bit samples that come out are bit-identical
to the ones that went in. A "cleanup" pass here would be baked in permanently,
and CHOIR has its own mastering chain for that.

Quality control is the point as much as the splitting is. A take that clipped,
came out too quiet, or does not match the line it should be is worse than no
take at all: it teaches the model a wrong mapping, and the damage is invisible
until synthesis sounds subtly wrong.

Usage:
    python3 Scripts/split_session.py recordings/raw/session_01.wav \\
        recordings/scripts/session_01.txt [outdir]
"""
import math
import os
import re
import struct
import sys

SILENCE_SECONDS = 0.35      # gap that separates two utterances
PAD_SECONDS = 0.12          # kept either side of speech, so nothing is clipped
MIN_UTTERANCE = 0.35        # shorter than this is a breath or a click
MAX_UTTERANCE = 20.0        # longer than this is two lines run together
FRAME_SECONDS = 0.025


def read_wav(path):
    """Returns (header_bytes, pcm_bytes, sample_rate, channels, bit_depth)."""
    with open(path, "rb") as handle:
        raw = handle.read()
    if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise SystemExit(f"{path}: not a RIFF/WAVE file")

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
        raise SystemExit(f"{path}: missing fmt or data chunk")
    _, channels, rate, _, _, bits = fmt
    if channels != 1:
        raise SystemExit(f"{path}: expected mono, found {channels} channels")
    return data, rate, channels, bits


def samples(pcm, bits):
    """Signed integer samples, whatever the bit depth."""
    step = bits // 8
    if bits == 16:
        return list(struct.unpack(f"<{len(pcm)//2}h", pcm[:len(pcm)//2*2]))
    if bits == 24:
        out = []
        for i in range(0, len(pcm) - 2, 3):
            value = pcm[i] | (pcm[i + 1] << 8) | (pcm[i + 2] << 16)
            if value & 0x800000:
                value -= 0x1000000
            out.append(value)
        return out
    raise SystemExit(f"unsupported bit depth: {bits}")


def write_wav(path, pcm, rate, bits):
    byte_rate = rate * bits // 8
    header = b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, byte_rate,
                                    bits // 8, bits)
    header += b"data" + struct.pack("<I", len(pcm))
    with open(path, "wb") as handle:
        handle.write(header + pcm)


def read_sheet(path):
    """The numbered lines of a reading sheet, in order."""
    lines = []
    for line in open(path, encoding="utf-8"):
        match = re.match(r"^\s*(\d+)\.\s+(.*\S)\s*$", line)
        if match:
            lines.append(match.group(2))
    return lines


def find_utterances(data, rate, bits):
    """Segments of speech, as (start_sample, end_sample) pairs."""
    audio = samples(data, bits)
    full = float(1 << (bits - 1))
    win = int(rate * FRAME_SECONDS)

    energies = []
    for i in range(0, len(audio) - win, win):
        acc = 0
        for s in audio[i:i + win]:
            acc += s * s
        rms = math.sqrt(acc / win)
        energies.append(20 * math.log10(rms / full) if rms > 0 else -999)

    finite = sorted(e for e in energies if e > -999)
    if not finite:
        raise SystemExit("the file appears to be digital silence")
    noise = finite[len(finite) // 20]
    threshold = noise + 12

    voiced = [e > threshold for e in energies]
    gap_frames = int(SILENCE_SECONDS / FRAME_SECONDS)

    segments, start, run = [], None, 0
    for i, is_voiced in enumerate(voiced):
        if is_voiced:
            if start is None:
                start = i
            run = 0
        elif start is not None:
            run += 1
            if run >= gap_frames:
                segments.append((start, i - run))
                start = None
    if start is not None:
        segments.append((start, len(voiced)))

    pad = int(PAD_SECONDS / FRAME_SECONDS)
    out = []
    for a, b in segments:
        seconds = (b - a) * FRAME_SECONDS
        if seconds < MIN_UTTERANCE:
            continue
        a = max(0, a - pad)
        b = min(len(voiced), b + pad)
        out.append((a * win, b * win))
    return out, noise, audio, full


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    wav_path, sheet_path = sys.argv[1], sys.argv[2]
    outdir = sys.argv[3] if len(sys.argv) > 3 else "recordings"
    wav_dir = os.path.join(outdir, "wav")
    os.makedirs(wav_dir, exist_ok=True)

    data, rate, _, bits = read_wav(wav_path)
    step = bits // 8
    sheet = read_sheet(sheet_path)
    segments, noise, audio, full = find_utterances(data, rate, bits)

    print(f"{os.path.basename(wav_path)}: {len(data)/step/rate/60:.1f} min, "
          f"{rate} Hz, {bits}-bit")
    print(f"noise floor {noise:+.1f} dBFS")
    print(f"{len(segments)} utterances detected, sheet has {len(sheet)} lines\n")

    stem = os.path.splitext(os.path.basename(wav_path))[0]
    manifest, warnings = [], []

    for index, (a, b) in enumerate(segments):
        chunk = data[a * step:b * step]
        seconds = (b - a) / rate
        window = audio[a:b]
        peak = max(max(window), -min(window)) if window else 0
        peak_db = 20 * math.log10(peak / full) if peak else -999

        name = f"{stem}_{index+1:04d}"
        write_wav(os.path.join(wav_dir, name + ".wav"), chunk, rate, bits)

        text = sheet[index] if index < len(sheet) else ""
        manifest.append(f"{name}|{text}|{text}")

        if peak_db > -1.0:
            warnings.append(f"{name}: peaks at {peak_db:+.1f} dBFS, close to clipping")
        if peak_db < -30.0:
            warnings.append(f"{name}: only {peak_db:+.1f} dBFS, unusually quiet")
        if seconds > MAX_UTTERANCE:
            warnings.append(f"{name}: {seconds:.1f}s, probably two lines run together")
        if not text:
            warnings.append(f"{name}: no sheet line for this utterance")

    manifest_path = os.path.join(outdir, "metadata.csv")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(manifest) + "\n")

    print(f"wrote {len(segments)} files to {wav_dir}/")
    print(f"wrote {manifest_path}")

    if len(segments) != len(sheet):
        print(f"\nCOUNT MISMATCH: {len(segments)} utterances against "
              f"{len(sheet)} sheet lines.")
        print("Every line after the first extra or missing take is paired with")
        print("the wrong text. Re-takes and lines containing a full stop are")
        print("the usual causes. Do not train on this manifest until the counts")
        print("agree or the pairing has been checked.")

    if warnings:
        print(f"\n{len(warnings)} warnings:")
        for warning in warnings[:25]:
            print(f"  {warning}")
        if len(warnings) > 25:
            print(f"  ... and {len(warnings)-25} more")
    else:
        print("\nNo level or length warnings.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
