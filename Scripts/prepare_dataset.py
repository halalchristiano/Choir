#!/usr/bin/env python3
"""Validates recorded sessions and assembles them into one training corpus.

Runs between the ingest pipeline and the trainer. Every check here exists
because the failure it catches is either invisible or expensive later:

- A corpus that is too small trains to something that imitates rather than
  speaks, and you only learn that after the GPU time is spent.
- Two speakers in one corpus train a blurred average of both voices. Nothing
  errors; the result just sounds like nobody. Each session directory carries a
  SPEAKER file, and sessions from different speakers are refused.
- One file at a different sample rate is silently resampled by most recipes,
  and teaches the model a slightly different voice for those lines.
- A clipped take teaches the model to clip.
- An empty transcript teaches a wrong mapping, and the damage is invisible
  until synthesis sounds subtly wrong on unrelated words.

Output is the LJSpeech layout, which every VITS-family recipe reads. Utterance
names are prefixed with their session so two sessions cannot collide.

Usage:
    python3 Scripts/prepare_dataset.py recordings/evan/esv_01 \\
        recordings/evan/web_01 [--out dataset] [--min-minutes 60]
"""
import argparse
import audioop
import math
import os
import shutil
import struct
from collections import Counter

MIN_UTTERANCE = 0.4
MAX_UTTERANCE = 20.0
CLIP_DBFS = -0.5
QUIET_DBFS = -32.0
SPEAKER_FILE = "SPEAKER"


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
    """Peak level, computed in C rather than by looping over samples."""
    step = bits // 8
    usable = len(pcm) - len(pcm) % step
    if usable == 0:
        return -999.0
    peak = audioop.max(pcm[:usable], step)
    full = float(1 << (bits - 1))
    return 20 * math.log10(peak / full) if peak else -999.0


def read_speaker(root):
    path = os.path.join(root, SPEAKER_FILE)
    if not os.path.exists(path):
        return None
    return open(path, encoding="utf-8").read().strip() or None


def check_speakers(roots, asserted=None, allow_mixed=False):
    """Returns the single speaker for these sessions, or raises ValueError.

    A session without a SPEAKER file cannot be verified, so it is refused
    unless the caller asserts the speaker explicitly.
    """
    found = {}
    for root in roots:
        speaker = read_speaker(root) or asserted
        if speaker is None:
            raise ValueError(
                f"{root}: no {SPEAKER_FILE} file. Write the speaker's name into "
                f"{os.path.join(root, SPEAKER_FILE)}, or pass --speaker if you "
                "are certain every session is the same person.")
        found[root] = speaker

    speakers = set(found.values())
    if len(speakers) > 1 and not allow_mixed:
        listing = ", ".join(f"{os.path.basename(r)}={s}" for r, s in found.items())
        raise ValueError(
            f"sessions come from {len(speakers)} speakers ({listing}). A voice "
            "model trained on more than one person learns a blend of them. "
            "Assemble each speaker separately.")
    return next(iter(speakers)) if len(speakers) == 1 else "mixed"


