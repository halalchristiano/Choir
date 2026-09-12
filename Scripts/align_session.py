#!/usr/bin/env python3
"""Aligns split utterances to their reading-sheet lines using transcripts.

Splitting on silence does not produce one file per sheet line. A reader pauses
mid-sentence, and the gap is cut; a reader fluffs a line and says it again, and
there are two files for one line. Either way every later file is paired with
the wrong text if position is all you have, and a manifest that pairs audio
with the wrong words teaches the model a wrong mapping.

So each utterance is transcribed by the on-device recognizer, and the sequence
of transcripts is aligned against the sequence of sheet lines by dynamic
programming. A sheet line may consume up to MAX_MERGE consecutive utterances
(a sentence read across a pause) or none at all (a line that was skipped), and
the alignment maximising total word overlap wins.

The transcripts are only used to decide *which* line each file contains. The
text written to the manifest is always the sheet line, never the recognizer's
guess: the reader said the sheet, and the recognizer is the thing being checked
against, not the source of truth.

Usage:
    python3 Scripts/align_session.py transcripts.tsv sheet.txt \\
        [--manifest metadata.csv] [--min-score 0.45]
"""
import argparse
import re
import sys

MAX_MERGE = 3           # a line read across at most two internal pauses
SKIP_PENALTY = 0.35     # cost of leaving a sheet line unmatched


def normalize(text):
    return [w for w in re.sub(r"[^a-z0-9 ]", " ", text.lower()).split() if w]


def similarity(hypothesis, reference):
    """Word-overlap F1 between a transcript and a sheet line.

    F1 rather than raw overlap: a long transcript that happens to contain every
    word of a short line should not score as a perfect match.
    """
    if not hypothesis or not reference:
        return 0.0
    remaining = list(reference)
    hits = 0
    for word in hypothesis:
        if word in remaining:
            remaining.remove(word)
            hits += 1
    if hits == 0:
        return 0.0
    precision = hits / len(hypothesis)
    recall = hits / len(reference)
    return 2 * precision * recall / (precision + recall)


