import json
import tempfile
import unittest
from pathlib import Path

import numpy as np

from assemble_bible_audio import prepare_passage, preserve_previous_assembly, sha


class PassageAssembly(unittest.TestCase):
    rate = 24000

    def test_voiced_boundaries_are_not_trimmed_or_faded(self):
        original = np.full(self.rate, .125, dtype=np.float32)
        result, start, end, leading, trailing = prepare_passage(original, self.rate)
        self.assertEqual((start, end, leading, trailing), (0, len(original), 0, 0))
        np.testing.assert_array_equal(result, original)

    def test_quiet_margins_are_trimmed_without_changing_speech(self):
        speech = np.full(self.rate, .125, dtype=np.float32)
        original = np.r_[np.zeros(12000, dtype=np.float32), speech, np.zeros(14400, dtype=np.float32)]
        result, start, end, leading, trailing = prepare_passage(original, self.rate)
        self.assertGreater(start, 0);self.assertLess(end, len(original))
        self.assertEqual((leading, trailing), (120, 120))
        np.testing.assert_array_equal(result[12000-start:36000-start], speech)

    def test_a_short_transient_in_a_low_rms_edge_is_preserved(self):
        original = np.zeros(self.rate*2+45, dtype=np.float32)
        original[self.rate//2:self.rate] = .125
        original[1] = .008
        original[-1] = .008
        result, start, end, leading, trailing = prepare_passage(original, self.rate)
        self.assertEqual((start, end, leading, trailing), (0, len(original), 0, 0))
        np.testing.assert_array_equal(result, original)

    def test_each_edge_is_handled_independently(self):
        original = np.r_[np.full(self.rate, .125, dtype=np.float32), np.zeros(self.rate, dtype=np.float32)]
        result, start, end, leading, trailing = prepare_passage(original, self.rate)
        self.assertEqual((start, leading, trailing), (0, 0, 120))
        np.testing.assert_array_equal(result[:self.rate], original[:self.rate])

    def test_pcm16_round_trip_keeps_every_unfaded_sample(self):
        pcm = np.tile(np.array([30000, -30000, 17001, -17001, 1, -1], dtype='<i2'), 4000)
        result, _, _, leading, trailing = prepare_passage(pcm.astype(np.float32)/32768, self.rate)
        self.assertEqual((leading,trailing),(0,0))
        np.testing.assert_array_equal(np.rint(result*32768).astype('<i2'), pcm)

    def test_invalid_and_silent_passages_are_rejected(self):
        for value in [0., float('nan')]:
            with self.assertRaises(AssertionError):
                prepare_passage(np.full(self.rate,value,dtype=np.float32),self.rate)

    def test_previous_assembly_is_retained_before_new_output(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory);audio=folder/'chapter.m4a';wav=audio.with_suffix('.wav')
            audio.write_bytes(b'old-encoded');wav.write_bytes(b'old-pcm')
            previous=dict(local_audio=str(audio));receipt=folder/'recording.json'
            receipt.write_text(json.dumps(previous));digest=sha(receipt)
            preserve_previous_assembly(folder,receipt,previous)
            audio.write_bytes(b'new-encoded');wav.write_bytes(b'new-pcm')
            history=folder/'assembly-history'/digest
            self.assertEqual((history/audio.name).read_bytes(),b'old-encoded')
            self.assertEqual((history/wav.name).read_bytes(),b'old-pcm')
            self.assertEqual(json.loads((history/'recording.json').read_text()),previous)


if __name__=='__main__':unittest.main()
