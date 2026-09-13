"""Tests for the recording ingest pipeline.

Everything here uses synthetic audio built in the test, so it runs in CI with
no recordings present. Each test pins down a failure that was either hit on
real sessions or would be invisible until a trained voice sounded wrong.
"""
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
import unittest

import align_session
import prepare_dataset
import split_session

RATE = 48000
BITS = 24
HERE = os.path.dirname(os.path.abspath(__file__))


def pcm24(samples):
    out = bytearray()
    for value in samples:
        value = max(-(1 << 23), min((1 << 23) - 1, int(value)))
        out += (value & 0xFFFFFF).to_bytes(3, "little")
    return bytes(out)


def tone(seconds, amplitude=0.3, frequency=220.0):
    full = (1 << 23) - 1
    count = int(seconds * RATE)
    return [amplitude * full * math.sin(2 * math.pi * frequency * i / RATE)
            for i in range(count)]


def room(seconds, level=12, seed=1):
    """Low-level noise rather than digital silence.

    A real room is never zero, and the splitter estimates its threshold from
    the quiet frames, so a test built on exact zeros would not exercise it.
    """
    rng = random.Random(seed)
    return [rng.uniform(-level, level) for _ in range(int(seconds * RATE))]


def write(path, samples):
    split_session.write_wav(path, pcm24(samples), RATE, BITS)


class SplitterTests(unittest.TestCase):
    def test_finds_each_utterance_between_silences(self):
        audio = room(1.0)
        for index in range(4):
            audio += tone(0.8, frequency=200 + 40 * index) + room(1.0, seed=index + 2)
        pcm = pcm24(audio)

        segments, noise, _ = split_session.find_utterances(pcm, RATE, BITS)

        self.assertEqual(len(segments), 4)
        self.assertLess(noise, -60)
        for start, end in segments:
            self.assertGreater((end - start) / RATE, 0.8,
                               "padding must keep the whole utterance")

    def test_a_short_pause_inside_a_line_is_not_a_cut(self):
        # 0.15 s is a breath inside a sentence, well under the 0.35 s gap.
        audio = room(1.0) + tone(0.6) + room(0.15) + tone(0.6) + room(1.0)
        segments, _, _ = split_session.find_utterances(pcm24(audio), RATE, BITS)
        self.assertEqual(len(segments), 1)

    def test_clicks_are_not_utterances(self):
        audio = room(1.0) + tone(0.05) + room(1.0) + tone(0.8) + room(1.0)
        segments, _, _ = split_session.find_utterances(pcm24(audio), RATE, BITS)
        self.assertEqual(len(segments), 1)

    def test_digital_silence_is_refused(self):
        with self.assertRaises(SystemExit):
            split_session.find_utterances(bytes(3 * RATE), RATE, BITS)

    def test_wav_round_trip_is_bit_identical(self):
        pcm = pcm24(tone(0.2) + room(0.2))
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "a.wav")
            split_session.write_wav(path, pcm, RATE, BITS)
            data, rate, channels, bits = split_session.read_wav(path)
        self.assertEqual((rate, channels, bits), (RATE, 1, BITS))
        self.assertEqual(data, pcm)


class AlignerTests(unittest.TestCase):
    SHEET = [
        "The polished birch bridge crossed a shallow stream.",
        "Odd thoughts caught her at the office door.",
        "That cat sat on a flat black mat.",
    ]

    def run_align(self, transcripts):
        rows = [(f"clip_{i:04d}", text) for i, text in enumerate(transcripts)]
        return align_session.align(rows, self.SHEET)

    def test_a_line_read_across_a_pause_is_merged(self):
        # The exact failure from the first real session: one sentence, two clips.
        result = self.run_align([
            "the polished birch bridge",
            "crossed a shallow stream",
            "odd thoughts caught her at the office door",
            "that cat sat on a flat black mat",
        ])
        matched = {line: clips for line, clips, _ in result if line is not None}
        self.assertEqual(matched[0], [0, 1])
        self.assertEqual(matched[1], [2])
        self.assertEqual(matched[2], [3])

    def test_a_retake_does_not_shift_later_lines(self):
        result = self.run_align([
            "the polished birch bridge crossed a shallow stream",
            "odd thoughts caught",
            "odd thoughts caught her at the office door",
            "that cat sat on a flat black mat",
        ])
        matched = {line: clips for line, clips, _ in result if line is not None}
        self.assertEqual(matched[2], [3], "the final line must stay on the final clip")
        self.assertIn(2, matched[1], "the complete take should win the line")

    def test_an_unread_line_is_skipped_not_forced(self):
        result = self.run_align([
            "the polished birch bridge crossed a shallow stream",
            "that cat sat on a flat black mat",
        ])
        matched = {line: clips for line, clips, _ in result if line is not None}
        self.assertEqual(matched[0], [0])
        self.assertEqual(matched[2], [1])
        self.assertNotIn(1, matched)

    def test_similarity_is_f1_not_containment(self):
        reference = align_session.normalize("the cat")
        long_hypothesis = align_session.normalize("the cat sat on the mat by the door")
        self.assertLess(align_session.similarity(long_hypothesis, reference), 0.5)
        self.assertEqual(align_session.similarity(reference, reference), 1.0)

    def test_join_preserves_every_sample(self):
        with tempfile.TemporaryDirectory() as tmp:
            first, second = tone(0.3), tone(0.4, frequency=330)
            a, b = os.path.join(tmp, "a.wav"), os.path.join(tmp, "b.wav")
            write(a, first)
            write(b, second)
            joined = os.path.join(tmp, "joined.wav")
            align_session.join_wavs([a, b], joined)
            data, _, _, _ = split_session.read_wav(joined)
        self.assertEqual(data, pcm24(first) + pcm24(second))


