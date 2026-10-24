#!/usr/bin/env python3
"""Assemble checked passages, measured verse cues, AAC files, and app catalog."""
import argparse
import hashlib
import json
import subprocess
import wave
from pathlib import Path

import numpy as np

from verify_bible_audio import words, write_json, timed_words as normalized_word_times


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    parser.add_argument('--chapter')
    args = parser.parse_args()
    root = args.root.resolve()/'gospels-v1'
    source = json.loads((root/'source.json').read_text())
    scope = json.loads((root/'publication-scope.json').read_text())
    allowed = {(item['book'], number) for item in scope['books'] for number in item['chapters']}
    sample_rate = 24000
    published = []
    for chapter in source['chapters']:
        if (chapter['book'], chapter['chapter']) not in allowed:
            continue
        folder = root/'chapters'/chapter['id']
        receipt_path = folder/'recording.json'
        if args.chapter and chapter['id'] != args.chapter:
            if receipt_path.exists():
                published.append(json.loads(receipt_path.read_text())['catalog_entry'])
            continue
        if not all((folder/'passages'/f'{chunk["index"]:03d}.check.json').exists() for chunk in chapter['chunks']):
            continue
        if receipt_path.exists():
            previous = json.loads(receipt_path.read_text())
            unchanged = previous['catalog_entry']['textSHA256'] == chapter['text_sha256']
            for passage in previous['passages']:
                file = folder/'passages'/f'{passage["index"]:03d}.wav'
                check = json.loads(file.with_suffix('.check.json').read_text())
                unchanged = unchanged and check['automatic_exact_match'] and check['sha256'] == passage['sha256'] == sha(file)
            encoded = Path(previous['local_audio'])
            if unchanged and encoded.exists() and sha(encoded) == previous['catalog_entry']['audioSHA256']:
                published.append(previous['catalog_entry'])
                continue
        parts = [np.zeros(int(.35*sample_rate), dtype=np.float32)]
        position = len(parts[0])
        cues = []
        passage_receipts = []
        problem = None
        for chunk in chapter['chunks']:
            path = folder/'passages'/f'{chunk["index"]:03d}.wav'
            check = json.loads(path.with_suffix('.check.json').read_text())
            if check['sha256'] != sha(path) or check['clipped_fraction'] != 0 or not check['automatic_exact_match']:
                problem = check['id']
                break
            with path.open('rb') as handle:
                with wave.open(handle) as reader:
                    assert reader.getframerate() == sample_rate
                    wav = np.frombuffer(reader.readframes(reader.getnframes()), dtype='<i2').astype(np.float32)/32768
            window = int(.01*sample_rate)
            count = len(wav)//window
            energy = np.sqrt(np.mean(wav[:count*window].reshape(count, window)**2, axis=1))
            active = np.flatnonzero(energy > .0006)
            assert len(active)
            start = max(0, int(active[0])*window-int(.1*sample_rate))
            end = min(len(wav), (int(active[-1])+1)*window+int(.15*sample_rate))
            trimmed = wav[start:end].copy()
            fade = min(int(.005*sample_rate), len(trimmed)//2)
            trimmed[:fade] *= np.linspace(0,1,fade)
            trimmed[-fade:] *= np.linspace(1,0,fade)
            timed_words = normalized_word_times(check['word_times'])
            expected = words(chunk['text'])
            assert [t[0] for t in timed_words] == expected, 'Word timestamps do not match source: '+check['id']
            first = 0
            for reference in chunk['references']:
                verse = next(v for v in chapter['verses'] if v['reference'] == reference)
                count = len(words(verse['text']))
                assert expected[first:first+count] == words(verse['text'])
                verse_start = max(0, timed_words[first][1]-start/sample_rate)
                verse_end = min(len(trimmed)/sample_rate, timed_words[first+count-1][2]-start/sample_rate)
                assert verse_end > verse_start
                cues.append(dict(reference=reference, start=round(position/sample_rate+verse_start,4),
                    end=round(position/sample_rate+verse_end,4)))
                first += count
            assert first == len(expected)
            passage_receipts.append(dict(index=chunk['index'], sha256=check['sha256'],
                start=position/sample_rate, trimmed_leading=start/sample_rate, trimmed_trailing=(len(wav)-end)/sample_rate))
            parts.append(trimmed)
            pause = np.zeros(int(.35*sample_rate),dtype=np.float32)
            parts.append(pause)
            position += len(trimmed)+len(pause)
        if problem:
            print('NEEDS_REVIEW '+problem,flush=True)
            continue
        audio = np.concatenate(parts)
        assert np.isfinite(audio).all() and np.max(np.abs(audio)) < .99
        wav_path = folder/f'{chapter["book"]} {chapter["chapter"]} - Evan.wav'
        with wav_path.open('wb') as handle:
            with wave.open(handle,'wb') as writer:
                writer.setnchannels(1); writer.setsampwidth(2); writer.setframerate(sample_rate)
                writer.writeframes(np.rint(audio*32767).astype('<i2').tobytes())
        m4a = wav_path.with_suffix('.m4a')
        subprocess.run(['/usr/bin/afconvert','-f','m4af','-d','aac@44100','-b','96000','-q','127',str(wav_path),str(m4a)],check=True)
        digest = sha(m4a)
        assert [cue['reference'] for cue in cues] == [v['reference'] for v in chapter['verses']]
        for a,b in zip(cues,cues[1:]):
            # ASR may put the boundary words on the same frame.
            if a['end'] > b['start'] and a['end']-b['start'] < .05:
                a['end'] = b['start']
            assert 0 <= a['start'] < a['end'] <= b['start']
        entry=dict(book=chapter['book'], chapter=chapter['chapter'], textSHA256=chapter['text_sha256'],
            audioPath=f'evan-bsb-v1/{chapter["id"]}/{digest}.m4a', audioSHA256=digest,
            byteCount=m4a.stat().st_size, duration=round(len(audio)/sample_rate,6), cues=cues)
        receipt=dict(catalog_entry=entry, local_audio=str(m4a), wav_sha256=sha(wav_path), passages=passage_receipts,
            voice='Saved Choir speaker embedding with trained voice-run-02 adapter',
            adapter_sha256='96e1746c34d634a4cc2a60a90cd91697de67aa846029af2823867480037c969b',
            verification='Every normalized source word matches independent local back-transcription; verse cues use recognized word timestamps.',
            human_listening_review_completed=False,
            processing='Quiet outer-edge trimming, 5 ms edge fades, 350 ms passage gaps; no pitch or speed change.')
        write_json(receipt_path,receipt)
        published.append(entry)
        print(f'ASSEMBLED {chapter["id"]}: {entry["duration"]:.2f}s, {entry["byteCount"]} bytes',flush=True)
    catalog=dict(schemaVersion=1, voiceID='evan-bsb-v1', translation='BSB', chapters=published)
    write_json(root/'catalog.json',catalog)
    print(f'CATALOG {len(published)}/{len(allowed)} requested chapters',flush=True)


if __name__ == '__main__':
    main()
