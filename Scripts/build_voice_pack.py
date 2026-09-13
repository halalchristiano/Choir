#!/usr/bin/env python3
"""Builds a .choirvoice bundle from trained model files.

The engine refuses a pack whose manifest disagrees with its files, its engine,
or its consent rules, so writing a manifest by hand is how a pack gets refused.
This builds one the engine will accept:

- copies the model files into a freshly staged bundle, never over an existing
  one (MaintenanceManual section 9: stage to a fresh directory)
- hashes every file with SHA-256, streaming, however large it is
- reads the engine version, package version and phoneme inventory version
  from the Swift sources, so a pack cannot claim a version the code does not
  have
- enforces the same consent rule the loader does before writing anything: a
  real person needs a release reference, a signing date, permitted uses, and
  mandatory synthetic disclosure

The Swift loader remains the authority. After building, verify with:

    swift run choir-benchmark --verify-pack path/to/Name.choirvoice

Usage:
    python3 Scripts/build_voice_pack.py build/Evan.choirvoice \\
        --pack-id studio.bothmade.evan --pack-version 1.0.0 \\
        --voice choir.ya.male.orion --sample-rate 22050 \\
        --vocoder model/evan.mlmodelc.zip \\
        --speaker-name "Evan" --kind real-person \\
        --release-ref "Evan voice release, signed PDF" \\
        --signed-on 2026-09-20 --use "commercial CHOIR voice pack"
"""
import argparse
import datetime
import difflib
import hashlib
import json
import os
import re
import shutil
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PACK_EXTENSION = ".choirvoice"
MANIFEST = "manifest.json"
SCHEMA_VERSION = 1


def read_engine_constants(repo=REPO):
    """Versions as the Swift code defines them, not as someone remembers them."""
    choir = open(os.path.join(repo, "Sources/Choir/Choir.swift"), encoding="utf-8").read()
    inventory = open(os.path.join(
        repo, "Sources/Choir/LinguisticFrontend/PhonemeInventory.swift"), encoding="utf-8").read()

    package = re.search(r'static let version = "(\d+\.\d+\.\d+)"', choir)
    engine = re.search(r"static let engineVersion: UInt64 = (\d+)", choir)
    phonemes = re.search(r"static let version = (\d+)", inventory)
    if not (package and engine and phonemes):
        raise SystemExit("could not read version constants from the Swift sources")
    return package.group(1), int(engine.group(1)), int(phonemes.group(1))


def read_voice_ids(repo=REPO):
    """Every Voice identifier the engine knows, read from Voice.swift.

    The loader refuses a pack naming an unknown voice, but only after the
    model files have been copied and hashed; checking here turns a typo into a
    one-line refusal with a suggestion instead.
    """
    source = open(os.path.join(repo, "Sources/Choir/Core/Voice.swift"), encoding="utf-8").read()
    ids = re.findall(r'identifier: "(choir\.[^"]+)"', source)
    if not ids:
        raise SystemExit("could not read voice identifiers from Voice.swift")
    return ids


def sha256_file(path, chunk=1 << 20):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            block = handle.read(chunk)
            if not block:
                break
            digest.update(block)
    return digest.hexdigest()


def is_semver(text):
    return re.fullmatch(r"\d+\.\d+\.\d+", text or "") is not None


def validate_consent(args):
    """Mirrors VoicePack.validateSpeaker, so a refusal happens before copying."""
    if args.kind != "real-person":
        return None
    problems = []
    if not (args.release_ref or "").strip():
        problems.append("--release-ref is required for a real person")
    if not args.use or any(not u.strip() for u in args.use):
        problems.append("at least one --use is required for a real person")
    try:
        signed = datetime.date.fromisoformat(args.signed_on or "")
        if args.signed_on != signed.isoformat():
            raise ValueError
        if signed > datetime.date.today():
            problems.append("--signed-on is in the future; the release was not signed yet")
    except ValueError:
        problems.append("--signed-on must be a real date, yyyy-mm-dd")
    if problems:
        raise SystemExit("REFUSED: " + "; ".join(problems))
    return {
        "releaseReference": args.release_ref.strip(),
        "signedOn": args.signed_on,
        "permittedUses": [u.strip() for u in args.use],
        # A real person's voice can be made to say anything once trained.
        # The loader refuses a real-person pack that does not require a label,
        # so there is no flag to turn this off.
        "requiresSyntheticDisclosure": True,
    }


