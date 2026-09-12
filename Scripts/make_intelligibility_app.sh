#!/bin/bash
#
# Builds a minimal macOS app bundle around choir-benchmark so the QUA-004
# intelligibility harness can request speech-recognition authorization.
#
# Speech authorization requires NSSpeechRecognitionUsageDescription in an
# Info.plist. A SwiftPM executable has no Info.plist and cannot carry that key,
# and asking for authorization without it is a TCC violation that terminates
# the process. Wrapping the same binary in a bundle is the smallest thing that
# makes the measurement possible; nothing about the engine changes.
#
# Usage:
#   Scripts/make_intelligibility_app.sh [output-dir]
#   <output-dir>/ChoirIntelligibility.app/Contents/MacOS/choir-benchmark \
#       --formant --intelligibility --voice orion
#
# The first run raises the system speech-recognition prompt. Approving it is a
# human action and cannot be scripted.

set -euo pipefail

OUT_DIR="${1:-build}"
APP="$OUT_DIR/ChoirIntelligibility.app"
BUNDLE_ID="${CHOIR_BUNDLE_ID:-com.choir.qua004}"
BINARY=".build/release/choir-benchmark"

if [ ! -x "$BINARY" ]; then
    echo "error: $BINARY not found. Run: swift build -c release" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# The library's resource bundle sits next to the executable in .build; it has to
# travel with it or the lexicon will not load. It goes in Contents/Resources,
# not next to the executable: codesign rejects a nested bundle inside MacOS/
# ("bundle format unrecognized"), which leaves the signature unable to bind the
# Info.plist, which is the one thing this wrapper exists to provide.
mkdir -p "$APP/Contents/Resources"
for resource in .build/release/*.bundle; do
    [ -e "$resource" ] && cp -R "$resource" "$APP/Contents/Resources/"
done

cp "$BINARY" "$APP/Contents/MacOS/choir-benchmark"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>choir-benchmark</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>ChoirIntelligibility</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <!-- Deliberately no LSBackgroundOnly and no LSUIElement. An app that
         declares itself background-only or agent-only cannot reliably present
         UI, and that includes the TCC authorization prompt, which is the one
         thing this bundle exists to obtain. -->
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>CHOIR transcribes its own synthesized speech to measure intelligibility (SRS QUA-004). No audio leaves this machine: recognition is forced on-device.</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 \
    || echo "warning: ad-hoc codesign failed; authorization may not persist" >&2

echo "Built $APP"
echo "Run: $APP/Contents/MacOS/choir-benchmark --formant --intelligibility --voice orion"
