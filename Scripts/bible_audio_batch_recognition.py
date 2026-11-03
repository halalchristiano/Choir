"""Batch Whisper's first decode while retaining its complete transcribe routine.

This is a single-process, single-thread helper for unprompted English clips of
at most 30 seconds. It accepts audio only, never expected passage text. The
installed mlx-whisper implementation still performs segmentation, any further
decoding, word alignment, punctuation handling and transcript construction.
"""
import dataclasses
import hashlib
import importlib
import time
from pathlib import Path

import mlx.core as mx
import numpy as np
from mlx_whisper.audio import N_FRAMES, N_SAMPLES, log_mel_spectrogram, pad_or_trim
from mlx_whisper.decoding import DecodingOptions

_transcription = importlib.import_module('mlx_whisper.transcribe')


def _same(left, right):
    return left.shape == right.shape and left.dtype == right.dtype and bool(mx.array_equal(left, right))


def transcribe_batch(audio, model_path):
    """Return raw original transcribe outputs and explicit cache-use receipts."""
    assert 1 <= len(audio) <= 8
    assert all(isinstance(a, np.ndarray) and a.ndim == 1 and a.dtype == np.float32
               and 0 < len(a) <= 30 * 16000 and np.isfinite(a).all() for a in audio)
    model = _transcription.ModelHolder.get_model(str(model_path), mx.float16)
    mels = []
    for samples in audio:
        full = log_mel_spectrogram(samples, n_mels=model.dims.n_mels, padding=N_SAMPLES)
        # Match transcribe's first window exactly, including its zero padding in
        # mel space. Raw-audio silence padding is not interchangeable with this.
        frames = full.shape[-2] - N_FRAMES
        mels.append(pad_or_trim(full[:min(frames, N_FRAMES)], N_FRAMES, axis=-2).astype(mx.float16))
    options = DecodingOptions(language='en', temperature=0., prompt=[], fp16=True)
    expected_options = dataclasses.asdict(options)
    started = time.time()
    decoded = model.decode(mx.stack(mels), options)
    decode_seconds = time.time() - started
    assert len(decoded) == len(audio)
    model_class = type(model)
    original_decode = model_class.decode
    original_alignment = model_class.forward_with_cross_qk
    implementation = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    results = []
    for index, (samples, mel, result) in enumerate(zip(audio, mels, decoded)):
        counters = dict(firstDecodeReused=0, alignmentEncoderReused=0, furtherDecodes=0)

        def reuse_decode(instance, incoming, incoming_options=DecodingOptions(), **kwargs):
            if instance is model and not counters['firstDecodeReused']:
                assert not kwargs and dataclasses.asdict(incoming_options) == expected_options
                assert _same(incoming, mel), 'The cached decode belongs to a different audio window'
                counters['firstDecodeReused'] += 1
                return result
            counters['furtherDecodes'] += 1
            return original_decode(instance, incoming, incoming_options, **kwargs)

        def reuse_alignment(instance, incoming, tokens):
            if instance is model and incoming.shape[0] == 1 and _same(incoming[0], mel):
                counters['alignmentEncoderReused'] += 1
                logits, _, cross_qk = instance.decoder(tokens, result.audio_features[None])
                return logits, cross_qk
            return original_alignment(instance, incoming, tokens)

        model_class.decode = reuse_decode
        model_class.forward_with_cross_qk = reuse_alignment
        try:
            transcript = _transcription.transcribe(samples, path_or_hf_repo=str(model_path), language='en',
                temperature=0., condition_on_previous_text=False, word_timestamps=True, verbose=None,
                initial_prompt=None, no_speech_threshold=None)
            assert counters['firstDecodeReused'] == 1
        finally:
            model_class.decode = original_decode
            model_class.forward_with_cross_qk = original_alignment
        results.append((transcript, dict(**counters, batchSize=len(audio), batchIndex=index,
            batchDecodeSeconds=decode_seconds, implementationSHA256=implementation,
            method='Batched unprompted first decode; original mlx-whisper transcribe and word timing; reuse encoded features only for the identical mel window.')))
    return results
