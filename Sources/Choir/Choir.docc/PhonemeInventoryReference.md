# Phoneme Inventory

Use CHOIR's stable General American English ARPAbet-to-IPA mapping for
pronunciation overrides and pre-phonemized input.

## Stress

ARPAbet vowel suffixes `0`, `1`, and `2` mean unstressed, primary stress, and
secondary stress. CHOIR maps unstressed `AH0` to schwa `/ə/`; stressed `AH1`
or `AH2` maps to `/ʌ/`. IPA input stores stress separately on ``Phoneme``.

```swift
let converted = PhonemeInventory.conversion(
    fromARPAbet: "M EH1 L K IH0 Z AH0 D EH2 K"
)

guard converted.isComplete else {
    print(converted.unknownSymbols)
    return
}
```

Unknown ARPAbet tokens are reported and omitted; they are never silently
reinterpreted as another sound.

## Vowels and diphthongs

| ARPAbet | IPA | Example word | Audio example |
|---|---|---|---|
| AA | ɑ | odd | Pending production voice assets |
| AE | æ | at | Pending production voice assets |
| AH | ʌ | hut | Pending production voice assets |
| AX | ə | about | Pending production voice assets |
| AO | ɔ | ought | Pending production voice assets |
| AW | aʊ | cow | Pending production voice assets |
| AY | aɪ | hide | Pending production voice assets |
| EH | ɛ | Ed | Pending production voice assets |
| ER | ɝ | hurt | Pending production voice assets |
| EY | eɪ | ate | Pending production voice assets |
| IH | ɪ | it | Pending production voice assets |
| IY | iː | eat | Pending production voice assets |
| OW | oʊ | oat | Pending production voice assets |
| OY | ɔɪ | toy | Pending production voice assets |
| UH | ʊ | hood | Pending production voice assets |
| UW | uː | two | Pending production voice assets |

## Consonants

| ARPAbet | IPA | Example word | Audio example |
|---|---|---|---|
| B | b | be | Pending production voice assets |
| CH | tʃ | cheese | Pending production voice assets |
| D | d | dee | Pending production voice assets |
| DH | ð | thee | Pending production voice assets |
| F | f | fee | Pending production voice assets |
| G | ɡ | green | Pending production voice assets |
| HH | h | he | Pending production voice assets |
| JH | dʒ | gee | Pending production voice assets |
| K | k | key | Pending production voice assets |
| L | l | lee | Pending production voice assets |
| M | m | me | Pending production voice assets |
| N | n | knee | Pending production voice assets |
| NG | ŋ | ping | Pending production voice assets |
| P | p | pee | Pending production voice assets |
| R | r | read | Pending production voice assets |
| S | s | sea | Pending production voice assets |
| SH | ʃ | she | Pending production voice assets |
| T | t | tea | Pending production voice assets |
| TH | θ | theta | Pending production voice assets |
| V | v | vee | Pending production voice assets |
| W | w | we | Pending production voice assets |
| Y | j | yield | Pending production voice assets |
| Z | z | zee | Pending production voice assets |
| ZH | ʒ | seizure | Pending production voice assets |

The source of truth is ``PhonemeInventory/all``. Existing symbols do not
change meaning or disappear within a major version. New symbols may be added
only with encoder vocabulary, conversion, test, migration, and cache-version
review.

## IPA input

```swift
let phonemes = [
    Phoneme("h"),
    Phoneme("ɛ", stress: 1),
    Phoneme("l"),
    Phoneme("oʊ")
]

let transcription = try LinguisticFrontend().process(.phonemes(phonemes))
```

`Phoneme("g")` normalizes to canonical IPA `ɡ`. End-to-end engine synthesis
from `.phonemes` requires a production acoustic implementation. The current
default engine reports that limitation rather than synthesizing misleading
audio.

## Audio-example acceptance gate

The table intentionally contains no fabricated clips. DOC-004 remains only
partially satisfied until one reviewed, normalized, license-clean audio sample
per inventory entry is generated with a production voice, checked against its
target sound, packaged as DocC resources, and linked in the final column.