def read_transcripts(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        if not line.strip():
            continue
        parts = line.rstrip("\n").split("\t")
        rows.append((parts[0], parts[1] if len(parts) > 1 else ""))
    return rows


def read_sheet(path):
    lines = []
    for line in open(path, encoding="utf-8"):
        match = re.match(r"^\s*(\d+)\.\s+(.*\S)\s*$", line)
        if match:
            lines.append(match.group(2))
    return lines


def align(transcripts, sheet):
    """Best assignment of utterance runs to sheet lines.

    Returns a list of (sheet_index, [utterance_indices], score).
    """
    n, m = len(transcripts), len(sheet)
    hyp = [normalize(t) for _, t in transcripts]
    ref = [normalize(s) for s in sheet]

    NEG = float("-inf")
    # best[i][j] = best score having consumed i utterances and j sheet lines
    best = [[NEG] * (m + 1) for _ in range(n + 1)]
    back = [[None] * (m + 1) for _ in range(n + 1)]
    best[0][0] = 0.0

    for i in range(n + 1):
        for j in range(m + 1):
            if best[i][j] == NEG:
                continue
            # Skip a sheet line: it was never read.
            if j < m and best[i][j] - SKIP_PENALTY > best[i][j + 1]:
                best[i][j + 1] = best[i][j] - SKIP_PENALTY
                back[i][j + 1] = (i, j, 0)
            # Consume k utterances for sheet line j.
            if j < m:
                for k in range(1, MAX_MERGE + 1):
                    if i + k > n:
                        break
                    merged = []
                    for t in range(i, i + k):
                        merged.extend(hyp[t])
                    score = similarity(merged, ref[j])
                    if best[i][j] + score > best[i + k][j + 1]:
                        best[i + k][j + 1] = best[i][j] + score
                        back[i + k][j + 1] = (i, j, k)
            # Drop an utterance entirely: a re-take, cough or false start.
            if i < n and best[i][j] - SKIP_PENALTY > best[i + 1][j]:
                best[i + 1][j] = best[i][j] - SKIP_PENALTY
                back[i + 1][j] = (i, j, -1)

    path, i, j = [], n, m
    while (i, j) != (0, 0):
        step = back[i][j]
        if step is None:
            break
        pi, pj, k = step
        if k > 0:
            merged = []
            for t in range(pi, pi + k):
                merged.extend(hyp[t])
            path.append((pj, list(range(pi, pi + k)), similarity(merged, ref[pj])))
        elif k == -1:
            path.append((None, [pi], 0.0))
        i, j = pi, pj
    path.reverse()
    return path


def join_wavs(paths, destination):
    """Concatenates mono PCM WAVs that share a format.

    A line read across a pause arrives as two or three files, and a manifest
    entry naming only the first would train the model on half a sentence. The
    samples are copied through untouched: same rate, same bit depth, same
    bytes, with the inter-part silence left in because it is real speech
    rhythm, not an artefact.
    """
    import struct
    fmt, data = None, b""
    for path in paths:
        with open(path, "rb") as handle:
            raw = handle.read()
        pos = 12
        while pos + 8 <= len(raw):
            cid = raw[pos:pos + 4]
            size = struct.unpack("<I", raw[pos + 4:pos + 8])[0]
            body = raw[pos + 8:pos + 8 + size]
            if cid == b"fmt ":
                current = struct.unpack("<HHIIHH", body[:16])
                if fmt is None:
                    fmt = current
                elif fmt != current:
                    raise SystemExit(f"{path}: format differs from the first part")
            elif cid == b"data":
                data += body
            pos += 8 + size + (size & 1)

    _, channels, rate, _, _, bits = fmt
    byte_rate = rate * channels * bits // 8
    header = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, channels, rate,
                                    byte_rate, channels * bits // 8, bits)
    header += b"data" + struct.pack("<I", len(data))
    with open(destination, "wb") as handle:
        handle.write(header + data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("transcripts")
    parser.add_argument("sheet")
    parser.add_argument("--manifest", default=None)
    parser.add_argument("--min-score", type=float, default=0.45)
    parser.add_argument("--wav-dir", default=None,
                        help="directory of split WAVs; merged lines are joined "
                             "into one file per sheet line")
    parser.add_argument("--out-dir", default=None,
                        help="where joined WAVs are written")
    args = parser.parse_args()

    transcripts = read_transcripts(args.transcripts)
    sheet = read_sheet(args.sheet)
    result = align(transcripts, sheet)

    matched = [r for r in result if r[0] is not None and r[2] >= args.min_score]
    weak = [r for r in result if r[0] is not None and r[2] < args.min_score]
    dropped = [r for r in result if r[0] is None]
    merged = [r for r in matched if len(r[1]) > 1]
    used = {i for r in result if r[0] is not None for i in r[1]}
    unread = [j for j in range(len(sheet))
              if j not in {r[0] for r in result if r[0] is not None}]

    print(f"{len(transcripts)} utterances, {len(sheet)} sheet lines\n")
    print(f"  matched          {len(matched)}")
    print(f"  merged across a pause {len(merged)}")
    print(f"  weak match       {len(weak)}   (below {args.min_score})")
    print(f"  dropped          {len(dropped)}   (re-takes, false starts, noise)")
    print(f"  sheet lines unread {len(unread)}")

    if weak:
        print("\nWeak matches, check these by ear:")
        for j, idx, score in weak[:12]:
            ids = ", ".join(transcripts[i][0] for i in idx)
            print(f"  {score:.2f}  {ids}")
            print(f"        heard: {transcripts[idx[0]][1][:70]}")
            print(f"        sheet: {sheet[j][:70]}")

    joined = 0
    if args.manifest:
        import os
        out_dir = args.out_dir or args.wav_dir
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(args.manifest, "w", encoding="utf-8") as handle:
            for j, idx, score in matched:
                primary = transcripts[idx[0]][0]
                if len(idx) > 1 and args.wav_dir:
                    parts = [os.path.join(args.wav_dir, transcripts[i][0] + ".wav")
                             for i in idx]
                    name = f"{primary}_joined"
                    join_wavs(parts, os.path.join(out_dir, name + ".wav"))
                    primary = name
                    joined += 1
                # The sheet line is the transcript of record, not the ASR guess.
                handle.write(f"{primary}|{sheet[j]}|{sheet[j]}\n")
        print(f"\nwrote {len(matched)} entries to {args.manifest}")
        if joined:
            print(f"joined {joined} multi-part lines into single files")
        elif merged and not args.wav_dir:
            print("Pass --wav-dir to join the multi-part lines; without it the")
            print("manifest names only the first part of each.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
