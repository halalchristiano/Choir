"""Keep a bounded Choir inference queue full while retaining passage identity."""
from types import SimpleNamespace


def completed_results(session, items, sample_rate):
    expected = {item.sequence_id for item in items}
    if len(expected) != len(items):
        raise ValueError('Duplicate passage sequence identifiers')
    session.add(items)
    seen = set()
    while not session.idle:
        for event in session.step():
            if event.error is not None:
                raise event.error
            if event.sequence_id not in expected or event.sequence_id in seen:
                raise ValueError('Unknown or duplicate completed passage')
            if not event.done or event.is_streaming_chunk:
                raise ValueError('Full-passage inference returned a partial chunk')
            if event.audio is None or event.samples <= 0 or event.sample_rate != sample_rate:
                raise ValueError('Completed passage has missing audio or a different sample rate')
            seen.add(event.sequence_id)
            yield SimpleNamespace(sequence_idx=event.sequence_id, audio=event.audio,
                                  token_count=event.token_count)
    if seen != expected:
        raise ValueError('Inference queue ended without every requested passage')


def generate(model, jobs, batch_size, temperature):
    from mlx_audio.tts.continuous import TTSBatchItem, TTSBatchOptions
    configured = (model.generate_config or {}).get('top_k')
    options = TTSBatchOptions(temperature=temperature, top_p=.9,
        top_k=50 if configured is None else configured, repetition_penalty=1.05,
        max_tokens=900, lang_code='english', stream=False, max_batch_size=batch_size)
    session = model.create_tts_batch_session(options)
    items = [TTSBatchItem(sequence_id=index, text=job['generation_text'], voice='choirreading')
             for index, job in enumerate(jobs)]
    yield from completed_results(session, items, model.sample_rate)
