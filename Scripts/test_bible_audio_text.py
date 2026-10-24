import hashlib
import os
import tempfile
import unittest
from pathlib import Path

from verify_bible_audio import words, number_words, ordinal_words, timed_words, audio_digest
from bible_audio_pronunciation import restore_source_spellings


class BibleAudioTextChecks(unittest.TestCase):
    def test_pronunciation_hints_cannot_change_source_words(self):
        entries = [dict(source='Irad', spoken='I-rad', reference='https://classic.net.bible.org/dictionary.php?word=Irad')]
        restored, used = restore_source_spellings('I-rad was born. I-rad lived 100 years.', entries)
        self.assertEqual(words(restored), words('Irad was born. Irad lived 100 years.'))
        self.assertEqual(used[0]['occurrences'], 2)
        changed, _ = restore_source_spellings('I-rad lived 101 years.', entries)
        self.assertNotEqual(words(changed), words('Irad lived 100 years.'))
        untouched, used = restore_source_spellings('Tirad was born.', entries)
        self.assertEqual(untouched, 'Tirad was born.')
        self.assertFalse(used)

    def test_replaced_recording_cannot_reuse_an_old_digest(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'recording.wav'
            path.write_bytes(b'old recording')
            first = audio_digest(path)
            self.assertEqual(first, audio_digest(path))
            stamp = path.stat()
            path.write_bytes(b'new recording')
            os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))
            self.assertEqual(audio_digest(path), hashlib.sha256(b'new recording').hexdigest())
            replacement = path.with_suffix('.replacement')
            replacement.write_bytes(b'final recording')
            replacement.replace(path)
            self.assertEqual(audio_digest(path), hashlib.sha256(b'final recording').hexdigest())

    def test_equivalent_spoken_numbers(self):
        for source, spoken in [('120 years', 'one hundred and twenty years'),
                               ('187 years', 'one hundred eighty seven years'),
                               ('595 years', 'five hundred and ninety five years'),
                               ('807 years', 'eight hundred seven years'),
                               ('601st year', 'six hundred and first year'),
                               ('600th year', 'six hundredth year'),
                               ('27th day', 'twenty seventh day')]:
            with self.subTest(source=source):
                self.assertEqual(words(source), words(spoken))

    def test_wrong_numbers_and_other_missing_words_are_rejected(self):
        for source, spoken in [('187 years', 'eighteen seven years'),
                               ('182 years', 'eighteen two years'),
                               ('120 years', 'one hundred twenty one years'),
                               ('807 years', 'eight hundred seventy years'),
                               ('601st year', '600th year'),
                               ('17th day', 'seventh day'),
                               ('one hundred and then he died', 'one hundred then he died')]:
            with self.subTest(source=source):
                self.assertNotEqual(words(source), words(spoken))

    def test_numeric_word_timestamps_remain_aligned(self):
        for text in ['one hundred and twenty years', 'one hundred and then he died',
                     'one thousand and five cubits', '600th year',
                     'six hundred and first year', '18-7 years']:
            items = [dict(word=w, start=float(i), end=i+.5) for i, w in enumerate(text.split())]
            with self.subTest(text=text):
                self.assertEqual([item[0] for item in timed_words(items)], words(text))

    def test_spelling_and_number_helpers(self):
        self.assertEqual(words('an ark'), words('an arc'))
        self.assertEqual(words('seedtime'), words('seed time'))
        self.assertEqual(words('a turtledove'), words('a turtle dove'))
        self.assertEqual(words('fell facedown'), words('fell face down'))
        self.assertEqual(words('had borne'), words('had born'))
        self.assertEqual(words('a bowshot away'), words('a bow shot away'))
        self.assertEqual(words('sometime later'), words('some time later'))
        self.assertEqual(words('worshiped'), words('worshipped'))
        self.assertEqual(words('an adviser'), words('an advisor'))
        self.assertEqual(words('plane trees'), words('plain trees'))
        self.assertEqual(words('Ben-oni'), words('Benoni'))
        self.assertEqual(words('sheepshearers'), words('sheep shearers'))
        self.assertEqual(words('a laughingstock'), words('a laughing stock'))
        self.assertEqual(words("the king's cup"), words('the kings cup'))
        self.assertNotEqual(words("the king's cup"), words('the king cup'))
        self.assertEqual(number_words(969), 'nine hundred sixty nine')
        self.assertEqual(ordinal_words(103), 'one hundred third')

    def test_name_transcription_spelling_preserves_distinct_readings(self):
        for source, spelling in [('Adah', 'Ada'), ('Admah', 'Adma'), ('Arioch', 'Ariok'),
                                 ('Casluhites', 'Kasluhites'), ('Caphtorites', 'Kaphtorites'),
                                 ('Rodanites', 'Rhodanites'), ('Goiim', 'Goyim'), ('O', 'Oh'),
                                 ('Rebekah', 'Rebecca'), ('Asshur', 'Ashur'), ('Asshurites', 'Ashurites'),
                                 ('Hirah', 'Hira'), ('Malchiel', 'Malkiel'),
                                 ('Potiphera', 'Potipherah'), ('Puvah', 'Puva'), ('Ammi', 'Ammy'),
                                 ('Raamah', 'Ramah'), ('Raamah', 'Rama'), ('Shua', 'Shuah'),
                                 ('Anah', 'Ana'), ('Zibeon', 'Zibion')]:
            with self.subTest(source=source):
                self.assertEqual(words(source), words(spelling))
        for source, other in [('Asshur', 'Asher'), ('Irad', 'Erad'),
                              ('seahs', 'seeds'), ('in', 'and'), ('Rebekah', 'Rachel'), ('Hirah', 'Hera'),
                              ('Potiphera', 'Potiphar'), ('Serah', 'Sarah'), ('Ammi', 'Amy')]:
            with self.subTest(source=source):
                self.assertNotEqual(words(source), words(other))


if __name__ == '__main__':
    unittest.main()
