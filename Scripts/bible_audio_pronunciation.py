"""Audited pronunciation respellings affect synthesis prompts, never source text."""
import re


def restore_source_spellings(prompt, pronunciations, *, source_text=None):
    """Undo cues, optionally restricting them to names in the canonical source.

    A dictionary cue such as Pul -> Pool must not reinterpret an unrelated
    literal pool. Callers must still compare the complete restored word sequence
    with the canonical text; a passage containing both forms remains ambiguous.
    """
    restored = prompt
    used = []
    for entry in sorted(pronunciations, key=lambda item: len(item['spoken']), reverse=True):
        assert entry['source'] and entry['spoken'] and entry['reference'].startswith('https://')
        assert re.fullmatch(r'[A-Za-z]+(?:-[A-Za-z]+)*', entry['source'])
        if source_text is not None and not re.search(
                r'(?<!\w)'+re.escape(entry['source'])+r'(?!\w)', source_text, re.IGNORECASE):
            continue
        pattern = r'(?<!\w)'+re.escape(entry['spoken'])+r'(?!\w)'
        restored, count = re.subn(pattern, entry['source'], restored, flags=re.IGNORECASE)
        if count:
            used.append(dict(entry, occurrences=count))
    return restored, used
