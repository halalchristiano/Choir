#!/usr/bin/env python3
"""Add the ten remaining Pauline books from verified app BSB rows.

The existing thirteen Pastoral chapters and all other published recordings stay
unchanged. Verse numbering follows BSB, including its omitted Romans 16:24.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

COUNTS = {
    'Romans': 16, '1 Corinthians': 16, '2 Corinthians': 13, 'Galatians': 6,
    'Ephesians': 6, 'Philippians': 4, 'Colossians': 4,
    '1 Thessalonians': 5, '2 Thessalonians': 3, 'Philemon': 1,
}


def write_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
    temporary.replace(path)


def main():
    root = Path(sys.argv[1]).resolve()/'gospels-v1'
    path = root/'source.json'
    source = json.loads(path.read_text())
    live = {(r['book'], r['chapter']): r for r in
            json.loads((root/'pauline-live-text-hashes.json').read_text())}
    expected = {(book, n) for book, count in COUNTS.items() for n in range(1, count+1)}
    assert set(live) == expected
    rows = json.loads((root/'pauline-live-verses.json').read_text())
    assert len(rows) == 1790 and len({r['reference'] for r in rows}) == len(rows)
    publisher = {}
    for line in (root/'bsb-publisher.txt').read_text().splitlines():
        match = re.fullmatch(r'(.+ \d+:\d+)\t(.*)', line)
        if match:
            publisher[match[1]] = match[2]
    chapters = []
    for book, count in COUNTS.items():
        for number in range(1, count+1):
            verses = sorted((r for r in rows if r['book'] == book and r['chapter'] == number), key=lambda r:r['verse'])
            assert len(verses) == live[(book, number)]['verses']
            for row in verses:
                assert row['reference'] == f'{book} {number}:{row["verse"]}'
                assert row['text'].casefold() == publisher[row['reference']].casefold(), row['reference']
            digest = hashlib.sha256('\n'.join(r['reference']+'\t'+r['text'] for r in verses).encode()).hexdigest()
            assert digest == live[(book, number)]['text_sha256']
            groups, group = [], []
            for row in verses:
                assert len(row['text'].split()) <= 75
                if group and sum(len(r['text'].split()) for r in group)+len(row['text'].split()) > 75:
                    groups.append(group)
                    group = []
                group.append(row)
            if group:
                groups.append(group)
            chunks = [dict(index=i, first_verse=g[0]['verse'], last_verse=g[-1]['verse'],
                           references=[r['reference'] for r in g], text=' '.join(r['text'] for r in g))
                      for i, g in enumerate(groups, 1)]
            chapters.append(dict(id=f'{book.lower().replace(" ", "-")}-{number:02d}',
                                 book=book, chapter=number, translation='BSB',
                                 text_sha256=digest, verses=verses, chunks=chunks))
    assert len(chapters) == 74
    existing = {c['id']: c for c in source['chapters']}
    added = [c for c in chapters if c['id'] not in existing]
    for c in chapters:
        if c['id'] in existing:
            assert c == existing[c['id']], 'Existing source differs: '+c['id']
    if added:
        backup = root/'source.before-pauline.json'
        assert not backup.exists()
        backup.write_bytes(path.read_bytes())
        source['chapters'].extend(added)
        source.update(chapter_count=len(source['chapters']),
                      verse_count=sum(len(c['verses']) for c in source['chapters']),
                      word_count=sum(len(v['text'].split()) for c in source['chapters'] for v in c['verses']),
                      passage_count=sum(len(c['chunks']) for c in source['chapters']))
        write_json(path, source)
    scope_path = root/'publication-scope.json'
    scope = json.loads(scope_path.read_text())
    scope_books = {r['book']: r['chapters'] for r in scope['books']}
    if not all(book in scope_books for book in COUNTS):
        backup = root/'publication-scope.before-pauline.json'
        assert not backup.exists()
        backup.write_bytes(scope_path.read_bytes())
        for book, count in COUNTS.items():
            wanted = list(range(1, count+1))
            if book in scope_books:
                assert scope_books[book] == wanted
            else:
                scope['books'].append(dict(book=book, chapters=wanted))
        scope['reason'] = 'All thirteen Pauline letters, retaining completed Genesis and Mark; Hebrews is outside this batch.'
        write_json(scope_path, scope)
    print(json.dumps(dict(books=list(COUNTS), chapters=74, verses=1790,
                          passages=sum(len(c['chunks']) for c in chapters),
                          liveTextHashesMatch=True, publisherWordsMatch=True,
                          addedChapters=len(added)), indent=2))


if __name__ == '__main__':
    main()
