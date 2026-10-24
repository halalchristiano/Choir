#!/usr/bin/env python3
"""Add the existing Genesis preview, byte for byte, to the verified app catalog.

Uses the original chunk assembly timeline and independent word timestamps.
Run with the voice workspace root and prepare|finish. Between these steps run
verify_bible_audio.py ROOT --chapter genesis-01 to obtain the word timestamps.
The existing preview and Mark recordings are never re-encoded or overwritten.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

from verify_bible_audio import words, write_json


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def preserve(path):
    backup = path.with_name(path.stem + '.before-genesis' + path.suffix)
    if path.exists() and not backup.exists():
        shutil.copy2(path, backup)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('action', choices=['prepare', 'finish'])
    args = parser.parse_args()
    root = args.root.resolve()
    preview = root/'previews/genesis-1'
    directory = root/'gospels-v1'
    folder = directory/'chapters/genesis-01'
    passages = folder/'passages'
    passages.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((preview/'text.json').read_text())
    original = json.loads((preview/'recording.json').read_text())
    verses = json.loads((preview/'app-verses.json').read_text())
    assert [v['verse'] for v in verses] == list(range(1, 32))
    assert all(v['reference'] == f'Genesis 1:{v["verse"]}' and v['book'] == 'Genesis' and v['chapter'] == 1 for v in verses)
    assert [(v['verse'], v['text']) for v in verses] == [(v['verse'], v['text']) for v in manifest['verses']], 'App BSB text differs from the spoken preview'
    for file in original['files']:
        path = preview/file['name']
        assert path.stat().st_size == file['bytes'] and sha(path) == file['sha256']
    digest = hashlib.sha256('\n'.join(v['reference']+'\t'+v['text'] for v in verses).encode()).hexdigest()
    chunks = [dict(index=c['index'], references=[f'Genesis 1:{v}' for v in range(c['first_verse'],c['last_verse']+1)], text=c['text']) for c in manifest['chunks']]
    chapter = dict(id='genesis-01',book='Genesis',chapter=1,translation='BSB',text_sha256=digest,verses=verses,chunks=chunks)
    source_path = directory/'source.json'
    source = json.loads(source_path.read_text())
    if args.action == 'prepare':
        prior_checks = {c['index']:c for c in json.loads((preview/'word-check.json').read_text())['chunks']}
        for chunk in chunks:
            source_wav = preview/'chunks'/f'{chunk["index"]:02d}.wav'
            assert sha(source_wav) == prior_checks[chunk['index']]['sha256']
            destination = passages/f'{chunk["index"]:03d}.wav'
            if destination.exists():
                assert sha(destination) == sha(source_wav)
            else:
                shutil.copy2(source_wav, destination)
            write_json(destination.with_suffix('.json'),dict(imported_from=str(source_wav),sha256=sha(source_wav),text=chunk['text']))
        previous = next((c for c in source['chapters'] if c['id']=='genesis-01'),None)
        assert previous is None or previous == chapter
        if previous is None:
            preserve(source_path)
            source['chapters'].insert(0, chapter)
            source.update(chapter_count=len(source['chapters']),verse_count=sum(len(c['verses']) for c in source['chapters']),
                word_count=sum(len(words(v['text'])) for c in source['chapters'] for v in c['verses']),
                passage_count=sum(len(c['chunks']) for c in source['chapters']))
            write_json(source_path, source)
        write_json(folder/'source.json', chapter)
        print('Prepared 14 unchanged preview passages; app text matches all 31 verses.',flush=True)
        return

    cues, receipt_passages = [], []
    timeline = {r['index']:r for r in original['timeline']}
    for chunk in chunks:
        path = passages/f'{chunk["index"]:03d}.wav'
        check = json.loads(path.with_suffix('.check.json').read_text())
        assert check['sha256'] == sha(path) and check['automatic_exact_match'] and check['clipped_fraction'] == 0
        timed = [(token,item['start'],item['end']) for item in check['word_times'] for token in words(item['word'])]
        expected = words(chunk['text'])
        assert [t[0] for t in timed] == expected
        line = timeline[chunk['index']]
        offset = line['start_seconds']-line['trimmed_leading_seconds']
        first = 0
        for reference in chunk['references']:
            verse = next(v for v in verses if v['reference']==reference)
            count = len(words(verse['text']))
            assert expected[first:first+count] == words(verse['text'])
            start = max(line['start_seconds'],offset+timed[first][1])
            end = min(line['end_seconds'],offset+timed[first+count-1][2])
            assert end > start
            cues.append(dict(reference=reference,start=round(start,4),end=round(end,4)))
            first += count
        assert first == len(expected)
        receipt_passages.append(dict(index=chunk['index'],sha256=sha(path),start=line['start_seconds'],
            trimmed_leading=line['trimmed_leading_seconds'],trimmed_trailing=line['trimmed_trailing_seconds']))
    assert [c['reference'] for c in cues] == [v['reference'] for v in verses]
    for a,b in zip(cues,cues[1:]):
        if 0 < a['end']-b['start'] < .05:
            a['end'] = b['start']
        assert 0 <= a['start'] < a['end'] <= b['start']
    assert cues[-1]['end'] <= original['seconds']
    m4a = preview/'Genesis 1 - Trained Voice.m4a'
    audio_sha = sha(m4a)
    entry = dict(book='Genesis',chapter=1,textSHA256=digest,audioPath=f'evan-bsb-v1/genesis-01/{audio_sha}.m4a',
        audioSHA256=audio_sha,byteCount=m4a.stat().st_size,duration=original['seconds'],cues=cues)
    receipt = dict(catalog_entry=entry,local_audio=str(m4a),wav_sha256=original['sha256'],passages=receipt_passages,
        voice='Saved Choir speaker embedding with trained voice-run-02 adapter',
        adapter_sha256=sha(root/'voice-run-02/best.safetensors'),preserved_preview=True,original_receipt=str(preview/'recording.json'),
        verification='All 31 app BSB verses exactly match preview source; independent word timestamps cover all 749 words. Audible homophone spelling equivalents team/teem and teamed/teemed are normalized; raw transcripts retained.',
        human_listening_review_completed=False,processing='Original preview bytes preserved, including its paragraph pauses; no resynthesis or re-encoding.')
    write_json(folder/'recording.json',receipt)
    catalog_path = directory/'catalog.json'
    catalog = json.loads(catalog_path.read_text())
    retained = [c for c in catalog['chapters'] if (c['book'],c['chapter']) != ('Genesis',1)]
    assert {(c['book'],c['chapter']) for c in retained} == {('Mark',v) for v in range(1,6)}
    preserve(catalog_path)
    catalog['chapters'] = [entry]+retained
    write_json(catalog_path,catalog)
    scope_path = directory/'publication-scope.json'
    preserve(scope_path)
    write_json(scope_path,dict(books=[dict(book='Genesis',chapters=[1]),dict(book='Mark',chapters=list(range(1,6)))],
        reason='User added the existing Genesis 1 preview to the already published Mark 1–5 recordings.',larger_generation_stopped=True))
    print(f'Imported unchanged Genesis 1: {original["seconds"]:.2f}s, {len(cues)} verse cues; retained all five Mark entries.',flush=True)


if __name__ == '__main__':
    main()
