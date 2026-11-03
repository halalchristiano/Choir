#!/usr/bin/env python3
"""Back-transcribe saved passages and retain word timestamps for verse cues.

Initial passes use no prompt. Optional isolated name and term spelling hints are recorded
and must never contain the passage text. Differences are reported for review;
an ASR match is not a human assessment of likeness or pronunciation.
"""
import argparse
import difflib
import hashlib
import json
import math
import re
import time
import wave
from pathlib import Path

import mlx.core as mx
import mlx_whisper
import numpy as np
from scipy.signal import resample_poly

NORMALIZATION_VERSION = 75
# Preserve across watcher reloads. The final publication audit independently
# hashes every file; this avoids rereading the entire book on every live scan.
_AUDIO_DIGEST_CACHE = globals().get('_AUDIO_DIGEST_CACHE', {})


def audio_digest(path):
    def identity():
        stat = path.stat()
        return (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
    before = identity()
    cached = _AUDIO_DIGEST_CACHE.get(path)
    if cached and cached[0] == before:
        return cached[1]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    assert before == identity(), 'Recording changed during verification: '+str(path)
    _AUDIO_DIGEST_CACHE[path] = (before, digest)
    return digest


def number_words(n):
    small = 'zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen'.split()
    tens = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety']
    if n < 20:
        return small[n]
    if n < 100:
        return tens[n//10]+(' '+small[n%10] if n%10 else '')
    for value, name in [(1000000000, 'billion'), (1000000, 'million'), (1000, 'thousand'), (100, 'hundred')]:
        if n >= value:
            return number_words(n//value)+' '+name+(' '+number_words(n%value) if n%value else '')


def words(text):
    # Numerals and their spoken English form represent the same source words.
    text = re.sub(r'\b(\d[\d,]*)(?:st|nd|rd|th)\b', lambda m: ordinal_words(int(m[1].replace(',', ''))), text, flags=re.IGNORECASE)
    text = re.sub(r'\b\d[\d,]*\b', lambda m: number_words(int(m[0].replace(',', ''))), text)
    # English permits "one hundred and twenty" for the same number as 120.
    # Only the conjunction inside a number is optional; other words stay exact.
    number_tail = 'zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth|thirteenth|fourteenth|fifteenth|sixteenth|seventeenth|eighteenth|nineteenth|twentieth|thirtieth|fortieth|fiftieth|sixtieth|seventieth|eightieth|ninetieth'
    text = re.sub(r'\b(hundred|thousand|million|billion)\s+and\s+(?=(?:'+number_tail+r')\b)', r'\1 ', text, flags=re.IGNORECASE)
    tokens = re.findall(r"[a-z0-9]+(?:'[a-z]+)?", text.lower().replace('’', "'"))
    # Cardinal articles denote one, including punctuation-separated readings.
    tokens = ['one' if token == 'a' and i+1 < len(tokens) and tokens[i+1] in ('hundred', 'thousand', 'million', 'billion') else token for i,token in enumerate(tokens)]
    # A possessive apostrophe does not change the spoken final s.
    tokens = [token[:-2]+'s' if token.endswith("'s") else token for token in tokens]
    # Audible spelling equivalents only. These do not waive missing words or
    # different readings. Raw transcripts remain in every verification record.
    # Epaenetus/Epenetus are published spellings of the same name (Strong G1866).
    # Aminadab/Amminadab: the same name, Strong G284 (biblehub.com/greek/284.htm).
    # Orthographic doubling and a syllable-separating apostrophe only;
    # retain vowel changes, extra syllables, and distinct neighboring names.
    # Maath syllable separator follows Strong G3092 mah-ath, not Maathah.
    spelling = {"ma'ath": ['maath'], 'travelling': ['traveling'],
                # Regional spellings and ASR spacing; no source word is omitted.
                # Cambridge /dictionary/english/travelled; Collins /dictionary/english/brier.
                'travelled': ['traveled'], 'briar': ['brier'], 'briars': ['briers'],
                'tonight': ['to', 'night'], 'hometown': ['home', 'town'],
                'everyones': ['every', 'ones'],
                # Ordinary compounds: preserve every letter, including plurals.
                # A recognizer's inserted space is not a changed spoken word.
                'oxgoad': ['ox', 'goad'], 'chainwork': ['chain', 'work'],
                'guardroom': ['guard', 'room'], 'baldhead': ['bald', 'head'],
                'anymore': ['any', 'more'], 'stonecutter': ['stone', 'cutter'],
                'stonecutters': ['stone', 'cutters'], 'showbread': ['show', 'bread'],
                'wingspan': ['wing', 'span'], 'hindquarters': ['hind', 'quarters'],
                'courtyard': ['court', 'yard'],
                # Attested source compounds with spacing-only ASR differences.
                # Keep all components and endings; no general word-joining rule.
                'vinedressers': ['vine', 'dressers'], 'reentered': ['re', 'entered'],
                'winepress': ['wine', 'press'], 'winepresses': ['wine', 'presses'],
                'todays': ['to', 'days'], 'sheepdogs': ['sheep', 'dogs'],
                'faultfinder': ['fault', 'finder'], 'simplehearted': ['simple', 'hearted'],
                'thornbush': ['thorn', 'bush'], 'firepot': ['fire', 'pot'],
                'lampstands': ['lamp', 'stands'], 'cutstones': ['cut', 'stones'],
                'underfoot': ['under', 'foot'], 'mountaintops': ['mountain', 'tops'],
                'wheelwork': ['wheel', 'work'], 'wasteland': ['waste', 'land'],
                'marketplace': ['market', 'place'],
                # Observed name/compound spacing preserves every source letter.
                # Keep missing components and changed vowels distinct.
                'bethshemesh': ['beth', 'shemesh'], 'elteke': ['el', 'teke'],
                'lodebar': ['lo', 'debar'], 'almugwood': ['almug', 'wood'],
                'geharashim': ['ge', 'harashim'], 'eshbaal': ['esh', 'baal'],
                # Cambridge /dictionary/english/skilful: UK spelling of skillful.
                'skilful': ['skillful'],
                # Poetry-heading compounds: retain all parts, including "more".
                'choirmaster': ['choir', 'master'],
                'forevermore': ['for', 'ever', 'more'], 'evermore': ['ever', 'more'],
                # Cambridge's savior, valor and honor entries document these
                # British spellings. Preserve the plural/verb ending in honours.
                'saviour': ['savior'], 'valour': ['valor'], 'honours': ['honors'],
                # Documented name spellings / English consonant spelling only.
                # biblehub.com/hebrew/5915.htm explicitly lists Aksah.
                # NET Bible dictionary Achshaph: Akshaph; Helkath: hel-kath.
                # Adult Bible Studies pronunciation guide: Tappuah, Tah-POO-uh.
                'aksah': ['acsah'], 'akshaph': ['achshaph'],
                'helcath': ['helkath'], 'tapuah': ['tappuah'],
                # Merriam-Webster lists the same pronunciations for your/you're
                # and cor/core. Keep "you are" and singular/plural distinct.
                "you're": ['your'], 'core': ['cor'], 'cores': ['cors'],
                # Strong H7935 lists Shecaniah/Shechaniah with a k sound;
                # H5761 explicitly gives Avim as the KJV form of Avvim.
                'shekaniah': ['shecaniah'], 'shechaniah': ['shecaniah'],
                'avim': ['avvim'],
                # Explicit KJV/NASB forms of the same names, not a general
                # consonant-deduplication rule: Strong H5757, H5755, H2536;
                # Bible Gateway Encyclopedia of the Bible, Shenazzar.
                'avites': ['avvites'], 'ivah': ['ivvah'],
                'hamuel': ['hammuel'], 'shenazar': ['shenazzar'],
                # Explicit English name evidence, not generic consonant folding.
                # Bible Gateway Encyclopedia gives Amon and Ammon the identical
                # pronunciation am-uhn; Zebah is Zee-buh (silent final h).
                # NET ISBE Zuph: zuf; Strong H4441: Malchiah/Malchijah/Malkijah.
                'ammon': ['amon'], 'zeba': ['zebah'], 'zuf': ['zuph'],
                'malchiah': ['malchijah'], 'malkijah': ['malchijah'],
                # Named, sourced English orthography only. Bible Gateway:
                # Isshiah explicitly has KJV Ishiah; Giloh has RSV Gilo;
                # Libnah is lib-nuh; Achbor is ak-bor. NET ISBE gives
                # Joiarib joi-a-rib and Zattu zat-u. No generic letter removal.
                'ishiah': ['isshiah'], 'gilo': ['giloh'], 'libna': ['libnah'],
                'akbor': ['achbor'], 'joyarib': ['joiarib'], 'zatu': ['zattu'],
                # Merriam-Webster: adviser/advisor are spelling variants;
                # council/counsel have the same published pronunciation.
                'advisors': ['advisers'], 'council': ['counsel'],
                # Bible Gateway: Asaph ends in f; Bukki has one k sound;
                # Timna explicitly has KJV Timnah; Neco has KJV Necho/Nechoh.
                # Keep the audible s in possessive forms.
                'asaf': ['asaph'], 'buki': ['bukki'], 'timna': ['timnah'],
                'necho': ['neco'], 'nechoh': ['neco'],
                'nechos': ['necos'], 'nechohs': ['necos'],
                # Named English orthography, not generic letter folding.
                # NET ISBE: Akkub ak-ub; Naharai/Nahari both na-ha-ri;
                # Hodevah ho-de-va. Strong H6583 explicitly lists Pashur.
                # Bible Gateway: Mattaniah mat-a-ni-a, Meshullam mi-shool-am,
                # Dumah doo-ma; Alemeth has KJV Alameth and ASV Allemeth.
                'akub': ['akkub'], 'mataniah': ['mattaniah'],
                'meshulam': ['meshullam'], 'nahari': ['naharai'],
                'hodeva': ['hodevah'], 'duma': ['dumah'], 'pashur': ['pashhur'],
                'alameth': ['alemeth'], 'allemeth': ['alemeth'],
                # NET ISBE: Mattan mat-an, Gazzam gaz-am, Ziha zi-ha;
                # Bible Gateway: Iddo id-oh. Named English consonant/final-h
                # spelling only; never remove consonants from arbitrary names.
                # NET Hasshub explicitly identifies KJV Hashub, hash-ub.
                'matan': ['mattan'], 'gazam': ['gazzam'], 'zihah': ['ziha'],
                'ido': ['iddo'], 'hashub': ['hasshub'],
                # Merriam-Webster Nazarite is a variant of Nazirite; keep plural.
                # Sidewall is a compound; retain both words and their ending.
                'nazarites': ['nazirites'], 'sidewall': ['side', 'wall'],
                'sidewalls': ['side', 'walls'],
                'foreseeing': ['for', 'seeing'], 'their': ['there'],
                # ISBE English name forms: sir-tis, re-ji-um, nik-o-las.
                'sirtis': ['syrtis'], 'regium': ['rhegium'], 'nicholas': ['nicolas'],
                # Smith/ISBE Cnidus: nidus, ni-dus (silent initial c).
                'nidus': ['cnidus'],
                # ISBE Aenon e-non; Mnason na-son; Akeldama a-kel-da-ma.
                'enon': ['aenon'], 'nason': ['mnason'], 'akeldama': ['a', 'keldama'],
                # ISBE syllables man-a-en and mit-i-le-ne; preserve vowel/syllable errors.
                'manaen': ['man', 'a', 'en'], 'mitylene': ['miti', 'lini'],
                'mitilini': ['miti', 'lini'], 'mytilene': ['miti', 'lini'],
                'galio': ['gallio'], 'atalia': ['attalia'], 'chusa': ['chuza'], 'forever': ['for', 'ever'],
                'joannan': ['joanan'], "mele'ah": ['melea'], 'meleah': ['melea'],
                'worshipping': ['worshiping'], 'worshippers': ['worshipers'],
                'tentmakers': ['tent', 'makers'], 'longstanding': ['long', 'standing'],
                # Compound spacing in ASR does not change the spoken words.
                'birthstools': ['birth', 'stools'], 'birthstool': ['birth', 'stool'],
                'riverbank': ['river', 'bank'], 'riverbanks': ['river', 'banks'],
                'maidservant': ['maid', 'servant'], 'maidservants': ['maid', 'servants'],
                'today': ['to', 'day'],
                'tomorrow': ['to', 'morrow'], 'someone': ['some', 'one'], 'anyone': ['any', 'one'],
                'doorframe': ['door', 'frame'], 'doorframes': ['door', 'frames'],
                'workload': ['work', 'load'], 'flintknife': ['flint', 'knife'], 'handmill': ['hand', 'mill'],
                'marvellous': ['marvelous'], 'favour': ['favor'], 'favoured': ['favored'], 'honour': ['honor'],
                'neighbour': ['neighbor'], 'neighbours': ['neighbors'],
                'moulding': ['molding'], 'skilfully': ['skillfully'], 'totalled': ['totaled'],
                'fulfil': ['fulfill'], 'jewellery': ['jewelry'], 'chiselled': ['chiseled'],
                'splendour': ['splendor'], 'quarrelled': ['quarreled'],
                'quarrelling': ['quarreling'], 'wilfully': ['willfully'], 'labour': ['labor'],
                'lampstand': ['lamp', 'stand'], 'everyone': ['every', 'one'],
                'ramskins': ['ram', 'skins'], 'breastpiece': ['breast', 'piece'],
                'manservant': ['man', 'servant'], 'menservants': ['men', 'servants'],
                'crossbar': ['cross', 'bar'], 'crossbars': ['cross', 'bars'],
                'firstfruits': ['first', 'fruits'], 'handbreadth': ['hand', 'breadth'],
                'halfway': ['half', 'way'], 'freewill': ['free', 'will'],
                'mountaintop': ['mountain', 'top'], 'livestock': ['live', 'stock'],
                'cordwork': ['cord', 'work'], 'doorpost': ['door', 'post'],
                'earlobes': ['ear', 'lobes'], 'headbands': ['head', 'bands'],
                'earlobe': ['ear', 'lobe'], 'reexamine': ['re', 'examine'],
                'reexamines': ['re', 'examines'], 'reenter': ['re', 'enter'],
                'anything': ['any', 'thing'], 'windblown': ['wind', 'blown'],
                'crossbreed': ['cross', 'breed'], 'bloodguilt': ['blood', 'guilt'],
                'pastureland': ['pasture', 'land'], 'pasturelands': ['pasture', 'lands'], 'someones': ['some', 'ones'],
                'practise': ['practice'], 'practised': ['practiced'], 'fulfilment': ['fulfillment'],
                # Cambridge gives identical UK/US pronunciations for foreman/foremen.
                'aroer': ['a', 'rower'], 'aror': ['a', 'rower'],
                'ahiezer': ['ahi', 'ezer'], 'deuel': ['deu', 'el'], 'eleazar': ['el', 'eazar'],
                'rabba': ['rabbah'], 'rabah': ['rabbah'], 'roer': ['rower'],
                'eliasaf': ['eliasaph'], 'elizafan': ['elizaphan'], 'elisaphan': ['elizaphan'], 'elisur': ['elizur'], 'shefer': ['shepher'],
                'vofsi': ['vophsi'], 'shufam': ['shupham'], 'shufamite': ['shuphamite'],
                'hanok': ['hanoch'], 'hanokite': ['hanochite'],
                'cosby': ['cozbi'], 'kozbi': ['cozbi'], 'amiel': ['ammiel'],
                'hefer': ['hepher'], 'heferite': ['hepherite'],
                'hufam': ['hupham'], 'hufamite': ['huphamite'],
                'ribla': ['riblah'], 'supha': ['suphah'], 'sufa': ['suphah'], 'sufah': ['suphah'],
                'unsandled': ['unsandaled'],
                'sulphur': ['sulfur'], 'zeboim': ['zeboiim'], 'account': ['a', 'count'],
                'unsewn': ['unsown'], 'foreman': ['foremen'], 'vale': ['veil'], 'mail': ['male'], 'gilt': ['guilt'], 'waived': ['waved'],
                # Strong H8236 shif-raw: ph/f and silent final h only.
                'shifra': ['shiphrah'],
                # Preserve every letter; only ASR space/hyphen segmentation differs.
                'pihahiroth': ['pi', 'hahiroth'], 'ahisamach': ['ahi', 'samach'],
                # Published name forms, Strong H7486 / H171; not arbitrary vowel substitutions.
                'ramesses': ['rameses'], 'aholiab': ['oholiab'],
                # Attested sounds: Uzziel oo-zee-el, Pallu pal-loo,
                # Hanoch ha-nok; gerah geh-raw with a plural s.
                'uziel': ['uzziel'], 'palu': ['pallu'], 'hannock': ['hanoch'], 'geras': ['gerahs'],
                # ISBE na-shon / fin-e-as; Strong H617 ah-seer.
                'nashon': ['nahshon'], 'phineas': ['phinehas'], 'asir': ['assir'],
                'firepans': ['fire', 'pans'],
                'firstborn': ['first', 'born'], 'stillborn': ['still', 'born'],
                'amishadai': ['ammishaddai'], 'zurishadai': ['zurishaddai'],
                'amihud': ['ammihud'], 'shamua': ['shammua'], 'uzielites': ['uzzielites'],
                # Published spellings / English pronunciations; preserve changed vowels and syllables.
                'okran': ['ocran'], 'eshkol': ['eshcol'], 'nazarite': ['nazirite'],
                'mali': ['mahli'], 'malites': ['mahlites'],
                # Strong H2147 explicitly transliterates Zichri as Zikri / Zicri.
                'zikri': ['zichri'], 'zicri': ['zichri'],
                # Silent final h / ph-f spelling, and unchanged-letter segmentation.
                'epha': ['ephah'], 'suf': ['suph'], 'agag': ['a', 'gag'],
                'aminadab': ['amminadab'],
                'turtledoves': ['turtle', 'doves'], 'thornbushes': ['thorn', 'bushes'],
                'onto': ['on', 'to'], 'sun': ['son'],
                'epaenetus': ['epenetus'], 'rights': ['rites'], 'rebekahs': ['rebeccas'],
                'awhile': ['a', 'while'], 'yokefellow': ['yoke', 'fellow'],
                'fainthearted': ['faint', 'hearted'],
                'grainfield': ['grain', 'field'], 'grainfields': ['grain', 'fields'], 'thaddeus': ['thaddaeus'],
                'team': ['teem'], 'teamed': ['teemed'], 'arc': ['ark'], 'seedtime': ['seed', 'time'],
                'turtledove': ['turtle', 'dove'], 'facedown': ['face', 'down'], 'borne': ['born'],
                'o': ['oh'], 'adah': ['ada'], 'admah': ['adma'], 'arioch': ['ariok'],
                'casluhites': ['kasluhites'], 'caphtorites': ['kaphtorites'],
                'rodanites': ['rhodanites'], 'goiim': ['goyim'],
                'bowshot': ['bow', 'shot'], 'sometime': ['some', 'time'],
                'worshipped': ['worshiped'], 'rebekah': ['rebecca'], 'advisor': ['adviser'],
                'asshur': ['ashur'], 'asshurites': ['ashurites'], 'plain': ['plane'], 'benoni': ['ben', 'oni'],
                'sheepshearers': ['sheep', 'shearers'], 'hirah': ['hira'],
                'malchiel': ['malkiel'], 'potipherah': ['potiphera'], 'puvah': ['puva'],
                'laughingstock': ['laughing', 'stock'], 'ammy': ['ammi'],
                # The same name/transliteration, Strong's H7484 (rah-maw):
                # https://biblehub.com/hebrew/7484.htm
                'raamah': ['ramah'], 'rama': ['ramah'],
                # Silent final h and alternative spelling of the same spoken name.
                'shuah': ['shua'], 'anah': ['ana'], 'zibion': ['zibeon'],
                # ASR may transcribe the three audible syllables of Beeri separately.
                # ISBE be-e'-ri: https://classic.net.bible.org/dictionary.php?word=Beeri
                'beeri': ['be', 'eh', 'ree'],
                # Standard spelling variants with identical spoken form.
                'impostors': ['imposters'],
                # ASR spellings of the attested jan'-ez, jam'-brez and
                # o-ne-sif'-o-rus pronunciations; distinct names remain distinct.
                # https://www.biblegateway.com/resources/encyclopedia-of-the-bible/Jannes-Jambres
                # https://classic.net.bible.org/dictionary.php?word=Onesiphorus
                'jannez': ['jannes'], 'jambrez': ['jambres'],
                'onisiphorus': ['onesiphorus']}
    return [part for token in tokens for part in spelling.get(token, [token])]


def ordinal_words(n):
    parts = number_words(n).split()
    last = parts[-1]
    irregular = dict(one='first', two='second', three='third', five='fifth', eight='eighth', nine='ninth', twelve='twelfth')
    parts[-1] = irregular.get(last, last[:-1]+'ieth' if last.endswith('y') else last+'th')
    return ' '.join(parts)


def differences(expected, recognized):
    expected_words, actual_words = words(expected), words(recognized)
    changes = []
    for tag, a, b, c, d in difflib.SequenceMatcher(None, expected_words, actual_words, autojunk=False).get_opcodes():
        if tag != 'equal':
            changes.append(dict(type=tag, expected=' '.join(expected_words[a:b]), recognized=' '.join(actual_words[c:d]),
                expected_span=[a,b], recognized_span=[c,d]))
    return changes


def timed_words(word_times):
    """Keep timestamps while removing only optional conjunctions inside numbers."""
    merged = []
    for item in word_times:
        # Whisper may tokenize 23,000 as "23" and ",000". Rejoin only
        # numeric continuation tokens, retaining the complete time interval.
        if merged and re.search(r'\d$', merged[-1]['word'].strip()) and re.fullmatch(r'\s*,\d{3}(?:,\d{3})*[.!?;:,\u2019\u201d]*\s*', item['word']):
            merged[-1]['word'] += item['word'].strip()
            merged[-1]['end'] = item['end']
        else:
            merged.append(dict(item))
    word_times = merged
    flattened = [(token, item['start'], item['end']) for item in word_times for token in words(item['word'])]
    # Apply the same bounded cardinal-article rule across timestamp tokens.
    flattened = [('one', start, end) if token == 'a' and i+1 < len(flattened) and flattened[i+1][0] in ('hundred', 'thousand', 'million', 'billion') else (token, start, end) for i,(token,start,end) in enumerate(flattened)]
    target = words(' '.join(item['word'] for item in word_times))
    result = []
    position = 0
    for index, item in enumerate(flattened):
        if position < len(target) and item[0] == target[position]:
            result.append(item)
            position += 1
        else:
            assert item[0] == 'and' and index > 0 and flattened[index-1][0] in ('hundred', 'thousand', 'million', 'billion'), 'Unexpected word-timestamp normalization'
    assert position == len(target), 'Word timestamps do not cover the normalized transcript'
    return result


def write_json(path, data):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
    temporary.replace(path)


def window_spelling_contexts(args, count):
    hints = getattr(args, 'window_name_contexts', None)
    if hints is None:
        return [args.name_context] * count
    assert args.split_at and args.name_context is None, 'Window hints need explicit windows and no global prompt'
    assert isinstance(hints, list) and len(hints) == count, 'Each complete audio window needs its own hint entry'
    contexts = []
    for names in hints:
        if names is None:
            contexts.append(None)
            continue
        assert isinstance(names, list) and len(names) <= 12
        assert all(isinstance(name, str) and re.fullmatch(r"[A-Za-z]+(?:[-’'][A-Za-z]+)*", name) for name in names), 'Use isolated name spellings, never sentence text'
        assert names == sorted(names, key=str.casefold) and len({name.casefold() for name in names}) == len(names), 'Name hints must be unique and alphabetized'
        contexts.append(', '.join(names) or None)
    return contexts


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('--limit', type=int)
    parser.add_argument('--chapter')
    parser.add_argument('--books', nargs='+', help='Restrict verification to these book names.')
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--recheck', nargs='+')
    parser.add_argument('--temperature', type=float, default=0.)
    parser.add_argument('--model-path', type=Path, help='Pinned local recognition model for an independent second opinion.')
    parser.add_argument('--recognizer-id', help='Exact repository and revision corresponding to --model-path.')
    parser.add_argument('--name-context', help='Isolated name or term spelling hints only; never supply the passage text.')
    parser.add_argument('--split-at', type=float, nargs='+', help='Recheck one passage in independent time windows when recognition stops early; does not edit the recording.')
    parser.add_argument('--window-name-contexts', type=Path, help='JSON lists of at most 12 alphabetized isolated names per complete time window; no sentence text.')
    args = parser.parse_args()
    assert bool(args.model_path) == bool(args.recognizer_id), 'A custom recognizer requires both its local path and pinned identity'
    if args.split_at:
        assert args.recheck and len(args.recheck) == 1, 'Time-window rechecks require exactly one passage'
    if args.window_name_contexts:
        args.window_name_contexts = json.loads(args.window_name_contexts.read_text())
        window_spelling_contexts(args, len(args.split_at or []) + 1)
    root = args.root.resolve()
    directory = root/'gospels-v1'
    source = json.loads((directory/'source.json').read_text())
    model = args.model_path or root/'cache/huggingface/hub/models--mlx-community--whisper-large-v3-turbo/snapshots/a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb'
    args.recognizer_id = args.recognizer_id or 'mlx-community/whisper-large-v3-turbo@a4aaeec0636e6fef84abdcbe3544cb2bf7e9f6fb'
    while True:
        scan(args, directory, source, model)
        audits = [json.loads(path.read_text()) for path in (directory/'chapters').glob('*/passages/*.check.json')]
        issues = [dict(id=audit['id'],changes=audit['changes']) for audit in audits if not audit['automatic_exact_match']]
        write_json(directory/'verification-progress.json', dict(checked=len(audits), exact_matches=len(audits)-len(issues), issues=issues))
        expected = sum(len(chapter['chunks']) for chapter in source['chapters']
            if (not args.books or chapter['book'] in args.books)
            and (not args.chapter or chapter['id'] == args.chapter))
        relevant = [audit for audit in audits if any(audit['id'].startswith(chapter['id']+'-')
            for chapter in source['chapters'] if (not args.books or chapter['book'] in args.books)
            and (not args.chapter or chapter['id'] == args.chapter))]
        if not args.watch or len(relevant) == expected:
            return
        time.sleep(20)


def scan(args, directory, source, model):
    checked = 0
    started = time.time()
    for chapter in source['chapters']:
        if args.books and chapter['book'] not in args.books:
            continue
        if args.chapter and chapter['id'] != args.chapter:
            continue
        for chunk in chapter['chunks']:
            identity = f'{chapter["id"]}-{chunk["index"]:03d}'
            if args.recheck and identity not in args.recheck:
                continue
            path = directory/'chapters'/chapter['id']/'passages'/f'{chunk["index"]:03d}.wav'
            if not path.exists() or not path.with_suffix('.json').exists():
                continue
            digest = audio_digest(path)
            audit = path.with_suffix('.check.json')
            if audit.exists():
                old = json.loads(audit.read_text())
                if old['sha256'] == digest and not args.recheck:
                    if old.get('normalization_version') != NORMALIZATION_VERSION:
                        old['earlier_normalization_changes'] = old['changes']
                        old['changes'] = differences(old['expected'], old['recognized'])
                        old['automatic_exact_match'] = not old['changes']
                        old['words'] = len(words(old['expected']))
                        old['normalization_version'] = NORMALIZATION_VERSION
                        write_json(audit, old)
                    continue
                if args.recheck:
                    archive = audit.with_name(audit.stem+f'.prior-{time.time_ns()}.json')
                    archive.write_bytes(audit.read_bytes())
            with path.open('rb') as handle:
                with wave.open(handle) as reader:
                    rate = reader.getframerate()
                    assert reader.getnchannels() == 1 and reader.getsampwidth() == 2
                    wav = np.frombuffer(reader.readframes(reader.getnframes()), dtype='<i2').astype(np.float32)/32768
            assert np.isfinite(wav).all()
            divisor = math.gcd(rate, 16000)
            audio = resample_poly(wav, 16000//divisor, rate//divisor).astype(np.float32)
            boundaries = [0.] + (args.split_at or []) + [len(audio)/16000]
            assert all(a < b for a,b in zip(boundaries,boundaries[1:]))
            contexts = window_spelling_contexts(args, len(boundaries) - 1)
            recognized_parts, word_times = [], []
            for start,end,context in zip(boundaries,boundaries[1:],contexts):
                transcript = mlx_whisper.transcribe(audio[round(start*16000):round(end*16000)], path_or_hf_repo=str(model), language='en',
                    temperature=args.temperature, condition_on_previous_text=False, word_timestamps=True, verbose=None,
                    initial_prompt=context, no_speech_threshold=None)
                recognized_parts.append(transcript['text'].strip())
                for segment in transcript['segments']:
                    for word in segment.get('words', []):
                        word_times.append(dict(word, start=word['start']+start, end=word['end']+start))
            recognized = ' '.join(recognized_parts)
            expected_words = words(chunk['text'])
            changes = differences(chunk['text'], recognized)
            result = dict(id=f'{chapter["id"]}-{chunk["index"]:03d}', sha256=digest,
                expected=chunk['text'], recognized=recognized, changes=changes, words=len(expected_words),
                seconds=len(wav)/rate, peak=float(np.abs(wav).max()), rms=float(np.sqrt(np.mean(wav**2))),
                clipped_fraction=float(np.mean(np.abs(wav)>=.999)), word_times=word_times,
                automatic_exact_match=not changes, human_listening_review_completed=False, normalization_version=NORMALIZATION_VERSION,
                recognizer=args.recognizer_id,
                recognition_temperature=args.temperature, proper_name_context=args.name_context, recognition_window_boundaries=boundaries)
            if getattr(args, 'window_name_contexts', None) is not None:
                result['recognition_window_spelling_hints'] = args.window_name_contexts
            write_json(audit, result)
            checked += 1
            print(json.dumps(dict(id=result['id'], changes=changes, seconds=result['seconds'],
                elapsed=round(time.time()-started,1)), ensure_ascii=False),flush=True)
            mx.clear_cache()
            if args.limit and checked >= args.limit:
                return
    print(f'CHECK_COMPLETE {checked} newly checked passages in {time.time()-started:.1f}s',flush=True)


if __name__ == '__main__':
    main()
