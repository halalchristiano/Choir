# Remaining NT audio: recognition spelling equivalence

These comparisons apply only to automated back-transcription. The app's BSB
source text is unchanged. Every selected recording retains the raw recognizer
output and word timestamps. A pass still requires the complete normalized text,
complete matching timestamps, the exact audio hash, and no clipped samples.

Version 32 accepts British `travelling`, compound spacing `for seeing`, the
homophones `their`/`there`, and the syllable separator in `Ma'ath`. Version 33
adds the name spellings `Sirtis`, `Regium`, `Nicholas`, and `Nidus`. Versions
34–36 add `Atalia`, `Chusa`, `for ever`, `Enon`, `Nason`, `a keldama`, and `Galio`.
These do not remove or add spoken syllables. The same transformation applies
to the source, transcript, and individual recognized word timestamps.

Pronunciation and spelling references consulted 2026-10-30:

- Maath: Strong G3092, `mah-ath`: https://biblehub.com/greek/3092.htm
- Syrtis: ISBE, `sir-tis`: https://biblehub.com/topical/s/syrtis.htm
- Rhegium: ISBE, `re-ji-um`: https://biblehub.com/topical/r/rhegium.htm
- Nicolas: ISBE, `nik-o-las`: https://biblehub.com/topical/n/nicolas.htm
- Cnidus: Smith's spelling `nidus`; ISBE `ni-dus` / `kni-dus`:
  https://biblehub.com/topical/c/cnidus.htm
- Chuza: Thayer lists the older spelling Chusa:
  https://biblehub.com/greek/5529.htm
- Aenon: ISBE, `e-non`: https://biblehub.com/topical/a/aenon.htm
- Mnason: ISBE, `na-son` / `m-na-son`:
  https://biblehub.com/topical/m/mnason.htm
- Akeldama: ISBE, `a-kel-da-ma`:
  https://biblehub.com/topical/a/akeldama.htm
- Attalia: ISBE, `at-a-li-a`:
  https://biblehub.com/topical/a/attalia.htm
- Gallio: Strong G1058, three syllables, not Galileo:
  https://biblehub.com/greek/1058.htm

Tests explicitly reject distinct readings including Maathah, Matthat, Galileo,
`and`/`in`, `ask`/`asked`, `stop`/`stopped`, `I am`/`I'm`, and
`craftsmen`/`craftsman`. No whole-passage text is supplied as a recognition hint;
where used, hints contain isolated proper names only. Automated checks are not
a human listening or voice-likeness review.

