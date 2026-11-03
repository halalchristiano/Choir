import json
import tempfile
import types
import unittest
import wave
from pathlib import Path
from unittest.mock import patch

import numpy as np

import verify_bible_audio as verifier


class BibleAudioWindowChecks(unittest.TestCase):
    def options(self, hints=None):
        return types.SimpleNamespace(books=None, chapter=None, recheck=['test-01-001'],
                                     limit=None, temperature=0., recognizer_id='test@fixture',
                                     name_context=None, split_at=[1.5], window_name_contexts=hints)

    def test_disjoint_windows_cover_all_audio_and_preserve_timestamp_offsets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / 'chapters/test-01/passages/001.wav'
            path.parent.mkdir(parents=True)
            pcm = (np.sin(np.arange(48000) * .1) * 5000).astype('<i2')
            with wave.open(str(path), 'wb') as writer:
                writer.setnchannels(1)
                writer.setsampwidth(2)
                writer.setframerate(16000)
                writer.writeframes(pcm.tobytes())
            path.with_suffix('.json').write_text('{}')
            source = dict(chapters=[dict(id='test-01', book='Test', chapter=1,
                                        chunks=[dict(index=1, text='Alpha Beta')])])
            calls = []

            def transcribe(audio, **kwargs):
                calls.append((audio.copy(), kwargs))
                token = ['Alpha', 'Beta'][len(calls) - 1]
                return dict(text=token, segments=[dict(words=[dict(word=token, start=.1, end=.2)])])

            args = self.options([['Alpha'], ['Beta']])
            with patch.object(verifier.mlx_whisper, 'transcribe', side_effect=transcribe), patch.object(verifier.mx, 'clear_cache'):
                verifier.scan(args, root, source, root / 'pinned-model')
            check = json.loads(path.with_suffix('.check.json').read_text())
            self.assertTrue(np.array_equal(np.concatenate([call[0] for call in calls]), pcm.astype(np.float32) / 32768))
            self.assertEqual([len(call[0]) for call in calls], [24000, 24000])
            self.assertEqual([call[1]['initial_prompt'] for call in calls], ['Alpha', 'Beta'])
            self.assertTrue(all(call[1]['condition_on_previous_text'] is False for call in calls))
            self.assertEqual(check['recognized'], 'Alpha Beta')
            self.assertEqual(check['recognition_window_boundaries'], [0., 1.5, 3.])
            self.assertEqual(check['recognition_window_spelling_hints'], [['Alpha'], ['Beta']])
            self.assertEqual(check['sha256'], verifier.audio_digest(path))
            self.assertTrue(check['automatic_exact_match'])
            self.assertAlmostEqual(check['word_times'][1]['start'], 1.6)
            self.assertAlmostEqual(check['word_times'][1]['end'], 1.7)

    def test_incomplete_or_sentence_shaped_hints_are_rejected(self):
        for hints in ([['Alpha']], [['Alpha'], ['the LORD spoke']],
                      [['Beta', 'Alpha'], []], [['Alpha', 'alpha'], []],
                      [['Name' + chr(65 + n) for n in range(13)], []]):
            with self.subTest(hints=hints), self.assertRaises(AssertionError):
                verifier.window_spelling_contexts(self.options(hints), 2)

    def test_window_hints_cannot_be_mixed_with_global_prompt_or_implicit_windows(self):
        args = self.options([['Alpha'], ['Beta']])
        args.name_context = 'Gamma'
        with self.assertRaises(AssertionError):
            verifier.window_spelling_contexts(args, 2)
        args.name_context = None
        args.split_at = None
        with self.assertRaises(AssertionError):
            verifier.window_spelling_contexts(args, 2)

    def test_existing_global_and_unprompted_recognition_are_unchanged(self):
        args = self.options()
        self.assertEqual(verifier.window_spelling_contexts(args, 2), [None, None])
        args.name_context = 'Alpha, Beta'
        self.assertEqual(verifier.window_spelling_contexts(args, 2), ['Alpha, Beta', 'Alpha, Beta'])


if __name__ == '__main__':
    unittest.main()
