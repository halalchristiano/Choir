#!/usr/bin/env python3
"""Builds a training manifest from recognizer transcripts alone.

For sessions recorded without a reading sheet -- the reader chose their own
passages -- there is no text of record to align against, so the on-device
recognizer's transcript becomes the transcript. That is rougher than sheet
text: the recognizer mishears names, normalises numbers, and occasionally
returns nothing. So this is deliberately conservative about what it keeps.

Dropped:
- utterances the recognizer returned nothing for, which are breaths, clicks,
  asides, or speech it could not follow
- transcripts of one or two words, which on a phrase-length clip usually means
  the recognizer caught only part of what was said, and a transcript that
  covers half the audio teaches a wrong mapping

Transcripts may reproduce the text that was read. This script writes them only
to the local manifest, which is git-ignored, and prints counts, not content.

Usage:
    python3 Scripts/manifest_from_transcripts.py recordings/evan \\
        [--min-words 3]
"""
import argparse
import os


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("root", help="directory with wav/ and transcripts.tsv")
    parser.add_argument("--min-words", type=int, default=3)
    args = parser.parse_args()

    transcripts_path = os.path.join(args.root, "transcripts.tsv")
    wav_dir = os.path.join(args.root, "wav")

    kept, empty, short, missing = [], 0, 0, 0
    for line in open(transcripts_path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line:
            continue
        name, _, text = line.partition("\t")
        text = " ".join(text.split())
        if not os.path.exists(os.path.join(wav_dir, name + ".wav")):
            missing += 1
            continue
        if not text:
            empty += 1
            continue
        if len(text.split()) < args.min_words:
            short += 1
            continue
        # The manifest format is pipe-separated; a pipe in a transcript would
        # shift every later field.
        text = text.replace("|", " ")
        kept.append((name, text))

    manifest = os.path.join(args.root, "metadata.csv")
    with open(manifest, "w", encoding="utf-8") as handle:
        for name, text in kept:
            handle.write(f"{name}|{text}|{text}\n")

    total = len(kept) + empty + short + missing
    print(f"{total} transcripts")
    print(f"  kept                {len(kept)}")
    print(f"  empty (dropped)     {empty}")
    print(f"  under {args.min_words} words (dropped) {short}")
    if missing:
        print(f"  no audio (dropped)  {missing}")
    print(f"\nwrote {manifest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
