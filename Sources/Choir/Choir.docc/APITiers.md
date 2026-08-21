# API Tiers

Choose the smallest public surface that gives the application the control it
needs.

## Tier 1: synthesize or speak

Use ``Choir`` for isolated requests:

```swift
let buffer = try await Choir.synthesize(
    "Keep the result in memory.",
    voice: .tamsin,
    parameters: SynthesisParameters(rate: 1.05, seed: 7)
)

try await Choir.speak("Synthesize and play.", voice: .tamsin)
```

This tier creates and initializes an engine for each call. It is convenient,
but not the efficient choice for repeated requests.

## Tier 2: reusable engine

Use ``ChoirEngine`` for lifecycle control, batch work, export, verification,
and metadata:

```swift
let engine = ChoirEngine()
try await engine.initialize()

let health = await engine.verify()
guard health.isHealthy else {
    throw ChoirError.modelLoadFailed(reason: health.summary)
}

let result = try await engine.synthesizeWithMetadata(
    text: "Metadata supports highlighting and timeline placement.",
    voice: .maeve,
    parameters: SynthesisParameters(seed: 2026)
)
```

`verify()` checks the development installation and runs a mock-backed smoke
render. It does not establish intelligibility, naturalness, real-time factor,
memory, battery, or physical-device conformance.

For independent items, select a partial-failure policy:

```swift
let batch = try await engine.synthesizeBatch(
    texts: ["First line.", "Second line."],
    voice: .orion,
    policy: .continueAndReport
)

for failure in batch.failures {
    print(failure.index, failure.error?.code ?? "unknown")
}
```

## Tier 3: explicit input, timing, and chunks

Use explicit ``SynthesisInput`` values for markup and phoneme workflows, and
``SynthesisMetadata`` for timing queries:

```swift
let result = try await engine.synthesize(
    input: .markup(
        #"<speak><mark name="start"/>In the beginning.</speak>"#
    ),
    voice: .alaric,
    parameters: SynthesisParameters(seed: 1)
)

let startMs = result.metadata.time(ofMark: "start")
```

Chunk delivery uses an async callback:

```swift
try await engine.streamSynthesis(
    text: "Render and deliver this request phrase by phrase.",
    voice: .isla,
    options: StreamingOptions(chunkSize: 2_400)
) { chunk in
    await outputQueue.enqueue(chunk)
}
```

The current implementation prepares request-wide text and prosody first, then
runs acoustic/vocoder inference one natural phrase at a time. It emits each
phrase before inference for the next phrase begins. Device latency, real-time
factor, and thermal behavior still require production-model measurements.

## Inject a production pipeline

The package provides protocols, not trained production assets:

```swift
let pipeline = SynthesisPipeline(
    acousticModel: myAcousticModel,
    vocoder: myVocoder
)

let engine = ChoirEngine(pipeline: pipeline)
try await engine.initialize()
```

The injected values conform to ``AcousticModelProtocol`` and
``VocoderProtocol``. Their model provenance, asset integrity, output quality,
and device measurements remain the integrator's responsibility until CHOIR
ships validated production assets.
