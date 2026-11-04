"""Require the checked source audio for two narrowly scoped ASR name spellings.

A matching sentence alone cannot grant acceptance. The original independent
phonetic diagnostic identified the name in a fixed Choir component, whose
actual PCM must occur unchanged in the candidate recording.
"""
import hashlib,json,re,wave
from pathlib import Path

RULES = [{'pattern': '\\b(?P<value>Elasa)(?=\\s+was\\s+the\\s+father\\s+of\\s+Sismai\\b)', 'canonicalContext': 'Elasah was the father of Sismai', 'canonicalName': 'Elasah', 'componentAudioSHA256': 'c554404881796455a4afa4714028f90d405285612ceeb123cd4f92c3ab5aed1b', 'diagnosticSHA256': 'd9afb9ec3230825cf08b7438a12200316770a8bf37f68a47134c76544bc6863b', 'reference': 'https://classic.net.bible.org/dictionary.php?word=Elasah', 'requiredPhonemes': 'ɪ l a s ɐ'}, {'pattern': '\\bShimea\\s+his\\s+son,?\\s+(?:Haggiah|Haggai\\s+ah)\\s+his\\s+son,?\\s+and\\s+(?P<value>Isaiah)(?=\\s+his\\s+son\\b)', 'canonicalContext': 'Shimea his son, Haggiah his son, and Asaiah his son', 'canonicalName': 'Asaiah', 'componentAudioSHA256': 'd50aa9d57b9d10e75a9f846f1ddab3088c8603d1a247c977afe415f7b15f3327', 'diagnosticSHA256': 'cd415a0876c8ced9061e0d15631a117e8266e652fbf1f8ef90ab375b5dee7290', 'reference': 'https://www.biblegateway.com/resources/encyclopedia-of-the-bible/Asaiah', 'requiredPhonemes': 'ɐ z eɪ ɐ'}, {'pattern': '\\b(?P<value>Shalom)(?=\\s+was\\s+the\\s+father\\s+of\\s+Jekamiah\\b)', 'canonicalContext': 'Shallum was the father of Jekamiah', 'canonicalName': 'Shallum', 'componentAudioSHA256': '080342f94f83e1e2cb64e3708ca2cfb0476fc60a68d806ad5f9a9d3f09558105', 'diagnosticSHA256': 'b087595749dfe402072ee452001dcb7f302f05d0b3151051e55e172788d9a9b1', 'reference': 'https://www.biblegateway.com/resources/encyclopedia-of-the-bible/Shallum', 'requiredPhonemes': 'ʃ æ l ə m'}, {'pattern': '\\b(?P<value>Ibnijah)(?=,?\\s+son\\s+of\\s+Jeroham\\b)', 'canonicalContext': 'Ibneiah son of Jeroham', 'canonicalName': 'Ibneiah', 'componentAudioSHA256': 'dcccab05a88b30caf0aa10f9d94d1a995b8531feeee45c57c99d748225fb8dd9', 'diagnosticSHA256': '7a4e335b0cf21c984f39823d313712c69a94f712ec628f5dba4814a73012c331', 'reference': 'https://classic.net.bible.org/dictionary.php?word=Ibneiah', 'requiredPhonemes': 'ɪ b n iː ɐ'}]

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def verify(path,check):
    needed=[rule for rule in RULES if re.search(rule['pattern'],check['recognized'],re.IGNORECASE)]
    if not needed:return dict(passes=True,required=False,components=[])
    try:
        import numpy as np
        path=Path(path);metadata=json.loads(path.with_suffix('.json').read_text())
        assert digest(path)==check['sha256']==metadata['audio_sha256']
        assert check['expected']==metadata['text']
        with wave.open(str(path)) as reader:
            assert (reader.getframerate(),reader.getnchannels(),reader.getsampwidth())==(24000,1,2)
            pcm=np.frombuffer(reader.readframes(reader.getnframes()),dtype='<i2')
        proof=metadata['postprocessing'];assert proof['kind']=='Same-voice clauses with verified quiet edge trims'
        components=[]
        for rule in needed:
            assert rule['canonicalContext'].casefold() in check['expected'].casefold()
            matches=[s for s in proof['segments'] if s['sha256']==rule['componentAudioSHA256']]
            assert len(matches)==1
            segment=matches[0];original=Path(segment['path']);assert digest(original)==rule['componentAudioSHA256']
            with wave.open(str(original)) as reader:
                assert (reader.getframerate(),reader.getnchannels(),reader.getsampwidth())==(24000,1,2)
                samples=np.frombuffer(reader.readframes(reader.getnframes()),dtype='<i2')
            a,b=segment['sourceStartFrame'],segment['sourceEndFrame'];lo,hi=segment['outputStartFrame'],segment['outputEndFrame'];fade=segment['quietEdgeFadeFrames']
            assert 0<=a<b<=len(samples) and 0<=lo<hi<=len(pcm) and b-a==hi-lo and fade==120
            expected=samples[a:b].copy();assert len(expected)>2*fade
            assert np.max(np.abs(expected[:fade].astype(np.int32)))<.006*32768 and np.max(np.abs(expected[-fade:].astype(np.int32)))<.006*32768
            expected[:fade]=np.rint(expected[:fade].astype(float)*np.linspace(0,1,fade)).astype('<i2')
            expected[-fade:]=np.rint(expected[-fade:].astype(float)*np.linspace(1,0,fade)).astype('<i2')
            assert np.array_equal(pcm[lo:hi],expected)
            components.append(dict(name=rule['canonicalName'],componentAudioSHA256=rule['componentAudioSHA256'],independentDiagnosticSHA256=rule['diagnosticSHA256'],exactCandidatePCM=True,outputStartFrame=lo,outputEndFrame=hi,reference=rule['reference']))
        return dict(passes=True,required=True,components=components)
    except (AssertionError,KeyError,ValueError,FileNotFoundError,wave.Error) as error:
        return dict(passes=False,required=True,components=[],reason='The exact independent acoustic evidence was not reproduced: '+type(error).__name__)
