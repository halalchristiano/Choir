# Natural-language speech planning

CHOIR includes a deterministic, on-device English NLP pass that translates
normalized prose into a typed `ContextualSpeechPlan`. The plan sits between
text normalization and phoneme-level prosody:

1. normalize text and preserve structural punctuation;
2. infer sentence intent, restrained emotion, dialogue spans, clause breaks,
   and contrastive focus;
3. phonemize and promote stress on contextually focused words;
4. realize the plan as local duration, pitch, energy, accent, pause, and
   boundary-tone changes;
5. pass the annotated sequence to the acoustic model and vocoder.

The pass is rule-based rather than generative. It has no network dependency,
does not send text to a service, does not claim to infer an author's actual
mental state, and produces the same plan for the same normalized words.

## What it recognizes

- statements, questions, exclamations, commands, and fragments;
- conservative lexical signals for joyful, sad, angry, fearful, tender, solemn,
  and neutral delivery;
- quoted dialogue separately from surrounding narration;
- contrastive markers such as `not`, `but`, `only`, `instead`, and `however`;
- intensifiers such as `truly`, `very`, and `absolutely`;
- clause boundaries at commas, semicolons, colons, dashes, and discourse
  transitions;
- sentence-final nuclear stress and question/statement boundary tones.

## Inspect a plan

```swift
let planner = ContextualSpeechPlanner()
let plan = planner.plan(normalizedWords: [
    "i", "did", "not", "say", "he", "left.",
])

plan.utterances.first?.intent        // .statement
plan.cue(forWord: 2)?.emphasis      // .moderate ("not")
plan.cue(forWord: 3)?.emphasis      // .strong ("say")
```

The ordinary front end attaches the plan automatically:

```swift
let transcript = try LinguisticFrontend().process("Are you afraid?")
transcript.speechPlan?.utterances.first?.intent   // .question
transcript.speechPlan?.utterances.first?.emotion  // .fearful
```

## Disable or narrow inference

Literal readers and applications with externally authored prosody can disable
the pass without changing the rest of the synthesis pipeline:

```swift
let frontend = LinguisticFrontend(
    speechPlanner: ContextualSpeechPlanner(configuration: .disabled)
)
```

Capabilities can also be switched independently:

```swift
let configuration = NaturalLanguageProcessingConfiguration(
    detectsEmotion: false,
    detectsDialogue: true
)
let frontend = LinguisticFrontend(
    speechPlanner: ContextualSpeechPlanner(configuration: configuration)
)
```

## Scope and limitations

The first implementation is English-only and deliberately conservative. It
does not perform general reasoning, dependency parsing, coreference resolution,
speaker identification, sarcasm detection, or unrestricted sentiment analysis.
Ambiguous language remains neutral. Explicit SSML and caller parameters remain
the authoritative controls.

The typed plan is intentionally independent of the inference implementation.
A future Core ML classifier can produce the same `ContextualSpeechPlan` without
requiring changes to the prosody or acoustic-model interfaces.

NLP improves how a capable speech model would deliver text; it does not replace
the production acoustic model, neural vocoder, voice assets, or listening tests
that CHOIR still needs before it can produce production speech.
