"""Compare the pinned, trained model's original and retained-cache sessions."""
import argparse,dataclasses,hashlib,json,sys,time
from pathlib import Path
import mlx.core as mx
import mlx.nn as nn
import numpy as np
from mlx_audio.tts.continuous import TTSBatchItem,TTSBatchOptions
from mlx_audio.tts.models.qwen3_tts.continuous_batching import Qwen3TTSBatchSession
from mlx_audio.tts.utils import load_model

parser=argparse.ArgumentParser()
parser.add_argument('root',type=Path)
parser.add_argument('--receipt',type=Path,required=True)
args=parser.parse_args()
R=args.root.resolve()
sys.path.insert(0,str(R/'Choir/Scripts'))
from voice_finetune_mlx import add_lora
from bible_audio_cached_session import CachedQwen3TTSBatchSession

mx.set_cache_limit(256*1024*1024)
config=json.loads((R/'voice-run-02/config.json').read_text())
model=load_model(str(R/'cache/huggingface/hub/models--mlx-community--Qwen3-TTS-12Hz-0.6B-Base-8bit/snapshots'/config['base_revision']))
add_lora(model,config['rank'],config['layers'])
model.load_weights(str(R/'voice-run-02/best.safetensors'),strict=False)
speaker=mx.load(str(R/'voice-run-02/speaker.safetensors'))['embedding']
embedding=model.talker.get_input_embeddings()
assert not isinstance(embedding,nn.QuantizedEmbedding)
weights=embedding.weight;weights[3000]=speaker.reshape(-1).astype(weights.dtype);embedding.weight=weights
model.config.talker_config.spk_id={'choirreading':3000};model.supported_speakers=['choirreading']
model.eval();mx.eval(model.talker.parameters())
texts=['Praise the LORD.','The LORD is my shepherd; I shall not want.',
       'Be strong and courageous.','In the beginning God created the heavens and the earth.',
       'The grace of the Lord Jesus be with all the saints. Amen.',
       'And God said, Let there be light, and there was light.',
       'Hear, O Israel: The LORD our God, the LORD is One.',
       'A gentle answer turns away wrath, but a harsh word stirs up anger.']
items=[TTSBatchItem(sequence_id=i,text=text,voice='choirreading') for i,text in enumerate(texts)]
options=TTSBatchOptions(temperature=.7,top_p=.9,top_k=50,repetition_penalty=1.05,max_tokens=120,lang_code='english',max_batch_size=4)

def run(cls,cancellation=False):
    captured={}
    class Traced(cls):
        def _decode_state(self,state):
            captured[state.sequence_id]=dict(tokens=state.generated_token_ids[:],codes=np.concatenate([np.asarray(x) for x in state.generated_codes],axis=0))
            return super()._decode_state(state)
    mx.random.seed(112358)
    session=Traced(model,options);session.add(items)
    result={};steps=0;start=time.time()
    while not session.idle:
        if cancellation and steps==5:
            session.cancel(2);session.cancel(6)
        for event in session.step():
            mx.eval(event.audio)
            assert event.done and event.error is None and not event.is_streaming_chunk
            result[event.sequence_id]=np.asarray(event.audio).copy()
        steps+=1
    return dict(captured=captured,result=result,elapsed=time.time()-start,steps=steps)

reports=[]
for cancellation in [False,True]:
    original=run(Qwen3TTSBatchSession,cancellation)
    retained=run(CachedQwen3TTSBatchSession,cancellation)
    expected=set(range(8))-({2,6} if cancellation else set())
    assert set(original['result'])==set(retained['result'])==expected
    assert original['steps']==retained['steps']
    checks=[]
    for identity in sorted(expected):
        before=original['captured'][identity];after=retained['captured'][identity]
        assert before['tokens']==after['tokens'],('token mismatch',identity)
        assert np.array_equal(before['codes'],after['codes']),('codec mismatch',identity)
        assert np.array_equal(original['result'][identity],retained['result'][identity]),('waveform mismatch',identity)
        checks.append(dict(id=identity,tokens=len(after['tokens']),floatAudioSHA256=hashlib.sha256(retained['result'][identity].tobytes()).hexdigest(),identicalCodecTokens=True,identicalWaveform=True))
    report=dict(cancellation=cancellation,originalSeconds=original['elapsed'],retainedSeconds=retained['elapsed'],steps=original['steps'],checks=checks)
    reports.append(report)
    print(json.dumps({k:v for k,v in report.items() if k!='checks'}),flush=True)
args.receipt.write_text(json.dumps(dict(passed=True,adapterSHA256=hashlib.sha256((R/'voice-run-02/best.safetensors').read_bytes()).hexdigest(),baseRevision=config['base_revision'],options=dataclasses.asdict(options),tests=reports),indent=2)+'\n')
print('RETAINED_CACHE_EQUIVALENCE_PASSED',flush=True)
