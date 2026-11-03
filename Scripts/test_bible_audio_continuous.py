import unittest
from types import SimpleNamespace
from bible_audio_continuous import completed_results


def event(identity, **changes):
    data = dict(sequence_id=identity, audio=f'audio-{identity}', samples=24000,
        sample_rate=24000, token_count=13, error=None, done=True, is_streaming_chunk=False)
    data.update(changes)
    return SimpleNamespace(**data)


class Session:
    def __init__(self, steps): self.steps=steps; self.items=None
    def add(self, items): self.items=items
    @property
    def idle(self): return not self.steps
    def step(self): return self.steps.pop(0)


class ContinuousAudioChecks(unittest.TestCase):
    def test_out_of_order_completion_preserves_text_audio_identity(self):
        session=Session([[event(2)],[],[event(0),event(1)]])
        items=[SimpleNamespace(sequence_id=i,text=f'text-{i}') for i in range(3)]
        results=list(completed_results(session,items,24000))
        self.assertEqual([(r.sequence_idx,r.audio) for r in results],[(2,'audio-2'),(0,'audio-0'),(1,'audio-1')])
        self.assertEqual(session.items,items)

    def test_missing_duplicate_and_unrequested_passages_are_rejected(self):
        items=[SimpleNamespace(sequence_id=i) for i in range(2)]
        for steps in [[[event(0)]],[[event(0),event(0)]],[[event(2)]]]:
            with self.subTest(steps=steps),self.assertRaises(ValueError):
                list(completed_results(Session(steps),items,24000))

    def test_partial_empty_and_wrong_sample_rate_audio_are_rejected(self):
        items=[SimpleNamespace(sequence_id=0)]
        for changes in [dict(done=False),dict(is_streaming_chunk=True),dict(audio=None),dict(samples=0),dict(sample_rate=16000)]:
            with self.subTest(changes=changes),self.assertRaises(ValueError):
                list(completed_results(Session([[event(0,**changes)]]),items,24000))

    def test_inference_errors_are_propagated(self):
        failure=RuntimeError('model failed')
        with self.assertRaisesRegex(RuntimeError,'model failed'):
            list(completed_results(Session([[event(0,error=failure)]]),[SimpleNamespace(sequence_id=0)],24000))


if __name__=='__main__':unittest.main()
