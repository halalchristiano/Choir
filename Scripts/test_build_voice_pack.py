"""Tests for the voice pack builder.

The Swift loader is the authority on what a pack must contain; these pin down
that the builder refuses the same things before copying anything, and writes
manifests the loader's rules would accept.
"""
import argparse
import datetime
import hashlib
import json
import os
import tempfile
import unittest

import build_voice_pack as builder

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def args(out, source, **overrides):
    values = dict(
        out=out, pack_id="studio.test.voice", pack_version="1.0.0",
        voice=["choir.ya.male.orion"], sample_rate=22050,
        vocoder=source, acoustic=None, aux=None,
        speaker_name="Test", kind="designed",
        release_ref=None, signed_on=None, use=None,
        minimum_package_version=None)
    values.update(overrides)
    return argparse.Namespace(**values)


class BuilderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.source = os.path.join(self.tmp.name, "vocoder.bin")
        with open(self.source, "wb") as handle:
            handle.write(os.urandom(70_000))

    def tearDown(self):
        self.tmp.cleanup()

    def out(self, name="Voice"):
        return os.path.join(self.tmp.name, name + ".choirvoice")

    def assertRefused(self, namespace, fragment):
        with self.assertRaises(SystemExit) as caught:
            builder.build(namespace)
        self.assertIn(fragment, str(caught.exception))
        self.assertFalse(os.path.exists(namespace.out), "a refused build must leave nothing behind")
        self.assertFalse(os.path.exists(namespace.out + ".staging"))

    def test_builds_a_manifest_matching_the_engine(self):
        out, manifest = builder.build(args(self.out(), self.source))
        package, engine, phonemes = builder.read_engine_constants()

        on_disk = json.load(open(os.path.join(out, "manifest.json")))
        self.assertEqual(on_disk, manifest)
        self.assertEqual(manifest["engineVersion"], engine)
        self.assertEqual(manifest["phonemeInventoryVersion"], phonemes)
        self.assertEqual(manifest["minimumPackageVersion"], package)

        entry = manifest["files"][0]
        self.assertEqual(entry["role"], "vocoder")
        copied = os.path.join(out, entry["path"])
        self.assertEqual(entry["sha256"], hashlib.sha256(open(copied, "rb").read()).hexdigest())
        self.assertNotIn("consent", manifest["speaker"])

    def test_version_constants_are_read_from_the_swift_sources(self):
        package, engine, phonemes = builder.read_engine_constants()
        choir = open(os.path.join(REPO, "Sources/Choir/Choir.swift")).read()
        self.assertIn(f'static let version = "{package}"', choir)
        self.assertIn(f"engineVersion: UInt64 = {engine}", choir)
        self.assertGreaterEqual(phonemes, 1)

    def test_knows_all_32_voices(self):
        self.assertEqual(len(builder.read_voice_ids()), 32)

    def test_a_real_person_gets_mandatory_disclosure(self):
        _, manifest = builder.build(args(
            self.out(), self.source, kind="real-person",
            release_ref="signed release", signed_on="2026-01-02", use=["commercial voice pack"]))
        consent = manifest["speaker"]["consent"]
        self.assertTrue(consent["requiresSyntheticDisclosure"])
        self.assertEqual(manifest["speaker"]["kind"], "realPerson")

    def test_a_real_person_without_a_release_is_refused(self):
        self.assertRefused(args(self.out(), self.source, kind="real-person"), "--release-ref")

    def test_an_incomplete_release_is_refused(self):
        base = dict(kind="real-person", release_ref="release", use=["commercial"])
        future = (datetime.date.today() + datetime.timedelta(days=30)).isoformat()
        self.assertRefused(args(self.out(), self.source, signed_on=future, **base), "in the future")
        self.assertRefused(args(self.out(), self.source, signed_on="2026-02-30", **base), "real date")
        self.assertRefused(
            args(self.out(), self.source, kind="real-person", release_ref="r",
                 signed_on="2026-01-02", use=[" "]), "--use")

    def test_an_unknown_voice_is_refused_with_a_suggestion(self):
        self.assertRefused(
            args(self.out(), self.source, voice=["choir.adult.male.orion"]),
            "did you mean choir.ya.male.orion")

    def test_never_builds_over_an_existing_pack(self):
        out = self.out()
        builder.build(args(out, self.source))
        with self.assertRaises(SystemExit) as caught:
            builder.build(args(out, self.source))
        self.assertIn("already exists", str(caught.exception))

    def test_malformed_fields_are_refused(self):
        self.assertRefused(args(self.out("a"), self.source, pack_version="1.0"), "major.minor.patch")
        self.assertRefused(args(self.out("b"), self.source, pack_id="has spaces"), "--pack-id")
        self.assertRefused(args(self.out("c"), self.source, sample_rate=0), "--sample-rate")
        self.assertRefused(
            args(self.out("d"), self.source, voice=["choir.ya.male.orion"] * 2), "listed twice")
        self.assertRefused(args(self.out("e"), os.path.join(self.tmp.name, "missing")), "no file")


if __name__ == "__main__":
    unittest.main()
