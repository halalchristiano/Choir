import hashlib
import os
import tempfile
import unittest
from pathlib import Path

from verify_bible_audio import words, number_words, ordinal_words, timed_words, audio_digest
from bible_audio_pronunciation import restore_source_spellings


class BibleAudioTextChecks(unittest.TestCase):
    def test_named_spelling_variants_preserve_vowels_syllables_and_endings(self):
        pairs = [('Isshiah', 'Ishiah'), ('Giloh', 'Gilo'), ('Libnah', 'Libna'),
                 ('Achbor', 'Akbor'), ('Joiarib', 'Joyarib'), ('Zattu', 'Zatu')]
        for source, recognized in pairs:
            with self.subTest(source=source):
                self.assertEqual(words(source), words(recognized))
                self.assertEqual([w[0] for w in timed_words([
                    dict(word=recognized, start=0., end=1.)])], words(source))
        for source, recognized in [('Isshiah', 'Ashiah'), ('Isshiah', 'Ishi'),
                                   ('Giloh', 'Gil'), ('Giloh', 'Gila'),
                                   ('Libnah', 'Labna'), ('Libnah', 'Libanah'),
                                   ('Achbor', 'Akbar'), ('Achbor', 'Abdon'),
                                   ('Joiarib', 'Joyrib'), ('Joiarib', 'Jehoiarib'),
                                   ('Zattu', 'Zeta'), ('Zattu', 'Zattus'),
                                   ('Jerimoth', 'Jeremoth'), ('Hamutal', 'Hamital')]:
            with self.subTest(source=source, recognized=recognized):
                self.assertNotEqual(words(source), words(recognized))

    def test_sourced_english_name_homophones_keep_other_sounds_distinct(self):
        # Amon/Ammon and Zebah/Zeba were previously held distinct pending
        # English pronunciation evidence. Both pairs are now documented.
        for source, transcript in [('Amon', 'Ammon'), ('Zebah', 'Zeba'),
                                   ('Zuph', 'Zuf'), ('Malchijah', 'Malchiah'),
                                   ('Malchijah', 'Malkijah')]:
            self.assertEqual(words(source), words(transcript))
            self.assertEqual(timed_words([dict(word=transcript, start=1., end=2.)]),
                             [(words(source)[0], 1., 2.)])
        for source, wrong in [('Amon', 'Aman'), ('Ammon', 'Ammonites'),
                              ('Zebah', 'Ziba'), ('Zebah', 'Zeb'),
                              ('Zuph', 'Zuth'), ('Zuph', 'Suph'),
                              ('Malchijah', 'Malchiram'), ('Malchijah', 'Malachi'),
                              ('Malchijah', 'Melchiah'), ('Addar', 'Adar'),
                              ('Heman', 'Haman'), ('and', 'in')]:
            self.assertNotEqual(words(source), words(wrong))

    def test_prophetic_book_compounds_keep_each_component_and_ending(self):
        pairs=[('vinedressers','vine dressers'), ('reentered','re entered'),
               ('winepress','wine press'), ('winepresses','wine presses'),
               ("today's",'to days'), ('sheepdogs','sheep dogs'),
               ('faultfinder','fault finder'), ('simplehearted','simple hearted'),
               ('thornbush','thorn bush'), ('firepot','fire pot'),
               ('lampstands','lamp stands'), ('cutstones','cut stones'),
               ('underfoot','under foot'), ('mountaintops','mountain tops'),
               ('wheelwork','wheel work'), ('wasteland','waste land'),
               ('marketplace','market place')]
        for compound,spaced in pairs:
            self.assertEqual(words(compound),words(spaced))
            for text in (compound,spaced):
                times=[dict(word=w,start=float(i),end=i+.5) for i,w in enumerate(text.split())]
                mapped=timed_words(times)
                self.assertEqual([w[0] for w in mapped],words(compound))
                self.assertEqual(mapped[0][1],0.)
                self.assertEqual(mapped[-1][2],times[-1]['end'])
            for missing in spaced.split():self.assertNotEqual(words(compound),words(missing))
        for expected,wrong in [('winepresses','wine press'), ('vinedressers','vine dresser'),
                               ('sheepdogs','sheep dog'), ('lampstands','lamp stand'),
                               ('cutstones','cut stone'), ('mountaintops','mountain top'),
                               ('firepot','fire pit'), ('wheelwork','wheel walk'),
                               ('wasteland','wastelands'), ('marketplace','marked place'),
                               ('and','in'), ('Gemariah','Jemariah')]:
            self.assertNotEqual(words(expected),words(wrong))

    def test_attested_name_doubling_does_not_hide_other_name_changes(self):
        for expected, transcript in [('Avvites', 'Avites'), ('Ivvah', 'Ivah'),
                                     ('Hammuel', 'Hamuel'), ('Shenazzar', 'Shenazar')]:
            self.assertEqual(words(expected), words(transcript))
            self.assertEqual(timed_words([dict(word=transcript, start=1., end=2.)]),
                             [(words(expected)[0], 1., 2.)])
        for expected, wrong in [('Avvites', 'Avvite'), ('Avvites', 'Avvim'),
                                ('Avvites', 'Hivites'), ('Ivvah', 'Avva'),
                                ('Ivvah', 'Eve'), ('Hammuel', 'Samuel'),
                                ('Hammuel', 'Hamiel'), ('Shenazzar', 'Sheshbazzar'),
                                ('Shenazzar', 'Shenazah'), ('Amon', 'Aman'),
                                ('Addar', 'Adar'), ('Heman', 'Haman')]:
            self.assertNotEqual(words(expected), words(wrong))

    def test_psalm_spacing_and_regional_spellings_preserve_reading_errors(self):
        for expected, transcript in [('choirmaster', 'choir master'),
                                     ('forevermore', 'for evermore'),
                                     ('forevermore', 'forever more'),
                                     ('forevermore', 'for ever more'),
                                     ('evermore', 'ever more'), ('savior', 'saviour'),
                                     ('valor', 'valour'), ('honors', 'honours')]:
            self.assertEqual(words(expected), words(transcript))
            original = [dict(word=w, start=float(i), end=i+.75)
                        for i, w in enumerate(transcript.split())]
            mapped = timed_words(original)
            self.assertEqual([w[0] for w in mapped], words(expected))
            self.assertEqual(mapped[0][1], 0.)
            self.assertEqual(mapped[-1][2], original[-1]['end'])
        for expected, wrong in [('choirmaster', 'master'), ('choirmaster', 'quarmaster'),
                                ('forevermore', 'forever'), ('forevermore', 'evermore'),
                                ('evermore', 'more'), ('savior', 'saviors'),
                                ('honors', 'honor'), ('song', 'psalm'),
                                ('ascents', 'assense'), ('Selah', 'Salah'),
                                ('Selah', ''), ('bows', 'boughs'), ('and', 'in')]:
            self.assertNotEqual(words(expected), words(wrong))

    def test_historical_name_spacing_keeps_complete_word_cues(self):
        examples = [('Beth-shemesh', 'Bethshemesh'), ('Elteke', 'El teke'),
                    ('Lo-debar', 'Lodebar'), ('almug wood', 'almugwood'),
                    ('Ge-harashim', 'Geharashim'), ('Esh-baal', 'Eshbaal'),
                    ('skillful', 'skilful')]
        for expected, transcript in examples:
            self.assertEqual(words(expected), words(transcript))
            original = [dict(word=w, start=float(i), end=i+.75)
                        for i, w in enumerate(transcript.split())]
            mapped = timed_words(original)
            self.assertEqual([w[0] for w in mapped], words(expected))
            self.assertEqual(mapped[0][1], 0.)
            self.assertEqual(mapped[-1][2], original[-1]['end'])
        for expected, wrong in [('Beth-shemesh', 'Beth Shemish'),
                                ('Elteke', 'El'), ('Elteke', 'Eltekeh'),
                                ('Lo-debar', 'Debar'), ('almug wood', 'almug'),
                                ('Ge-harashim', 'Harashim'), ('Esh-baal', 'Ish Baal'),
                                ('skillful', 'skillfully'), ('Amon', 'Aman'),
                                ('Heman', 'Haman'), ('and', 'in')]:
            self.assertNotEqual(words(expected), words(wrong))

    def test_documented_homophones_keep_quantities_and_other_words_distinct(self):
        for expected, recognized in [('your', "you're"), ('cor', 'core'), ('cors', 'cores'),
                                     ('Shecaniah', 'Shekaniah'), ('Shecaniah', 'Shechaniah'),
                                     ('Avvim', 'Avim')]:
            self.assertEqual(words(expected), words(recognized))
            self.assertEqual([w[0] for w in timed_words([
                dict(word=recognized, start=1., end=2.)])], words(expected))
        for expected, wrong in [('your', 'you'), ('your', 'you are'),
                                ('you are', "you're"), ('cors', 'cor'), ('cors', 'core'),
                                ('cors', 'course'), ('three cors', 'two cores'),
                                ('Shecaniah', 'Shekanihu'), ('Shecaniah', 'Shekanyahu'),
                                ('Shecaniah', 'Shekania'), ('Avvim', 'Avvi'),
                                ('Avvim', 'Avvites'), ('Heman', 'Haman'),
                                ('Jerubbaal', 'Jeroboam'), ('seah', 'sea'), ('in', 'and')]:
            self.assertNotEqual(words(expected), words(wrong))

    def test_documented_historical_name_spellings_keep_pronunciation_changes_flagged(self):
        for expected, recognized in [('Acsah', 'Aksah'), ('Achshaph', 'Akshaph'),
                                     ('Helkath', 'Helcath'), ('Tappuah', 'Tapuah')]:
            self.assertEqual(words(expected), words(recognized))
            self.assertEqual([w[0] for w in timed_words([
                dict(word=recognized, start=1., end=2.)])], words(expected))
        for expected, wrong in [('Acsah', 'Asah'), ('Acsah', 'Aksaha'),
                                ('Achshaph', 'Akshap'), ('Achshaph', 'Akshaphah'),
                                ('Helkath', 'Helcat'), ('Helkath', 'Helketh'),
                                ('Tappuah', 'Tapu'), ('Tappuah', 'Tipuah'),
                                ('Hivites', 'Hevites'), ('Makkedah', 'Macdah'),
                                ('Taanach', 'Tanakh'), ('Kedesh', 'Kadesh'),
                                ('Zebah', 'Ziba'), ('and', 'in')]:
            self.assertNotEqual(words(expected), words(wrong))

    def test_historical_books_compound_spacing_preserves_each_part(self):
        for compound, spaced in [('oxgoad', 'ox goad'), ('chainwork', 'chain work'),
                                 ('guardroom', 'guard room'), ('baldhead', 'bald head'),
                                 ('anymore', 'any more'), ('stonecutter', 'stone cutter'),
                                 ('stonecutters', 'stone cutters'), ('showbread', 'show bread'),
                                 ('wingspan', 'wing span'), ('hindquarters', 'hind quarters'),
                                 ('courtyard', 'court yard')]:
            with self.subTest(compound=compound):
                self.assertEqual(words(compound), words(spaced))
                for transcript in (compound, spaced):
                    times = [dict(word=w, start=float(i), end=i+.5)
                             for i, w in enumerate(transcript.split())]
                    self.assertEqual([w[0] for w in timed_words(times)], words(compound))
                for missing in spaced.split():
                    self.assertNotEqual(words(compound), words(missing))
        for expected, wrong in [('stonecutters', 'stone cutter'),
                                ('hindquarters', 'hind quarter'),
                                ('oxgoad', 'ox god'), ('chainwork', 'chain walk'),
                                ('guardroom', 'guard rooms'), ('baldhead', 'ball head'),
                                ('showbread', 'shewbreadth'), ('wingspan', 'wing spans'),
                                ('courtyard', 'court yards'), ('and', 'in'),
                                ('Hivites', 'Hevites'), ('Acsah', 'Aksaha')]:
            self.assertNotEqual(words(expected), words(wrong))

    def test_joshua_judges_spelling_and_spacing_preserve_content_changes(self):
        for expected, recognized in [('traveled', 'travelled'), ('brier', 'briar'),
                                     ('briers', 'briars'), ('tonight', 'to night'),
                                     ('hometown', 'home town'), ("everyone's", "every one's")]:
            self.assertEqual(words(expected), words(recognized))
            times=[dict(word=w,start=float(i),end=i+.5) for i,w in enumerate(recognized.split())]
            self.assertEqual([w[0] for w in timed_words(times)],words(expected))
        for expected, wrong in [('traveled', 'travel'), ('briers', 'brier'),
                                ('tonight', 'night'), ('hometown', 'town'),
                                ("everyone's", 'everyone'), ('waters', 'water'),
                                ('Shittim', 'Shatim'), ('Zarethan', 'Zarathun')]:
            self.assertNotEqual(words(expected), words(wrong))

    def test_numbers_spelling_equivalents_preserve_wrong_names(self):
        for a,b in [('firstborn','first born'), ('stillborn','still born'),
                    ('Ammishaddai','Amishadai'), ('Zurishaddai','Zurishadai'),
                    ('Ammihud','Amihud'), ('Shammua','Shamua'), ('Uzzielites','Uzielites'),
                    ('Ocran','Okran'), ('Eshcol','Eshkol'), ('Nazirite','Nazarite'),
                    ('Mahli','Mali'), ('Mahlites','Malites'), ('Zichri','Zikri'), ('Zichri','Zicri')]:
            self.assertEqual(words(a), words(b))
            items=[dict(word=w,start=float(i),end=i+.5) for i,w in enumerate(b.split())]
            self.assertEqual([w[0] for w in timed_words(items)], words(a))
        for a,b in [('Zurishaddai','Zurushadai'), ('Ammihud','Amehud'),
                    ('Shammua','Shammual'), ('Mahli','Mahi'), ('Ocran','Ocren'),
                    ('Uzzielites','Uzielite'), ('Nazirite','Nazarene'), ('Elizur','Elizar'),
                    ('Zichri','Zitri')]:
            self.assertNotEqual(words(a), words(b))

    def test_leviticus_spacing_and_homophones_preserve_word_changes(self):
        for a,b in [('earlobe','ear lobe'), ('reexamine','re examine'), ('reexamines','re examines'),
                    ('reenter','re enter'), ('anything','any thing'), ('windblown','wind blown'),
                    ('crossbreed','cross breed'), ('bloodguilt','blood guilt'),
                    ('pastureland','pasture land'), ("someone's","some one's"),
                    ('practice','practise'), ('practiced','practised'), ('fulfillment','fulfilment'),
                    ('veil','vale'), ('male','mail'), ('guilt','gilt'), ('waved','waived')]:
            self.assertEqual(words(a), words(b))
            items=[dict(word=w,start=float(i),end=i+.5) for i,w in enumerate(b.split())]
            self.assertEqual([w[0] for w in timed_words(items)], words(a))
        for a,b in [('emission','omission'), ('countryman','countrymen'), ('reexamines','re examine'),
                    ('earlobes','ear lobe'), ('has','is'), ('hide','hind'), ('its','his')]:
            self.assertNotEqual(words(a), words(b))

    def test_tabernacle_compounds_and_british_spelling(self):
        pairs = [('molding','moulding'), ('skillfully','skilfully'), ('totaled','totalled'),
                 ('fulfill','fulfil'), ('jewelry','jewellery'), ('chiseled','chiselled'),
                 ('splendor','splendour'), ('quarreled','quarrelled'),
                 ('quarreling','quarrelling'), ('willfully','wilfully'), ('labor','labour'),
                 ('lampstand','lamp stand'), ('everyone','every one'), ('ram skins','ramskins'),
                 ('breastpiece','breast piece'), ('manservant','man servant'),
                 ('menservants','men servants'), ('crossbar','cross bar'), ('crossbars','cross bars'),
                 ('firstfruits','first fruits'), ('handbreadth','hand breadth'),
                 ('halfway','half way'), ('freewill','free will'), ('mountaintop','mountain top'),
                 ('livestock','live stock'), ('cord work','cordwork'), ('doorpost','door post'),
                 ('earlobes','ear lobes'), ('headbands','head bands')]
        for a,b in pairs:
            self.assertEqual(words(a), words(b))
            items=[dict(word=w,start=float(i),end=i+.5) for i,w in enumerate(b.split())]
            self.assertEqual([w[0] for w in timed_words(items)], words(a))
        for a,b in [('menservants','man servant'), ('crossbars','cross bar'),
                    ('firstfruits','first fruit'), ('earlobes','ear lobe'),
                    ('frames','frame'), ('directs','direct'), ('Eliezer','Eleazar')]:
            self.assertNotEqual(words(a), words(b))

    def test_exodus_compound_spacing_preserves_missing_words(self):
        for compound, spaced in [('birthstools', 'birth stools'), ('birthstool', 'birth stool'),
                                 ('riverbank', 'river bank'), ('riverbanks', 'river banks'),
                                 ('maidservant', 'maid servant'), ('maidservants', 'maid servants'),
                                 ('today', 'to day'), ('tomorrow', 'to morrow'),
                                 ('someone', 'some one'), ('anyone', 'any one'),
                                 ('doorframe', 'door frame'), ('doorframes', 'door frames'),
                                 ('workload', 'work load'), ('flint knife', 'flintknife'),
                                 ('hand mill', 'handmill'), ('marvelous', 'marvellous'),
                                 ('favor', 'favour'), ('honor', 'honour'),
                                 ('neighbor', 'neighbour'), ('neighbors', 'neighbours'),
                                 ('Shiphrah', 'Shifra'), ('Pi-hahiroth', 'Pihahiroth'),
                                 ('Ahisamach', 'Ahi Samach'), ('Rameses', 'Ramesses'),
                                 ('Oholiab', 'Aholiab'), ('Uzziel', 'Uziel'), ('Pallu', 'Palu'),
                                 ('Hanoch', 'Hannock'), ('gerahs', 'geras'),
                                 ('Nahshon', 'Nashon'), ('Phinehas', 'Phineas'),
                                 ('Assir', 'Asir'), ('firepans', 'fire pans')]:
            self.assertEqual(words(compound), words(spaced))
            items = [dict(word=w, start=float(i), end=i+.5) for i,w in enumerate(spaced.split())]
            self.assertEqual([w[0] for w in timed_words(items)], words(compound))
        for expected, wrong in [('birthstools', 'birth stool'), ('riverbank', 'bank'),
                                ('maidservants', 'maid servant'), ('today', 'day'),
                                ('Pithom', 'Pithem'), ('Reuel', 'Reoel'),
                                ('doorframes', 'door frame'), ('Shiphrah', 'Shiphraha'),
                                ('roasted', 'roast it'),
                                ('Pi-hahiroth', 'Piaheroth'), ('Ahisamach', 'Ahisamech'),
                                ('Rameses', 'Ramizes'), ('Oholiab', 'Oholibah'),
                                ('Uzziel', 'Uzzil'), ('Hanoch', 'Hanak'), ('gerahs', 'jarahs'),
                                ('Assir', 'Asher'), ('Nahshon', 'Nason'), ('firepans', 'fire pan')]:
            self.assertNotEqual(words(expected), words(wrong))

    def test_remaining_nt_orthography_preserves_reading_errors(self):
        for a, b in [("Maath", "Ma'ath"), ("Syrtis", "Sirtis"), ("Rhegium", "Regium"),
                     ("Aenon", "Enon"), ("Mnason", "Nason"), ("Akeldama", "a keldama"),
                     ("Manaen", "man a en"), ("Mitylene", "miti lini"),
                     ("Mitylene", "Mytilene"), ("Mitylene", "Mitilini"), ("Gallio", "Galio"), ("Attalia", "Atalia"), ("Chuza", "Chusa"), ("forever", "for ever"),
                     ("Nicolas", "Nicholas"), ("Cnidus", "Nidus"), ("traveling", "travelling"),
                     ("foreseeing", "for seeing"), ("there", "their")]:
            self.assertEqual(words(a), words(b))
            self.assertEqual([w[0] for w in timed_words([dict(word=b, start=0., end=1.)])], words(a))
        for a, b in [("Manaen", "Manahein"), ("Mitylene", "Metellim"), ("Mitylene", "Midulene"),
                     ("Gallio", "Galileo"), ("Maath", "Maathah"), ("Maath", "Matthat"), ("and", "in"),
                     ("ask", "asked"), ("stop", "stopped"), ("I am", "I'm"),
                     ("craftsmen", "craftsman")]:
            self.assertNotEqual(words(a), words(b))

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
        for ending in [',000', ',000?', ',000.', ',000,', ',000,000!']:
            items = [dict(word=' 20', start=1., end=1.2),
                     dict(word=ending, start=1.2, end=1.8)]
            aligned = timed_words(items)
            self.assertEqual([w[0] for w in aligned], words('20'+ending))
            self.assertTrue(all(w[1:] == (1., 1.8) for w in aligned))
        separate = [dict(word='20', start=0., end=.5), dict(word='000', start=.5, end=1.)]
        self.assertNotEqual([w[0] for w in timed_words(separate)], words('20,000'))
        for text in ['one hundred and twenty years', 'one hundred and then he died',
                     'one thousand and five cubits', '600th year',
                     'six hundred and first year', '18-7 years']:
            items = [dict(word=w, start=float(i), end=i+.5) for i, w in enumerate(text.split())]
            with self.subTest(text=text):
                self.assertEqual([item[0] for item in timed_words(items)], words(text))

    def test_spelling_and_number_helpers(self):
        for source, spoken in [('turtledoves', 'turtle doves'), ('thornbushes', 'thorn bushes'),
                               ('onto the road', 'on to the road'), ('sun', 'son')]:
            self.assertEqual(words(source), words(spoken))
            items = [dict(word=w, start=float(i), end=i+.5) for i,w in enumerate(spoken.split())]
            self.assertEqual([item[0] for item in timed_words(items)], words(source))
        for source, spoken in [('crowds', 'crowd'), ('others', 'other'), ('and', 'in'),
                               ('Jews', 'Joes'), ('Amminadab', 'Ammonadab')]:
            self.assertNotEqual(words(source), words(spoken))
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
        self.assertEqual(words('pasturelands'), words('pasture lands'))
        self.assertEqual(words('grainfield'), words('grain field'))
        self.assertEqual(words('favoured'), words('favored'))
        self.assertEqual(words('foreman'), words('foremen'))
        self.assertEqual(words('unsown'), words('unsewn'))
        self.assertEqual(words('sulfur'), words('sulphur'))
        for a,b in [('Rabbah','Rabba'),('Rabbah','Rabah'),('Aroer','a roer'),('Eliasaph','Eliasaf'),('Elizaphan','Elizafan'),('Shepher','Shefer'),('Vophsi','Vofsi'),('Shupham','Shufam'),('Shuphamite','Shufamite'),('Hanoch','Hanok'),('Hanochite','Hanokite')]:
            self.assertEqual(words(a),words(b))
        for a,b in [('Rabbah','Rabahh'),('Eliasaph','Eliaseph'),('Shepher','Sheper'),('Shepher','Shepherd'),('Shupham','Shupam'),('Hanoch','Hanuk'),('Hanochite','Hanukkite')]:
            self.assertNotEqual(words(a),words(b))
        self.assertEqual(words('Aroer'),words('a rower'))
        self.assertEqual(words('Aroer'),words('Aror'))
        self.assertEqual(words('Ahiezer'),words('Ahi ezer'))
        self.assertEqual(words('Deuel'),words('Deu el'))
        self.assertNotEqual(words('Aroer'),words('rower'))
        self.assertNotEqual(words('Ahiezer'),words('Abiezer'))
        self.assertNotEqual(words('Deuel'),words('Deweel'))
        self.assertEqual(words('Elizaphan'), words('Elisaphan'))
        self.assertEqual(words('Elizur'), words('Elisur'))
        for a,b in [('Elizaphan','Elisaphon'),('Elizaphan','Elishaphan'),('Elizaphan','Elzaphan'),('Elizur','Eliezer'),('Elizur','Eleazar'),('Elizur','Elisor'),('Elizur','Elisir')]:
            self.assertNotEqual(words(a),words(b))
        for a,b in [('a hundred and thirty','130'),('a-hundred and thirty','130'),('a—hundred and thirty','130'),('a thousand','1000'),('a million','1000000'),('a billion','1000000000')]:
            self.assertEqual(words(a),words(b))
        for a,b in [('a silver platter','one silver platter'),('a hundred','hundred'),('a hundred','200'),('a hundredth','one hundredth')]:
            self.assertNotEqual(words(a),words(b))
        sample=[dict(word=w,start=i,end=i+1) for i,w in enumerate('a hundred and thirty'.split())]
        aligned=timed_words(sample)
        self.assertEqual([w[0] for w in aligned],words('130'))
        self.assertEqual(aligned[0],('one',0,1))
        self.assertEqual(words('Eleazar'), words('El eazar'))
        self.assertNotEqual(words('Eleazar'), words('Eliezer'))
        self.assertNotEqual(words('Eleazar'), words('El iyazar'))
        for a,b in [('Cozbi','Cosby'),('Cozbi','Kozbi'),('Ammiel','Amiel'),('Hepher','Hefer'),('Hepherite','Heferite'),('Hupham','Hufam'),('Huphamite','Hufamite'),('Riblah','Ribla'),('Suphah','Sufa'),('Suphah','Sufah'),('Suphah','Supha'),('Unsandaled','Unsandled')]:
            self.assertEqual(words(a),words(b))
        for a,b in [('Cozbi','Crosby'),('Ammiel','Amal'),('Hepher','Heper'),('Hepherite','Hepher'),('Hupham','Huppam'),('Riblah','Rib'),('Suphah','Suph'),('Unsandaled','Unsaddled'),('Unsandaled','Unsanded')]:
            self.assertNotEqual(words(a),words(b))
        self.assertEqual(words('Zeboiim'), words('Zeboim'))
        self.assertEqual(words('a count'), words('account'))
        self.assertNotEqual(words('a count'), words('count'))
        self.assertNotEqual(words('Zeboiim'), words('Ziboim'))
        self.assertNotEqual(words('unsown'), words('sown'))
        self.assertNotEqual(words('unsown'), words('unseen'))
        self.assertNotEqual(words('magician'), words('magicians'))
        self.assertNotEqual(words('favoured'), words('favour'))
        self.assertNotEqual(words('grainfield'), words('grainfields'))
        self.assertNotEqual(words('pasturelands'), words('pastureland'))
        self.assertEqual(words('Beeri'), words('Be-eh-ree'))
        self.assertEqual(words('evil men and imposters'), words('evil men and impostors'))
        self.assertNotEqual(words('imposters'), words('imposter'))
        self.assertNotEqual(words('Beeri'), words('Be-er'))
        self.assertEqual(words("the king's cup"), words('the kings cup'))
        self.assertNotEqual(words("the king's cup"), words('the king cup'))
        self.assertEqual(number_words(969), 'nine hundred sixty nine')
        self.assertEqual(ordinal_words(103), 'one hundred third')

    def test_name_transcription_spelling_preserves_distinct_readings(self):
        for source, spelling in [('Ephah', 'Epha'), ('Suph', 'Suf'), ('Agag', 'A gag')]:
            self.assertEqual(words(source), words(spelling))
        for source, other in [('Ephah', 'Aphah'), ('Suph', 'Suphah'), ('Agag', 'Hagag')]:
            self.assertNotEqual(words(source), words(other))
        self.assertEqual(words('Amminadab'), words('Aminadab'))
        self.assertNotEqual(words('Amminadab'), words('Ammonadab'))
        self.assertEqual(words('Joanan'), words('Joannan'))
        self.assertEqual(words('Melea'), words("Mele'ah"))
        self.assertEqual(words('Melea'), words('Meleah'))
        self.assertEqual(words('worshiping worshipers'), words('worshipping worshippers'))
        self.assertNotEqual(words('worshipers'), words('worshiper'))
        self.assertEqual(words('tentmakers'), words('tent makers'))
        self.assertEqual(words('longstanding'), words('long standing'))
        self.assertNotEqual(words('tentmakers'), words('tent maker'))
        self.assertNotEqual(words('Joanan'), words('Jonam'))
        self.assertNotEqual(words('Melea'), words('Meleas'))
        self.assertNotEqual(words('Maath'), words('Maathah'))
        for source, spelling in [('Adah', 'Ada'), ('Admah', 'Adma'), ('Arioch', 'Ariok'),
                                 ('Casluhites', 'Kasluhites'), ('Caphtorites', 'Kaphtorites'),
                                 ('Rodanites', 'Rhodanites'), ('Goiim', 'Goyim'), ('O', 'Oh'),
                                 ('Rebekah', 'Rebecca'), ('Asshur', 'Ashur'), ('Asshurites', 'Ashurites'),
                                 ('Hirah', 'Hira'), ('Malchiel', 'Malkiel'),
                                 ('Potiphera', 'Potipherah'), ('Puvah', 'Puva'), ('Ammi', 'Ammy'),
                                 ('Raamah', 'Ramah'), ('Raamah', 'Rama'), ('Shua', 'Shuah'),
                                 ('Anah', 'Ana'), ('Zibeon', 'Zibion'),
                                 ('Jannes', 'Jannez'), ('Jambres', 'Jambrez'), ('Onesiphorus', 'Onisiphorus')]:
            with self.subTest(source=source):
                self.assertEqual(words(source), words(spelling))
        for source, other in [('Asshur', 'Asher'), ('Irad', 'Erad'),
                              ('seahs', 'seeds'), ('in', 'and'), ('Rebekah', 'Rachel'), ('Hirah', 'Hera'),
                              ('Potiphera', 'Potiphar'), ('Serah', 'Sarah'), ('Ammi', 'Amy'),
                              ('Jannes', 'Jonas'), ('Jannes', 'Jambres'), ('Onesiphorus', 'Onesimus'),
                              ('Dishon', 'Dishan')]:
            with self.subTest(source=source):
                self.assertNotEqual(words(source), words(other))


if __name__ == '__main__':
    unittest.main()