Version 37 also compares the explicitly generated, reference-supported syllables
`man a en` with Manaen and `miti lini`/`Mitilini` with Mitylene. ISBE gives
`man-a-en` (https://biblehub.com/topical/m/manaen.htm) and `mit-i-le-ne`
(https://biblehub.com/topical/m/mitylene.htm). Different vowels or extra
syllables such as Manahein, Midulene, and Metellim still fail.

Version 38 also accepts Mytilene, the explicitly documented alternate spelling
of Mitylene in Strong G3412: https://biblehub.com/greek/3412.htm.

Version 39 adds compound spacing seen in the Exodus first transcription:
birthstool(s)/birth stool(s), riverbank(s)/river bank(s),
maidservant(s)/maid servant(s), and today/to day. These retain all spoken
components, including plural endings. Raw transcripts and timestamp records
remain unchanged. Missing components, changed plurals, and uncertain name
vowels (Pithom/Pithem and Reuel/Reoel) still fail.

Version 40 adds observed compound spacing for tomorrow, someone, anyone,
doorframe(s), workload, flintknife, and handmill; standard British spellings
marvellous, favour, honour, and neighbour(s); and Shifra for Shiphrah.
Strong H8236 gives shif-raw (https://biblehub.com/hebrew/8236.htm), supporting
ph/f and silent final h only. Foremen/foreman and roasted/roast it remain
different readings requiring another recognizer or a corrected take.

Version 41 extends the same strictly orthographic handling to tabernacle
vocabulary (lampstand, breastpiece, crossbar(s), firstfruits, handbreadth,
cordwork, and related compounds) and further standard British spellings.
Every added pair has transcript and timestamp normalization checks; changed
plurals and distinct names such as Eliezer/Eleazar remain rejected.

Version 42 treats Pihahiroth/Pi-hahiroth and Ahisamach/Ahi Samach as
segmentation differences. Every letter is preserved; changed spellings such
as Piaheroth and Ahisamech remain rejected.

Version 43 accepts Ramesses for Rameses (the same city/name, H7486,
https://biblehub.com/hebrew/7486.htm) and Aholiab for Oholiab (explicit KJV
form of H171, https://biblehub.com/strongs/hebrew/171.htm). These are
attested forms only; Ramizes and the distinct Oholibah still fail.

Version 44 accepts Uziel/Uzziel and Palu/Pallu (consonant doubling only),
Hannock/Hanoch (ha-nok, ISBE), and geras/gerahs (silent final h before plural s).
Pronunciation references: https://biblehub.com/hebrew/5816.htm,
https://biblehub.com/hebrew/6396.htm,
https://biblehub.com/topical/h/hanoch.htm,
https://biblehub.com/strongs/hebrew/1626.htm.
Uzzil, Hanak, and jarahs remain mismatches.

Version 45 adds Leviticus compound/hyphen spacing (including reexamine,
reenter, earlobe, bloodguilt, and pastureland), the possessive someone's/some
one's, British practise/practised/fulfilment, and audible homophones
veil/vale, male/mail, guilt/gilt, waved/waived. Changed vowels, plurals,
possessives, and verbs (emission/omission, countryman/countrymen, its/his,
has/is) still fail. Raw recognition is preserved without substitutions.

Version 46 adds Nashon/Nahshon (ISBE na-shon,
https://biblehub.com/topical/n/nahshon.htm), Phineas/Phinehas (ISBE fin-e-as,
https://biblehub.com/topical/p/phinehas.htm), and Asir/Assir (H617 ah-seer,
https://biblehub.com/strongs/hebrew/617.htm), plus firepans/fire pans spacing.
Assir/Asher, Nahshon/Nason, and missing plural endings remain rejected.

Version 47 adds firstborn/stillborn spacing and consonant-doubling-only forms
Amishadai, Zurishadai, Amihud, Shamua, and Uzielites. It also accepts Okran
(H5918, https://biblehub.com/strongs/hebrew/5918.htm), Eshkol (ISBE esh-kol,
https://biblehub.com/topical/e/eshcol.htm), Nazarite (Easton's explicitly
equates Nazirite, https://biblehub.com/topical/n/nazarite.htm), Mali (ISBE
ma-li, https://biblehub.com/topical/m/mahli.htm), and Malites (ISBE ma-lits,
https://classic.net.bible.org/dictionary.php/dictionary.php?word=Mahlites).
Changed vowels, missing syllables, plurals, and distinct names remain errors.

Version 48 accepts the explicitly documented Zikri/Zicri transliterations of
Zichri (https://biblehub.com/hebrew/2147.htm; ISBE zik-ri at
https://biblehub.com/topical/z/zichri.htm). The different consonant in Zitri
remains rejected.

Version 49 accepts Epha/Ephah (silent final h; Cambridge English pronunciation
https://dictionary.cambridge.org/pronunciation/english/ephah), Suf/Suph
(ph/f only; ISBE soof at https://classic.net.bible.org/dictionary.php?word=Suph),
and Agag/a gag (identical letters and syllables, only ASR word spacing).
Aphah, Suphah and Hagag remain mismatches. Raw transcripts are retained.

Version 50 extends pastureland spacing to plural pasturelands/pasture lands.
The plural ending remains required; pastureland/pasturelands still differs.

Version 51 includes singular grainfield/grain field compound spacing, alongside
the existing plural form. Grainfield/grainfields remains a mismatch.

Version 52 accepts British favoured alongside American favored, preserving the
past-tense ending; favour/favoured remains a mismatch.

Version 53 corrects the earlier foreman/foremen negative control after consulting
primary dictionary pronunciation entries. Cambridge gives both UK /ˈfɔː.mən/
and US /ˈfɔːr.mən/ for both forms:
https://dictionary.cambridge.org/pronunciation/english/foreman
https://dictionary.cambridge.org/us/pronunciation/english/foremen
This is an explicit audible homophone exception, like their/there; canonical
source text and its plural remain unchanged. Magician/magicians and other
audibly different number endings still fail. This supersedes the earlier
foremen/foreman rejection; no transcript words are edited.


### 2026-10-30: unsown/unsewn (normalization 54)

Deuteronomy 29 produced the transcript “unsewn” for canonical “unsown”.
The sown/sewn bases share /soʊn/ according to Cambridge; the identical
un- prefix does not change that homophony. Normalize only this pair, retaining
the canonical source and raw recognizer output. Tests still reject omitted
un- and changed vowels (unseen).

References: https://dictionary.cambridge.org/pronunciation/english/sown and
https://dictionary.cambridge.org/pronunciation/english/sewn


### 2026-10-30: spacing and established variants (normalization 55)

Normalize the standard British/American sulphur/sulfur spelling pair and
the identical spoken segmentation a count/account. The latter retains
the article token, with a negative test for its omission.
Zeboim is an explicitly documented English spelling of Zeboiim (Strong H6636
and ISBE); only that alias is accepted, not the changed vowel Ziboim.
Canonical BSB text and unedited recognition evidence are retained.

References: https://biblehub.com/strongs/hebrew/6636.htm and
https://biblehub.com/topical/z/zeboiim.htm


### 2026-10-30: bounded phonetic spelling aliases (normalization 56)

Cozbi/Kozbi and the recognizer's Cosby share the documented koz-bi
pronunciation (ISBE; Cambridge UK /kɒz.bi/). Ammiel/Amiel retains
ISBE am-i-el with no extra spoken consonant for the doubled m.
Hepher/Hefer and Hupham/Hufam retain ISBE he-fer and hu-fam;
clan -ite endings remain required. Riblah/Ribla and Suphah/Supha/Sufa
retain the documented rib-la and soo-fa endings.
The phonetic ASR spelling unsandled retains the standard sandaled
pronunciation (Webster 1924 gives sandaled as san'dld); it does not
permit unsaddled or unsanded. All aliases are explicitly enumerated,
with negative controls for changed sounds and missing suffixes.
Raw ASR, source spelling, and audio hashes remain unedited.

References:
- https://biblehub.com/topical/c/cozbi.htm
- https://dictionary.cambridge.org/pronunciation/english/cosby
- https://biblehub.com/topical/a/ammiel.htm
- https://biblehub.com/topical/h/hepher.htm
- https://biblehub.com/topical/h/hupham.htm
- https://biblehub.com/topical/r/riblah.htm
- https://biblehub.com/topical/s/suphah.htm
- https://truthbook.com/urantia-book-viewer-core/1924-Websters-Dictionary-Edition/LETTER-S.pdf


### 2026-10-30: Aroer and exact name segmentation (normalization 57)

ISBE gives Aroer as a-ro'-er, matching the audible segmentation
“a rower”; Strong H6177 explicitly also lists Aror as a form of this
same place-name. Preserve the leading syllable and reject bare rower.
Ahiezer/Ahi ezer and Deuel/Deu el split the identical letters into
recognizer tokens without removing any syllable. Tests retain the
distinct Abiezer and the altered Deweel vowel.

References: https://biblehub.com/topical/a/aroer.htm and
https://biblehub.com/hebrew/6177.htm


### 2026-10-30: explicit consonant spelling aliases (normalization 58)

Recognize enumerated ph/f spellings in Eliasaph, Elizaphan, Shepher,
Vophsi, Shupham and Shuphamite, retaining the /f/ sound and clan suffix.
Hanoch/Hanok and Hanochite/Hanokite retain ISBE ha-nok and ha-nok-its.
Rabbah/Rabba/Rabah retains rab-a (silent terminal h and consonant doubling).
Aroer's a-ro-er segmentation can be written a roer as well as a rower.
Tests still reject changed vowels, p for f, Shepherd, and dropped suffixes.

References:
- https://biblehub.com/topical/e/eliasaph.htm
- https://biblehub.com/topical/e/elizaphan.htm
- https://biblehub.com/topical/s/shepher.htm
- https://biblehub.com/topical/v/vophsi.htm
- https://classic.net.bible.org/dictionary.php/xml/dictionary.php?word=SHEPHUPHAM
- https://biblehub.com/topical/h/hanoch.htm
- https://biblehub.com/topical/r/rabbah.htm
- https://biblehub.com/topical/a/aroer.htm

Normalization 59 also recognizes `Sufah` as the same /soo-fa/ phonetic
spelling already covered by `Sufa` and `Supha`. Final h is silent; this adds
no vowel or syllable equivalence. The Suph/Suphah negative control remains.
Reference: https://biblehub.com/topical/s/suphah.htm

Normalization 60 handles the recognizer splitting `Eleazar` as `El eazar`.
This only removes a token boundary inside the identical letters. It does not
permit `Eliezer` or `El iyazar`, and raw recognized text/timestamps remain saved.

Normalization 61 recognizes two documented traditional English name forms:
`Elisaphan` / `Elizaphan` (Numbers 3:30) and `Elisur` / `Elizur` (Numbers 1:5).
The Challoner Douay-Rheims primary text publishes the s spellings:
https://sacredbible.org/challoner/OT-04_Numbers.htm
The BSB source and generation text remain unchanged. These are explicitly
bounded English proper-name variants, not a general s/z substitution and not
a claim that all historical pronunciations are identical. Raw recognition
remains in each receipt. Eliezer, Eleazar, Elisir, Elisor, Elisaphon, Elishaphan,
and syllable-shortened Elzaphan remain distinct in the negative controls.

Normalization 62 fixes cardinal-number formatting: `a hundred and thirty`,
`one hundred thirty`, and ASR-formatted `130` represent the same numeric value.
Only `a` immediately before singular hundred/thousand/million/billion becomes
`one`; arbitrary article substitutions, omitted magnitudes, different amounts,
and ordinal articles remain distinct. The same bounded rule preserves the
original interval in word timestamps. This corrects an earlier false flag
caused by expanding recognizer digits to `one` while leaving source `a` intact.
Primary language reference: https://dictionary.cambridge.org/grammar/british-grammar/number

### Audited quiet-only edits

`bible_audio_quiet_edit.py` certifies silence removal from an already
independently recognized recording. It is explicitly **not a fresh transcript**
of the edited file. The raw parent transcript is inherited whole, with the
parent audio and check files bound by hashes; no transcript words are edited or
combined. Every output PCM sample must equal the specified deletion/fade
transformation. All deleted and fade-modified samples must be below RMS 0.001
and peak 0.006; entire recognized word intervals may not be removed. Timestamp
intervals are shifted/clamped through the documented cut. Both final audit and
publication revalidate the proof, and the receipt identifies the parent
recognition-audio hash separately from the current audio hash.

This addresses recognizer formatting/spelling drift after a quiet-only edit
without claiming fresh ASR succeeded. Fresh failed recognition attempts remain
preserved. The certificate establishes sample preservation, not a human
listening review. Tests reject changed speech even with an updated output hash,
speech deletion, and transcript changes, and verify the timing shift.
