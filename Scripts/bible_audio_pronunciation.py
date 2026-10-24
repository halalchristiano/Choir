"""Audited pronunciation respellings affect synthesis prompts, never source text."""
import re


def restore_source_spellings(prompt, pronunciations):
    restored = prompt
    used = []
    for entry in sorted(pronunciations, key=lambda item: len(item['spoken']), reverse=True):
        assert entry['source'] and entry['spoken'] and entry['reference'].startswith('https://')
        assert re.fullmatch(r'[A-Za-z]+(?:-[A-Za-z]+)*', entry['source'])
        pattern = r'(?<!\w)'+re.escape(entry['spoken'])+r'(?!\w)'
        restored, count = re.subn(pattern, entry['source'], restored, flags=re.IGNORECASE)
        if count:
            used.append(dict(entry, occurrences=count))
    return restored, used
