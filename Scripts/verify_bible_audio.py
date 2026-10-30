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

NORMALIZATION_VERSION = 31
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
    # A possessive apostrophe does not change the spoken final s.
    tokens = [token[:-2]+'s' if token.endswith("'s") else token for token in tokens]
    # Audible spelling equivalents only. These do not waive missing words or
    # different readings. Raw transcripts remain in every verification record.
    # Epaenetus/Epenetus are published spellings of the same name (Strong G1866).
    # Aminadab/Amminadab: the same name, Strong G284 (biblehub.com/greek/284.htm).
    # Orthographic doubling and a syllable-separating apostrophe only;
    # retain vowel changes, extra syllables, and distinct neighboring names.
    spelling = {'joannan': ['joanan'], "mele'ah": ['melea'], 'meleah': ['melea'],
                'worshipping': ['worshiping'], 'worshippers': ['worshipers'],
                'tentmakers': ['tent', 'makers'], 'longstanding': ['long', 'standing'],
                'aminadab': ['amminadab'],
                'turtledoves': ['turtle', 'doves'], 'thornbushes': ['thorn', 'bushes'],
                'onto': ['on', 'to'], 'sun': ['son'],
                'epaenetus': ['epenetus'], 'rights': ['rites'], 'rebekahs': ['rebeccas'],
                'awhile': ['a', 'while'], 'yokefellow': ['yoke', 'fellow'],
                'fainthearted': ['faint', 'hearted'],
                'grainfields': ['grain', 'fields'], 'thaddeus': ['thaddaeus'],
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
    args = parser.parse_args()
    assert bool(args.model_path) == bool(args.recognizer_id), 'A custom recognizer requires both its local path and pinned identity'
    if args.split_at:
        assert args.recheck and len(args.recheck) == 1, 'Time-window rechecks require exactly one passage'
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
            recognized_parts, word_times = [], []
            for start,end in zip(boundaries,boundaries[1:]):
                transcript = mlx_whisper.transcribe(audio[round(start*16000):round(end*16000)], path_or_hf_repo=str(model), language='en',
                    temperature=args.temperature, condition_on_previous_text=False, word_timestamps=True, verbose=None,
                    initial_prompt=args.name_context, no_speech_threshold=None)
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
