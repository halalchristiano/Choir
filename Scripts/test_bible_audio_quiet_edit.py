import json,tempfile,unittest,wave
from pathlib import Path
import numpy as np
import bible_audio_quiet_edit as q
class QuietEditChecks(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.root=Path(self.tmp.name);self.original=np.full(1000,12,dtype='<i2');self.original[:250]=1000;self.original[750:]=2000;self.parent=self.root/'parent.wav';self.child=self.root/'child.wav';self.write(self.parent,self.original);self.write(self.child,q.transform(self.original,1000,.3,.7,.005))
  self.parent_check=dict(sha256=q.sha(self.parent),automatic_exact_match=True,clipped_fraction=0,expected='one two',recognized='one two',word_times=[dict(word='one',start=0.,end=.2),dict(word='two',start=.8,end=1.)]);cp=self.root/'parent.check.json';cp.write_text(json.dumps(self.parent_check));self.check=dict(verificationMethod='verified-quiet-only-edit-of-recognized-source',quietEditProof=dict(parentAudio=dict(path=str(self.parent),sha256=q.sha(self.parent)),parentCheck=dict(path=str(cp),sha256=q.sha(cp)),removedSeconds=[.3,.7],fadeSeconds=.005),recognitionAudioSHA256=q.sha(self.parent),expected='one two',recognized='one two',sha256=q.sha(self.child),word_times=q.mapped_times(self.parent_check['word_times'],.3,.7),seconds=.6)
 def write(self,p,pcm):
  with wave.open(str(p),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(1000);f.writeframes(pcm.tobytes())
 def test_exact_quiet_edit_and_timestamp_shift(self):
  self.assertTrue(q.verify(self.child,self.check)['retainedSamplesVerified']);self.assertAlmostEqual(self.check['word_times'][1]['start'],.4)
 def test_changed_speech_rejected_even_with_updated_child_hash(self):
  _,pcm=q.read(self.child);pcm[0]+=1;self.write(self.child,pcm);self.check['sha256']=q.sha(self.child)
  with self.assertRaises(AssertionError):q.verify(self.child,self.check)
 def test_speech_deletion_rejected(self):
  with self.assertRaises(AssertionError):q.transform(self.original,1000,.1,.2,.005)
 def test_changed_transcript_rejected(self):
  self.check['recognized']='one three'
  with self.assertRaises(AssertionError):q.verify(self.child,self.check)
if __name__=='__main__':unittest.main()
