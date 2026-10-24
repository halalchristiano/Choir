#!/usr/bin/env python3
"""Append exact app BSB text after checking publisher words and all live hashes."""
import hashlib
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve() / 'gospels-v1'
path = root / 'source.json'
source = json.loads(path.read_text())
counts = {'1 Timothy': 6, '2 Timothy': 4, 'Titus': 3}
live = {(x['book'], x['chapter']): x for x in json.loads((root/'finish-pastorals-live-text-hashes.json').read_text())}
assert set(live) == {(book, n) for book, count in counts.items() for n in range(1, count+1)}
assert not any(c['book'] in counts for c in source['chapters'])
verses = {}
live_verses = {r['reference']: r for r in json.loads((root/'finish-pastorals-live-verses.json').read_text())}
for line in (root/'bsb-publisher.txt').read_text().splitlines():
    match = re.fullmatch(r'(1 Timothy|2 Timothy|Titus) (\d+):(\d+)\t(.*)', line)
    if match:
        book, chapter, verse, text = match.groups()
        chapter, verse = int(chapter), int(verse)
        row = live_verses[f'{book} {chapter}:{verse}']
        assert text.casefold() == row['text'].casefold(), row['reference']
        verses.setdefault((book, chapter), []).append(row)
chapters = []
for (book, number), expected in live.items():
    rows = verses[(book, number)]
    assert [r['verse'] for r in rows] == list(range(1, expected['verses']+1))
    digest = hashlib.sha256('\n'.join(r['reference']+'\t'+r['text'] for r in rows).encode()).hexdigest()
    assert digest == expected['text_sha256'], (book, number)
    groups, group = [], []
    for row in rows:
        assert len(row['text'].split()) <= 75
        if group and sum(len(r['text'].split()) for r in group)+len(row['text'].split()) > 75:
            groups.append(group)
            group = []
        group.append(row)
    if group:
        groups.append(group)
    chunks = [dict(index=i, first_verse=g[0]['verse'], last_verse=g[-1]['verse'], references=[r['reference'] for r in g], text=' '.join(r['text'] for r in g)) for i, g in enumerate(groups, 1)]
    chapters.append(dict(id=f'{book.lower().replace(" ", "-")}-{number:02d}', book=book, chapter=number, translation='BSB', text_sha256=digest, verses=rows, chunks=chunks))
assert len(chapters) == 13 and sum(len(c['verses']) for c in chapters) == 242
backup = root/'source.before-pastorals.json'
assert not backup.exists()
backup.write_bytes(path.read_bytes())
source['chapters'].extend(chapters)
source.update(chapter_count=len(source['chapters']), verse_count=sum(len(c['verses']) for c in source['chapters']), word_count=sum(len(v['text'].split()) for c in source['chapters'] for v in c['verses']), passage_count=sum(len(c['chunks']) for c in source['chapters']))
temporary = path.with_suffix('.tmp')
temporary.write_text(json.dumps(source, ensure_ascii=False, indent=2)+'\n')
temporary.replace(path)
scope_path = root/'publication-scope.json'
(root/'publication-scope.before-pastorals.json').write_bytes(scope_path.read_bytes())
scope = json.loads(scope_path.read_text())
scope['books'].extend(dict(book=book, chapters=list(range(1, count+1))) for book, count in counts.items())
scope['reason'] = 'Finish Genesis and all the Pastorals (1 Timothy, 2 Timothy, Titus), retaining all of Mark.'
scope_path.write_text(json.dumps(scope, indent=2)+'\n')
print(json.dumps(dict(books=list(counts), chapters=13, verses=242, passages=sum(len(c['chunks']) for c in chapters), liveTextHashesMatch=True), indent=2))
