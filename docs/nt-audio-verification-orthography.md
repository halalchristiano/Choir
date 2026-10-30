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
