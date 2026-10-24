import unittest

from verify_bible_audio import words, number_words, ordinal_words, timed_words


class BibleAudioTextChecks(unittest.TestCase):
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
        self.assertEqual(number_words(969), 'nine hundred sixty nine')
        self.assertEqual(ordinal_words(103), 'one hundred third')

    def test_name_transcription_spelling_preserves_distinct_readings(self):
        for source, spelling in [('Adah', 'Ada'), ('Admah', 'Adma'), ('Arioch', 'Ariok'),
                                 ('Casluhites', 'Kasluhites'), ('Caphtorites', 'Kaphtorites'),
                                 ('Rodanites', 'Rhodanites'), ('Goiim', 'Goyim'), ('O', 'Oh')]:
            with self.subTest(source=source):
                self.assertEqual(words(source), words(spelling))
        for source, other in [('Asshur', 'Asher'), ('Irad', 'Erad'), ('Raamah', 'Rama'),
                              ('seahs', 'seeds'), ('in', 'and')]:
            with self.subTest(source=source):
                self.assertNotEqual(words(source), words(other))


if __name__ == '__main__':
    unittest.main()
