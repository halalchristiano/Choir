#!/bin/bash
#
# Turns one recorded session into validated training data, in one command.
#
# Processing Evan's first session by hand took seven separate commands --
# split, build the app bundle, register it, launch it, wait blind for twenty
# minutes, build the manifest, validate -- and every one of them is a place to
# get a path or a flag wrong on the session after. This runs the same steps in
# order and stops at the first failure.
#
# Usage:
#   Scripts/ingest_session.sh SPEAKER SESSION path/to/recording.wav [reading-sheet.txt]
#
# Example:
#   Scripts/ingest_session.sh evan web_01 ~/Downloads/evan_corinthians_01.wav \
#       recordings/scripts/corinthians/session_01.txt
#
# Without a reading sheet, the recognizer's transcripts become the text. With
# one, transcripts are only used to align each clip to its sheet line, and the
# sheet text is what goes into the manifest.
#
# Output lands in recordings/SPEAKER/SESSION/, which is git-ignored. Only counts
# are printed: transcripts can reproduce copyrighted text that was read aloud.

set -euo pipefail

if [ $# -lt 3 ]; then
    sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
fi

SPEAKER="$1"
SESSION="$2"
WAV="$3"
SHEET="${4:--}"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
DIR="recordings/$SPEAKER/$SESSION"
APP="$ROOT/.build/ChoirIntelligibility.app"
BINARY=".build/release/choir-benchmark"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nerror: %s\n' "$*" >&2; exit 1; }

case "$SPEAKER$SESSION" in
    *[!A-Za-z0-9_-]*) fail "speaker and session names may use letters, digits, - and _ only" ;;
esac
[ -f "$WAV" ] || fail "no recording at $WAV"
[ "$SHEET" = "-" ] || [ -f "$SHEET" ] || fail "no reading sheet at $SHEET"
# Never overwrite a session: re-running on the wrong WAV would silently replace
# data that may have taken an hour to record.
[ ! -e "$DIR/wav" ] || fail "$DIR already exists; choose a new session name or remove it"

step "1/5  Splitting $(basename "$WAV")"
# The splitter is not given the sheet. Pairing clips to lines by position is
# wrong as soon as the reader pauses mid-sentence, and step 4 pairs them by
# transcript instead; running both printed a count-mismatch warning that the
# very next step resolved.
python3 Scripts/split_session.py "$WAV" - "$DIR" | grep -E "min,|noise floor|utterances detected" || true
printf '%s\n' "$SPEAKER" > "$DIR/SPEAKER"

step "2/5  Preparing the transcription app"
if [ ! -x "$BINARY" ]; then
    echo "release build not found; building (this can take several minutes)"
    swift build -c release >/dev/null
fi
Scripts/make_intelligibility_app.sh .build >/dev/null
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

step "3/5  Transcribing (through LaunchServices, so speech authorization applies)"
OUT="$ROOT/$DIR/transcripts.tsv"
rm -f "$OUT" "$OUT.progress"
open "$APP" --args --transcribe "$ROOT/$DIR/wav" --output "$OUT"

sleep 5
last=""
while [ ! -f "$OUT" ]; do
    if [ -f "$OUT.progress" ]; then
        now="$(cat "$OUT.progress")"
        [ "$now" != "$last" ] && printf '  %s clips\n' "$now" && last="$now"
    fi
    if ! pgrep -f "choir-benchmark --transcribe" >/dev/null; then
        sleep 3
        [ -f "$OUT" ] && break
        fail "transcription stopped without output. If this is the first run, macOS may be asking for speech recognition permission."
    fi
    sleep 10
done
rm -f "$OUT.progress"
echo "  done: $(wc -l < "$OUT" | tr -d ' ') transcripts"

step "4/5  Building the manifest"
if [ "$SHEET" = "-" ]; then
    python3 Scripts/manifest_from_transcripts.py "$DIR"
else
    python3 Scripts/align_session.py "$OUT" "$SHEET" \
        --manifest "$DIR/metadata.csv" --wav-dir "$DIR/wav" \
        | grep -vE "^\s+(heard|sheet):" || true
fi

step "5/5  Validating every session for $SPEAKER"
python3 Scripts/prepare_dataset.py recordings/"$SPEAKER"/*/
