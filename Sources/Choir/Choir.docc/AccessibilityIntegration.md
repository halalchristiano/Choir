# Accessibility Integration

Make synthesized audio cooperate with assistive technologies and provide an
equivalent visual channel.

## Audio coexistence

The consuming application owns its audio session. It must decide whether CHOIR
playback mixes, ducks, pauses, or stops when VoiceOver or other system speech
is active. Test with VoiceOver enabled, spoken notifications, calls, Siri,
alarms, route changes, and application backgrounding on each supported device.

Never repeatedly reactivate an audio session after the system or user has
interrupted it. Preserve playback position and apply the app's documented
resume policy.

## Highlighting from metadata

Use metadata-bearing synthesis and map the current playback offset to a word:

```swift
let result = try await engine.synthesizeWithMetadata(
    text: text,
    voice: .maeve
)

if let word = result.metadata.word(at: playbackTimeMs) {
    highlight(word.content)
}
```

Expose the full text to assistive technology as one coherent reading region;
do not move VoiceOver focus on every timing event. Visual highlighting should
meet contrast requirements and respect Reduce Motion. ``SynthesisStreamChunk``
provides live word/phoneme/mark timing; throttle visual updates to the display
rate instead of moving accessibility focus for every chunk.

## Caption parity

``TimelineAudioExporter`` emits per-line WAV, timing JSON, SRT, and WebVTT.
Retain the original script as the authoritative text alternative and test
reading order, speaker labels, non-speech cues, line length, timing, and
overlap. Audio alone must not be the only way to receive essential content.