class ManifestFromTranscriptsTests(unittest.TestCase):
    def test_drops_empty_and_fragmentary_transcripts(self):
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, "wav"))
            for name in ("c1", "c2", "c3", "c4"):
                write(os.path.join(tmp, "wav", name + ".wav"), tone(1.0))
            with open(os.path.join(tmp, "transcripts.tsv"), "w") as handle:
                handle.write("c1\tthree whole words\n")
                handle.write("c2\t\n")
                handle.write("c3\ttoo short\n")
                handle.write("c4\ta pipe | in the text\n")

            subprocess.run(
                [sys.executable, os.path.join(HERE, "manifest_from_transcripts.py"), tmp],
                check=True, capture_output=True)

            lines = open(os.path.join(tmp, "metadata.csv")).read().splitlines()

        names = [line.split("|")[0] for line in lines]
        self.assertEqual(names, ["c1", "c4"])
        # A pipe inside a transcript would shift every later manifest field.
        self.assertEqual(len(lines[1].split("|")), 3)


class DatasetTests(unittest.TestCase):
    def make_session(self, parent, name, speaker, clips=3, seconds=1.0, amplitude=0.3):
        root = os.path.join(parent, name)
        os.makedirs(os.path.join(root, "wav"))
        with open(os.path.join(root, "metadata.csv"), "w") as handle:
            for index in range(clips):
                clip = f"clip_{index:04d}"
                write(os.path.join(root, "wav", clip + ".wav"),
                      room(0.1) + tone(seconds, amplitude) + room(0.1))
                handle.write(f"{clip}|a line of text|a line of text\n")
        if speaker is not None:
            with open(os.path.join(root, "SPEAKER"), "w") as handle:
                handle.write(speaker + "\n")
        return root

    def test_two_speakers_are_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = self.make_session(tmp, "one", "evan")
            b = self.make_session(tmp, "two", "kiana")
            with self.assertRaises(ValueError):
                prepare_dataset.check_speakers([a, b])
            self.assertEqual(prepare_dataset.main([a, b]), 2)

    def test_an_unlabelled_session_is_refused_unless_asserted(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.make_session(tmp, "one", None)
            with self.assertRaises(ValueError):
                prepare_dataset.check_speakers([root])
            self.assertEqual(prepare_dataset.check_speakers([root], asserted="evan"), "evan")

    def test_sessions_with_matching_names_do_not_collide(self):
        with tempfile.TemporaryDirectory() as tmp:
            a = self.make_session(tmp, "esv_01", "evan", clips=2)
            b = self.make_session(tmp, "web_01", "evan", clips=2)
            out = os.path.join(tmp, "dataset")
            self.assertEqual(prepare_dataset.main([a, b, "--out", out]), 0)
            files = sorted(os.listdir(os.path.join(out, "wavs")))
            speaker = open(os.path.join(out, "SPEAKER")).read().strip()
        # Both sessions contain clip_0000 and clip_0001; all four must survive.
        self.assertEqual(len(files), 4)
        self.assertEqual(speaker, "evan")

    def test_clipped_and_quiet_takes_are_excluded(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.make_session(tmp, "s", "evan", clips=1)
            write(os.path.join(root, "wav", "clip_0000.wav"), tone(1.0, amplitude=1.0))
            usable, problems, _, _ = prepare_dataset.validate_session(root)
        self.assertEqual(usable, [])
        self.assertTrue(any("clipped" in p for p in problems))

    def test_peak_matches_the_signal(self):
        peak = prepare_dataset.peak_dbfs(pcm24(tone(0.1, amplitude=0.5)), BITS)
        self.assertAlmostEqual(peak, 20 * math.log10(0.5), delta=0.1)


if __name__ == "__main__":
    unittest.main()
