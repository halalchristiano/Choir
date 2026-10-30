"""Verify a quiet-only deletion against an independently recognized parent.

This is an edit certificate, not a new ASR transcript. The parent's complete
unaltered transcript and its actual recognition-audio hash remain explicit.
"""
import hashlib,json,wave
from pathlib import Path
import numpy as np
from verify_bible_audio import words,timed_words

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):
 with wave.open(str(p),'rb') as f:
  assert f.getnchannels()==1 and f.getsampwidth()==2
  return f.getframerate(),np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').copy()
def transform(pcm,rate,start,end,fade_seconds):
 lo,hi=round(start*rate),round(end*rate);fade=round(fade_seconds*rate)
 assert 0<fade<=lo<hi<=len(pcm)-fade
 # Check both deleted samples and all samples modified by fades.
 quiet=pcm[lo-fade:hi+fade].astype(float)/32768
 assert float(np.sqrt(np.mean(quiet**2)))<.001 and float(abs(quiet).max())<.006
 left=pcm[:lo].astype(float);right=pcm[hi:].astype(float)
 left[-fade:]*=np.linspace(1,0,fade);right[:fade]*=np.linspace(0,1,fade)
 return np.concatenate([left,right]).astype('<i2')
def mapped_times(parent,start,end):
 def at(t):return t if t<start else start if t<=end else t-(end-start)
 result=[]
 for item in parent:
  # Never certify deletion of an entire recognized word interval.
  assert not (item['start']>=start and item['end']<=end)
  q=dict(item,start=at(item['start']),end=at(item['end']));assert q['end']>=q['start'];result.append(q)
 return result

def verify(child_path,check):
 assert check['verificationMethod']=='verified-quiet-only-edit-of-recognized-source'
 proof=check['quietEditProof'];parent_path=Path(proof['parentAudio']['path']);parent_check_path=Path(proof['parentCheck']['path'])
 assert sha(parent_path)==proof['parentAudio']['sha256'];assert sha(parent_check_path)==proof['parentCheck']['sha256']
 parent=json.loads(parent_check_path.read_text());assert parent['sha256']==proof['parentAudio']['sha256']==check['recognitionAudioSHA256']
 assert parent['automatic_exact_match'] and parent['clipped_fraction']==0
 assert parent['expected']==check['expected'] and parent['recognized']==check['recognized']
 assert words(parent['expected'])==words(parent['recognized'])==[w[0] for w in timed_words(parent['word_times'])]
 rate,original=read(parent_path);child_rate,child=read(child_path);assert rate==child_rate
 start,end=proof['removedSeconds'];expected=transform(original,rate,start,end,proof['fadeSeconds'])
 assert np.array_equal(child,expected), 'A retained speech sample differs from the certified transformation'
 assert sha(child_path)==check['sha256']
 assert check['word_times']==mapped_times(parent['word_times'],start,end)
 assert [w[0] for w in timed_words(check['word_times'])]==words(check['expected'])
 assert abs(check['seconds']-len(child)/rate)<1e-8
 return dict(parentSHA256=parent['sha256'],childSHA256=check['sha256'],removedSeconds=end-start,retainedSamplesVerified=True)
