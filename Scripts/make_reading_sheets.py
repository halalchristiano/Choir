#!/usr/bin/env python3
"""Builds numbered reading sheets from the World English Bible.

The WEB is dedicated to the public domain, which is the only reason it is
usable here: CHOIR's runtime is MIT and its voice packs are commercial, so
training material has to be clean for commercial redistribution (PKG-005).
Every mainstream modern translation -- NIV, ESV, NASB, NLT, CSB -- is
copyrighted and licensed in ways that forbid exactly this.

Selection is not the whole Bible. Genealogies and legal lists are the worst
possible TTS training material: long runs of rare proper nouns, no prosodic
variety, and a reader's attention collapses after ten minutes of them. The
Gospels, Acts, Psalms and Proverbs give narrative, dialogue, question forms and
poetic rhythm, which is what the prosody model has to learn.

Usage:
    python3 Scripts/make_reading_sheets.py path/to/web.txt [outdir] [--books "1 Corinthians,2 Corinthians"]
"""
import os
import re
import sys

# Books chosen for prosodic variety, in reading order.
BOOKS = [
    "Mark",         # fast narrative, lots of dialogue
    "John",         # discourse, long sentences, repetition
    "Luke",         # narrative and parable
    "Acts",         # narrative, speeches, place names
    "Proverbs",     # short, self-contained, punchy
    "Psalms",       # poetic rhythm and parallelism
    "Matthew",      # teaching discourse
]

MIN_WORDS = 5
MAX_WORDS = 25
TARGET_SESSION_MINUTES = 30      # beyond this the voice audibly tires
WORDS_PER_MINUTE = 150           # unhurried reading aloud
PAUSE_SECONDS = 1.0              # the gap between lines, used for splitting


def estimate_minutes(lines):
    """Reading time from actual word counts.

    A flat seconds-per-line constant is wrong here: these verses average about
    17 words against the 8-word sentences of the coverage script, so a constant
    calibrated on one badly underestimates the other. Getting this wrong means
    a reader sits down for half an hour and is still going an hour later, which
    is precisely how a session ends up with a tired voice in it.
    """
    words = sum(len(line.split()) for line in lines)
    return words / WORDS_PER_MINUTE + len(lines) * PAUSE_SECONDS / 60


def load(path):
    """Yields (book, chapter, verse, text) from the tab-separated WEB dump."""
    with open(path, encoding="utf-8-sig") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) != 2:
                continue
            ref, text = parts
            match = re.match(r"^(.+?)\s+(\d+):(\d+)$", ref)
            if not match:
                continue
            yield match.group(1), int(match.group(2)), int(match.group(3)), text


def clean(text):
    """Strips editorial marks the reader should not voice."""
    text = re.sub(r"\{[^}]*\}", "", text)      # translator's supplied words
    text = re.sub(r"\[[^\]]*\]", "", text)     # bracketed notes
    text = re.sub(r"[“”]", '"', text)
    text = re.sub(r"[‘’]", "'", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def usable(text):
    if not text or text[0].islower():
        return False
    words = text.split()
    if not (MIN_WORDS <= len(words) <= MAX_WORDS):
        return False
    # A verse that is mostly proper nouns is a genealogy fragment.
    capitals = sum(1 for w in words[1:] if w[:1].isupper())
    if capitals > len(words) * 0.4:
        return False
    # Yahweh appears constantly and is not how most readers say it aloud;
    # leaving it in would teach one pronunciation thousands of times.
    if "Yahweh" in text:
        return False
    return True


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    global BOOKS
    args = sys.argv[1:]
    if "--books" in args:
        index = args.index("--books")
        BOOKS = [b.strip() for b in args[index + 1].split(",") if b.strip()]
        del args[index:index + 2]
    source = args[0]
    outdir = args[1] if len(args) > 1 else "recordings/scripts"
    os.makedirs(outdir, exist_ok=True)

    by_book = {}
    for book, chapter, verse, text in load(source):
        if book not in BOOKS:
            continue
        text = clean(text)
        if usable(text):
            by_book.setdefault(book, []).append(text)

    lines = []
    for book in BOOKS:
        lines.extend(by_book.get(book, []))

    # Deduplicate: repeated formulae would over-train one phrase.
    seen, unique = set(), []
    for text in lines:
        key = text.lower()
        if key in seen:
            continue
        seen.add(key)
        unique.append(text)

    # Fill each session up to the time budget rather than to a line count.
    sessions, current = [], []
    for text in unique:
        current.append(text)
        if estimate_minutes(current) >= TARGET_SESSION_MINUTES:
            sessions.append(current)
            current = []
    if current:
        sessions.append(current)

    written = []
    for index, session in enumerate(sessions, 1):
        minutes = estimate_minutes(session)
        path = os.path.join(outdir, f"session_{index:02d}.txt")
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(f"CHOIR reading sheet - session {index}\n")
            handle.write(f"{len(session)} lines, about {minutes:.0f} minutes\n")
            handle.write("\n")
            handle.write("Same mic, same room, same gain, same distance as every\n")
            handle.write("other session. One continuous recording. Pause about one\n")
            handle.write("second between lines. If you fluff a line, pause and say\n")
            handle.write("the whole line again - do not stop recording.\n")
            handle.write("\n")
            handle.write("Text: World English Bible (public domain).\n")
            handle.write("=" * 62 + "\n\n")
            for number, text in enumerate(session, 1):
                handle.write(f"{number:>4}.  {text}\n\n")
        written.append((path, len(session), minutes))

    total_minutes = sum(m for _, _, m in written)
    print(f"{len(unique):,} usable lines from {len(BOOKS)} books")
    print(f"{len(written)} sessions, {total_minutes/60:.1f} hours total\n")
    for path, count, minutes in written:
        print(f"  {path}  {count} lines  ~{minutes:.0f} min")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
