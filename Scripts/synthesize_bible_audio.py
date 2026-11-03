#!/usr/bin/env python3
"""Resumable chapter audio using the pinned Choir fine-tune and app text.

Raw recordings and model assets remain outside the repository. Completed
passages are immutable by text/model hash and retain their generation settings.
"""
import argparse
import hashlib
import json
import re
import time
import wave
from pathlib import Path

import mlx.core as mx
import mlx.nn as nn
import numpy as np
from mlx_audio.tts.utils import load_model

from voice_finetune_mlx import add_lora
from verify_bible_audio import number_words, words
from bible_audio_pronunciation import restore_source_spellings

ADAPTER_SHA = '96e1746c34d634a4cc2a60a90cd91697de67aa846029af2823867480037c969b'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, data):
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n')
    tmp.replace(path)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('root', type=Path)
    p.add_argument('--batch-size', type=int, default=4)
    p.add_argument('--continuous', action='store_true',
                   help='Refill completed inference slots from a saved queue; keep the same bounded batch size.')
    p.add_argument('--limit', type=int)
    p.add_argument('--books', nargs='+', default=['Mark', 'John', 'Matthew', 'Luke'])
    p.add_argument('--seed-offset', type=int, default=0)
    p.add_argument('--chapter')
    p.add_argument('--from-chapter', type=int, default=1,
                   help='Start at this chapter number, preserving earlier imported recordings.')
    p.add_argument('--expand-numbers', action='store_true',
                   help='Spell numeric quantities in full to avoid abbreviated ages and counts.')
    p.add_argument('--only', nargs='+')
    p.add_argument('--minimum-audio-seconds', type=float, default=1., help='Lower only for explicitly isolated word repairs; full passages keep the default.')
    p.add_argument('--prompt-overrides', type=Path)
    p.add_argument('--temperature', type=float, default=.7)
    p.add_argument('--cache-limit-mb', type=int, default=512,
                   help='Bound unused MLX buffers so long batches do not pressure system swap.')
    args = p.parse_args()
    assert args.batch_size >= 1
    assert .25 <= args.minimum_audio_seconds <= 1.
    assert args.cache_limit_mb >= 0
    mx.set_cache_limit(args.cache_limit_mb * 1024 * 1024)
    root = args.root.resolve()
    out = root / 'gospels-v1'
    source = json.loads((out/'source.json').read_text())
    override_path = args.prompt_overrides or out/'prosody-overrides.json'
    overrides = json.loads(override_path.read_text()) if override_path.exists() else {}
    pronunciation_path = out/'pronunciation-overrides.json'
    pronunciations = json.loads(pronunciation_path.read_text()) if pronunciation_path.exists() else []
    jobs=[]
    for book in args.books:
        for chapter in source['chapters']:
            if chapter['book'] != book:
                continue
            if chapter['chapter'] < args.from_chapter:
                continue
            if args.chapter and chapter['id'] != args.chapter:
                continue
            for chunk in chapter['chunks']:
                directory = out / 'chapters' / chapter['id'] / 'passages'
                directory.mkdir(parents=True,exist_ok=True)
                identity = f'{chapter["id"]}-{chunk["index"]:03d}'
                if args.only and identity not in args.only:
                    continue
                signature=hashlib.sha256((ADAPTER_SHA+'\n'+chunk['text']).encode()).hexdigest()
                prompt = overrides.get(identity, chunk['text'])
                if args.expand_numbers:
                    prompt = re.sub(r'\b\d[\d,]*\b', lambda m: number_words(int(m[0].replace(',', ''))), prompt)
                # Literal source words can also occur as a respelling elsewhere
                # (for example, Luke's "inn" versus a repair of "in").
                if words(prompt) == words(chunk['text']):
                    canonical_prompt, used_pronunciations = prompt, []
                else:
                    canonical_prompt, used_pronunciations = restore_source_spellings(prompt, pronunciations)
                assert words(canonical_prompt) == words(chunk['text']), 'A generation prompt cannot change source words or numeric quantities'
                if prompt != chunk['text']:
                    signature = hashlib.sha256((signature+'\n'+prompt).encode()).hexdigest()
                job=dict(chunk,book=book,chapter=chapter['chapter'],chapter_id=chapter['id'],
                         id=identity,signature=signature,directory=directory,generation_text=prompt,
                         pronunciation_respellings=used_pronunciations)
                audio_path=directory/f'{chunk["index"]:03d}.wav'
                metadata_path=audio_path.with_suffix('.json')
                if metadata_path.exists() and audio_path.exists():
                    old=json.loads(metadata_path.read_text())
                    if old['signature']!=signature or old['audio_sha256']!=sha(audio_path):
                        raise RuntimeError('Existing passage differs: '+identity)
                    continue
                jobs.append(job)
    if args.limit:
        jobs=jobs[:args.limit]
    print(f'QUEUED {len(jobs)} passages; batch size {args.batch_size}',flush=True)
    if not jobs:
        return
    run=root/'voice-run-02'
    config=json.loads((run/'config.json').read_text())
    assert sha(run/'best.safetensors')==ADAPTER_SHA
    begun=time.time()
    print('Loading saved trained voice',flush=True)
    snapshot=root/'cache/huggingface/hub/models--mlx-community--Qwen3-TTS-12Hz-0.6B-Base-8bit/snapshots'/config['base_revision']
    model=load_model(str(snapshot))
    add_lora(model,config['rank'],config['layers'])
    model.load_weights(str(run/'best.safetensors'),strict=False)
    speaker=mx.load(str(run/'speaker.safetensors'))['embedding']
    embedding=model.talker.get_input_embeddings()
    assert not isinstance(embedding,nn.QuantizedEmbedding)
    weights=embedding.weight
    weights[3000]=speaker.reshape(-1).astype(weights.dtype)
    embedding.weight=weights
    model.config.talker_config.spk_id={'choirreading':3000}
    model.supported_speakers=['choirreading']
    model.eval()
    mx.eval(model.talker.parameters())
    print(f'MODEL_READY {time.time()-begun:.1f}s',flush=True)
    completed=0
    audio_seconds=0.
    started=time.time()
    group_size = len(jobs) if args.continuous else args.batch_size
    for offset in range(0,len(jobs),group_size):
        batch=jobs[offset:offset+group_size]
        batch_started=time.time()
        seed=20261024+int(hashlib.sha256('|'.join(j['id'] for j in batch).encode()).hexdigest()[:7],16)+args.seed_offset
        mx.random.seed(seed)
        queue_path = None
        if args.continuous:
            queue=dict(seed=seed,adapter_sha256=ADAPTER_SHA,base_revision=config['base_revision'],
                batch_size=args.batch_size,temperature=args.temperature,top_p=.9,
                repetition_penalty=1.05,max_tokens=900,
                jobs=[{k:j[k] for k in ['id','signature','generation_text']} for j in batch])
            queue_path=out/f'inference-queue-{seed}.json'
            if queue_path.exists():
                assert json.loads(queue_path.read_text())==queue, 'Saved inference queue differs'
            else:write_json(queue_path,queue)
            queue_hash=sha(queue_path)
            print(f'CONTINUOUS_QUEUE {len(batch)} passages; maximum {args.batch_size} active; receipt {queue_path}',flush=True)
            from bible_audio_continuous import generate
            results=generate(model,batch,args.batch_size,args.temperature)
        else:
            print('BATCH '+','.join(j['id'] for j in batch),flush=True)
            results=model.batch_generate(texts=[j['generation_text'] for j in batch],
                voices=['choirreading']*len(batch),lang_code='english',
                max_tokens=900,temperature=args.temperature,top_p=.9,repetition_penalty=1.05)
        seen=set()
        for result in results:
            index=result.sequence_idx
            assert index not in seen
            seen.add(index)
            job=batch[index]
            mx.eval(result.audio)
            audio=np.asarray(result.audio).reshape(-1)
            assert np.isfinite(audio).all() and len(audio)>model.sample_rate*args.minimum_audio_seconds
            assert np.sqrt(np.mean(audio**2))>.002
            if result.token_count>=900:
                raise RuntimeError('Generation length cap reached: '+job['id'])
            peak=float(np.abs(audio).max())
            gain=min(1.,.97/peak)
            audio=audio*gain
            path=job['directory']/f'{job["index"]:03d}.wav'
            # The standard-library writer also gives explicit OS errors on
            # removable disks, rather than libsndfile's generic System error.
            temporary=path.with_suffix('.wav.tmp')
            pcm=np.rint(np.clip(audio,-1.,1.)*32767).astype('<i2')
            with temporary.open('wb') as handle:
                with wave.open(handle,'wb') as writer:
                    writer.setnchannels(1)
                    writer.setsampwidth(2)
                    writer.setframerate(model.sample_rate)
                    writer.writeframes(pcm.tobytes())
            temporary.replace(path)
            metadata={k:v for k,v in job.items() if k!='directory'}
            metadata.update(mode='fine_tuned',adapter_sha256=ADAPTER_SHA,base_revision=config['base_revision'],
                conditioning='saved trained speaker embedding',seed=seed,batch_ids=None if args.continuous else [j['id'] for j in batch],
                sample_rate=model.sample_rate,seconds=len(audio)/model.sample_rate,tokens=result.token_count,
                peak_before_attenuation=peak,gain=gain,audio_sha256=sha(path),
                temperature=args.temperature,top_p=.9,repetition_penalty=1.05)
            if queue_path is not None:
                metadata.update(inference_queue=str(queue_path),inference_queue_sha256=queue_hash,
                    inference_queue_index=index,inference_batch_size=args.batch_size,
                    inference_scheduler='bounded continuous queue using the existing Qwen3 TTS batch session')
            write_json(path.with_suffix('.json'),metadata)
            completed+=1
            audio_seconds+=metadata['seconds']
            progress=dict(completed_this_run=completed,queued_this_run=len(jobs),
                audio_seconds_this_run=audio_seconds,elapsed_seconds=time.time()-started,
                last_completed=job['id'],peak_memory_gb=mx.get_peak_memory()/1e9)
            write_json(out/('repair-progress.json' if args.only else 'generation-progress.json'),progress)
            print(f'DONE {completed}/{len(jobs)} {job["id"]}: {metadata["seconds"]:.2f}s',flush=True)
            if args.continuous:mx.clear_cache()
        assert len(seen)==len(batch)
        print(f'BATCH_FINISHED {time.time()-batch_started:.1f}s; total audio {audio_seconds:.1f}s; elapsed {time.time()-started:.1f}s; peak {mx.get_peak_memory()/1e9:.2f}GB',flush=True)
        mx.clear_cache()
    print('SYNTHESIS_COMPLETE',flush=True)


if __name__=='__main__':
    main()