def build(args, repo=REPO):
    out = os.path.abspath(args.out)
    if not out.endswith(PACK_EXTENSION):
        raise SystemExit(f"REFUSED: the pack directory must end in {PACK_EXTENSION}")
    if os.path.exists(out):
        raise SystemExit(f"REFUSED: {out} already exists; packs are never built over an old one")
    if not re.fullmatch(r"[A-Za-z0-9._-]+", args.pack_id or ""):
        raise SystemExit("REFUSED: --pack-id may use letters, digits, '.', '_' and '-' only")
    if not is_semver(args.pack_version):
        raise SystemExit("REFUSED: --pack-version must be major.minor.patch")
    if args.sample_rate <= 0:
        raise SystemExit("REFUSED: --sample-rate must be positive")
    if not args.voice:
        raise SystemExit("REFUSED: at least one --voice is required")
    if len(set(args.voice)) != len(args.voice):
        raise SystemExit("REFUSED: a --voice is listed twice")
    known = read_voice_ids(repo)
    for voice in args.voice:
        if voice not in known:
            close = difflib.get_close_matches(voice, known, n=1, cutoff=0.6)
            hint = f"; did you mean {close[0]}?" if close else ""
            raise SystemExit(f"REFUSED: unknown voice {voice}{hint}")
    if not (args.speaker_name or "").strip():
        raise SystemExit("REFUSED: --speaker-name is required")

    consent = validate_consent(args)
    package, engine, phonemes = read_engine_constants(repo)

    inputs = [("vocoder", args.vocoder)]
    if args.acoustic:
        inputs.append(("acousticModel", args.acoustic))
    inputs.extend(("auxiliary", path) for path in (args.aux or []))

    names = set()
    for _, source in inputs:
        if not os.path.isfile(source):
            raise SystemExit(f"REFUSED: no file at {source}")
        name = os.path.basename(source)
        if name in names:
            raise SystemExit(f"REFUSED: two input files are both named {name}")
        names.add(name)

    staging = out + ".staging"
    if os.path.exists(staging):
        shutil.rmtree(staging)
    os.makedirs(os.path.join(staging, "models"))
    try:
        files = []
        for role, source in inputs:
            relative = "models/" + os.path.basename(source)
            destination = os.path.join(staging, relative)
            shutil.copy2(source, destination)
            source_digest = sha256_file(source)
            copied_digest = sha256_file(destination)
            if source_digest != copied_digest:
                raise SystemExit(f"REFUSED: {source} changed while it was being copied")
            files.append({"path": relative, "sha256": copied_digest, "role": role})

        speaker = {"kind": "realPerson" if args.kind == "real-person" else "designed",
                   "displayName": args.speaker_name.strip()}
        if consent is not None:
            speaker["consent"] = consent

        manifest = {
            "schemaVersion": SCHEMA_VERSION,
            "packID": args.pack_id,
            "packVersion": args.pack_version,
            "engineVersion": engine,
            "minimumPackageVersion": args.minimum_package_version or package,
            "sampleRate": args.sample_rate,
            "phonemeInventoryVersion": phonemes,
            "voiceIDs": args.voice,
            "files": files,
            "speaker": speaker,
        }
        with open(os.path.join(staging, MANIFEST), "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, indent=2, sort_keys=True)
            handle.write("\n")

        os.rename(staging, out)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    return out, manifest


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("out", help="the .choirvoice directory to create")
    parser.add_argument("--pack-id", required=True)
    parser.add_argument("--pack-version", required=True)
    parser.add_argument("--voice", action="append", required=True,
                        help="Voice identifier the pack renders; repeatable")
    parser.add_argument("--sample-rate", type=int, required=True)
    parser.add_argument("--vocoder", required=True)
    parser.add_argument("--acoustic")
    parser.add_argument("--aux", action="append")
    parser.add_argument("--speaker-name", required=True)
    parser.add_argument("--kind", choices=["designed", "real-person"], required=True)
    parser.add_argument("--release-ref")
    parser.add_argument("--signed-on")
    parser.add_argument("--use", action="append")
    parser.add_argument("--minimum-package-version")
    args = parser.parse_args(argv)

    out, manifest = build(args)
    print(f"built {out}")
    for entry in manifest["files"]:
        print(f"  {entry['role']:<14} {entry['path']}  {entry['sha256'][:12]}…")
    print(f"engine {manifest['engineVersion']}, phoneme inventory "
          f"{manifest['phonemeInventoryVersion']}, requires CHOIR "
          f"{manifest['minimumPackageVersion']}+")
    print(f"\nverify with: swift run choir-benchmark --verify-pack {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