def validate_session(root):
    """Checks every manifest entry in one session.

    Returns (usable, problems, rates, depths) where usable is a list of
    (session, name, text, path, seconds).
    """
    manifest_path = os.path.join(root, "metadata.csv")
    wav_dir = os.path.join(root, "wav")
    if not os.path.exists(manifest_path):
        return [], [f"{root}: no metadata.csv"], Counter(), Counter()

    session = os.path.basename(os.path.normpath(root))
    usable, problems = [], []
    rates, depths = Counter(), Counter()

    for line in open(manifest_path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line:
            continue
        parts = line.split("|")
        if len(parts) < 2:
            problems.append(f"{session}: malformed manifest line")
            continue
        name, text = parts[0], parts[-1]
        path = os.path.join(wav_dir, name + ".wav")
        label = f"{session}/{name}"

        if not os.path.exists(path):
            problems.append(f"{label}: no audio file")
            continue
        try:
            pcm, rate, channels, bits = read_wav(path)
        except ValueError as error:
            problems.append(f"{label}: {error}")
            continue

        rates[rate] += 1
        depths[bits] += 1
        seconds = len(pcm) / (rate * channels * bits // 8)

        reasons = []
        if channels != 1:
            reasons.append(f"{channels} channels, expected mono")
        if not text.strip():
            reasons.append("empty transcript")
        if seconds < MIN_UTTERANCE:
            reasons.append(f"{seconds:.2f}s, too short to be speech")
        if seconds > MAX_UTTERANCE:
            reasons.append(f"{seconds:.1f}s, probably two lines")
        peak = peak_dbfs(pcm, bits)
        if peak > CLIP_DBFS:
            reasons.append(f"peaks {peak:+.1f} dBFS, clipped or near it")
        elif peak < QUIET_DBFS:
            reasons.append(f"{peak:+.1f} dBFS, too quiet to use")

        if reasons:
            problems.extend(f"{label}: {reason}" for reason in reasons)
        else:
            usable.append((session, name, text, path, seconds))

    return usable, problems, rates, depths


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("roots", nargs="+",
                        help="session directories, each with metadata.csv and wav/")
    parser.add_argument("--out", default=None, help="assemble a dataset here")
    parser.add_argument("--min-minutes", type=float, default=60.0)
    parser.add_argument("--speaker", default=None,
                        help="assert the speaker for sessions without a SPEAKER file")
    parser.add_argument("--allow-mixed-speakers", action="store_true",
                        help="only for a deliberate multi-speaker model")
    args = parser.parse_args(argv)

    try:
        speaker = check_speakers(args.roots, args.speaker, args.allow_mixed_speakers)
    except ValueError as error:
        print(f"REFUSED: {error}")
        return 2

    usable, problems = [], []
    rates, depths = Counter(), Counter()
    per_session = []
    for root in args.roots:
        u, p, r, d = validate_session(root)
        usable.extend(u)
        problems.extend(p)
        rates.update(r)
        depths.update(d)
        per_session.append((os.path.basename(os.path.normpath(root)), len(u),
                            sum(x[4] for x in u) / 60))

    total = sum(x[4] for x in usable) / 60
    print(f"speaker       {speaker}")
    for session, count, minutes in per_session:
        print(f"  {session:<20} {count:>5} utterances  {minutes:5.1f} min")
    print(f"\n{len(usable)} usable utterances, {total:.1f} minutes of speech\n")

    if len(rates) > 1:
        print(f"MIXED SAMPLE RATES: {dict(rates)}")
        print("  Every file must share one rate. Most recipes resample silently,")
        print("  which teaches the model a different voice for the odd files.\n")
    elif rates:
        print(f"sample rate   {next(iter(rates))} Hz (consistent)")
    if len(depths) > 1:
        print(f"MIXED BIT DEPTHS: {dict(depths)}\n")
    elif depths:
        print(f"bit depth     {next(iter(depths))}-bit (consistent)")

    durations = sorted(x[4] for x in usable)
    if durations:
        print(f"utterances    min {durations[0]:.1f}s  "
              f"median {durations[len(durations)//2]:.1f}s  max {durations[-1]:.1f}s")

    print()
    if total >= args.min_minutes:
        print(f"READY: {total:.1f} min meets the {args.min_minutes:.0f} min minimum.")
    else:
        needed = args.min_minutes - total
        sessions = math.ceil(needed / 30)
        print(f"NOT READY: {total:.1f} min of {args.min_minutes:.0f} min.")
        print(f"  About {needed:.0f} more minutes, or {sessions} more "
              f"30-minute session{'s' if sessions != 1 else ''}.")

    if problems:
        print(f"\n{len(problems)} problems:")
        for problem in problems[:20]:
            print(f"  {problem}")
        if len(problems) > 20:
            print(f"  ... and {len(problems) - 20} more")

    if args.out:
        out_wav = os.path.join(args.out, "wavs")
        os.makedirs(out_wav, exist_ok=True)
        with open(os.path.join(args.out, "metadata.csv"), "w", encoding="utf-8") as handle:
            for session, name, text, path, _ in usable:
                # Prefixed so two sessions that both contain "clip_0001" cannot
                # silently overwrite each other in the assembled corpus.
                unique = f"{session}__{name}"
                shutil.copy2(path, os.path.join(out_wav, unique + ".wav"))
                handle.write(f"{unique}|{text}|{text}\n")
        with open(os.path.join(args.out, SPEAKER_FILE), "w", encoding="utf-8") as handle:
            handle.write(speaker + "\n")
        print(f"\nassembled {len(usable)} utterances into {args.out}/")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
