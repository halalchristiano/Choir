"""Retain Qwen's batched KV cache until active passage membership changes.

The installed mlx-audio session extracts and merges every request's cache at
every token. Reusing that same cache avoids the copies; the trained model,
sampling, passage state and audio decoder still come from mlx-audio.
The advance loop is adapted from mlx_audio.tts.models.qwen3_tts.continuous_batching
(Copyright 2025 Prince Canuma and contributors, MIT license).
"""
import mlx.core as mx
from mlx_audio.tts.models.qwen3_tts.continuous_batching import Qwen3TTSBatchSession


class CachedQwen3TTSBatchSession(Qwen3TTSBatchSession):
    def __init__(self, model, options):
        super().__init__(model, options)
        self._retained_cache = None
        self._retained_ids = None

    def _materialize_cache(self):
        if self._retained_cache is None:
            return
        assert self._retained_ids == tuple(state.sequence_id for state in self._active)
        rows = self._extract_batch_cache_rows(self._retained_cache, len(self._active))
        for state, cache in zip(self._active, rows):
            state.cache = cache
        self._retained_cache = None
        self._retained_ids = None

    def _admit_pending(self):
        self._materialize_cache()
        return super()._admit_pending()

    def cancel(self, sequence_id):
        self._materialize_cache()
        return super().cancel(sequence_id)

    def _advance_active(self):
        states = list(self._active)
        identities = tuple(state.sequence_id for state in states)
        if self._retained_cache is None:
            cache = self._merge_state_caches(states)
        else:
            assert self._retained_ids == identities
            cache = self._retained_cache
        # Match the parent's zero/one attention mask, including left padding.
        attention_mask = (mx.arange(cache[0]._idx + 1)[None, :] >=
                          cache[0].left_padding[:, None]).astype(mx.float32)
        input_embeds = mx.concatenate([state.input_embeds for state in states], axis=0)
        logits, hidden = self.model.talker(input_embeds, cache=cache,
                                          attention_mask=attention_mask)
        next_token_batch, code_tokens, all_codes = self._sample_code_tokens(
            logits, hidden,
            generated_tokens_per_seq=[state.generated_token_ids for state in states])
        finished_cpu = (next_token_batch[:, 0] == self.eos_token_id).tolist()
        token_ids_cpu = next_token_batch[:, 0].tolist()
        next_input_embeds = self._next_input_embeds_for_states(states, code_tokens)
        events = []
        still_active = []
        for index, state in enumerate(states):
            state.input_embeds = next_input_embeds[index:index+1]
            if not finished_cpu[index]:
                state.generated_token_ids.append(token_ids_cpu[index])
                state.generated_codes.append(all_codes[index:index+1])
                state.trailing_idx += 1
            if finished_cpu[index] or len(state.generated_codes) >= self.options.max_tokens:
                events.append(self._decode_state(state))
            else:
                still_active.append(state)
        if events:
            # Only continuing requests need cache rows. Membership changes are
            # uncommon compared with token steps, so copy only at this boundary.
            for index, state in enumerate(states):
                if not finished_cpu[index] and len(state.generated_codes) < self.options.max_tokens:
                    state.cache = [layer.extract(index) for layer in cache]
            self._retained_cache = None
            self._retained_ids = None
        else:
            self._retained_cache = cache
            self._retained_ids = identities
        self._active = still_active
        return events
