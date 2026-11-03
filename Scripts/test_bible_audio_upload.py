import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from upload_bible_audio import jobs


class BibleAudioUploadChecks(unittest.TestCase):
    def fixture(self, root, count):
        # The uploader verifies immutable bytes; decoding is checked separately
        # by the production app repository before release.
        data = b'verified audio fixture'
        digest = hashlib.sha256(data).hexdigest()
        audio = root/'fixture.m4a'
        audio.write_bytes(data)
        entries = []
        for number in range(1, count+1):
            entry = dict(book='Fixture', chapter=number, audioPath=f'evan-bsb-v1/fixture-{number:02d}/{digest}.m4a',
                         byteCount=len(data), audioSHA256=digest)
            directory = root/'chapters'/f'fixture-{number:02d}'
            directory.mkdir(parents=True)
            (directory/'recording.json').write_text(json.dumps(dict(catalog_entry=entry, local_audio=str(audio))))
            entries.append(entry)
        (root/'catalog.json').write_text(json.dumps(dict(schemaVersion=1, voiceID='evan-bsb-v1', translation='BSB', chapters=entries)))
        (root/'publication-scope.json').write_text(json.dumps(dict(books=[dict(book='Fixture', chapters=list(range(1, count+1)))])))
        return audio

    def test_legacy_catalog_keeps_its_existing_path(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            self.fixture(root, 1)
            plan = jobs(root)
            self.assertEqual(plan[-1]['path'], 'evan-bsb/current.json')
            self.assertEqual(plan[-1]['mime'], 'application/json')

    def test_expanded_catalog_requires_separate_path(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            self.fixture(root, 153)
            with self.assertRaisesRegex(AssertionError, 'Older app builds reject larger catalogs'):
                jobs(root)
            plan = jobs(root, 'evan-bsb/current-v2.json')
            self.assertEqual(len(plan), 154)
            self.assertEqual(plan[-1]['path'], 'evan-bsb/current-v2.json')
            self.assertNotIn('evan-bsb/current.json', [item['path'] for item in plan])

    def test_changed_recording_cannot_be_uploaded(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            audio = self.fixture(root, 1)
            audio.write_bytes(b'different bytes')
            with self.assertRaises(AssertionError):
                jobs(root, 'evan-bsb/current-v2.json')

    def test_whole_bible_cannot_overgrow_installed_clients_catalog_limit(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            self.fixture(root, 1)
            catalog = root/'catalog.json'
            # Real verse cues make the whole Bible exceed build 100's 2 MB cap.
            catalog.write_text(catalog.read_text() + ' ' * 2_000_000)
            with self.assertRaisesRegex(AssertionError, 'cap older catalogs at 2 MB'):
                jobs(root, 'evan-bsb/current-v2.json')
            plan = jobs(root, 'evan-bsb/current-v3.json')
            self.assertEqual(plan[-1]['path'], 'evan-bsb/current-v3.json')
            self.assertGreater(plan[-1]['bytes'], 2_000_000)
            self.assertNotIn('evan-bsb/current-v2.json', [item['path'] for item in plan])


if __name__ == '__main__':
    unittest.main()
