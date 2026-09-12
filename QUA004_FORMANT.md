# QUA-004 intelligibility measurement — rule-based formant path

**Measured:** 12 September 2026
**Build:** v0.17.0, release configuration
**Host:** macOS 26.3, Apple Silicon
**Recognizer:** Apple Speech, forced on-device (`supportsOnDeviceRecognition`)
**Reproduce:**

```bash
swift build -c release
Scripts/make_intelligibility_app.sh build
open build/ChoirIntelligibility.app --args \
    --formant --intelligibility --voice orion --output qua004.md
```

The app bundle exists because speech authorization requires
`NSSpeechRecognitionUsageDescription` in an `Info.plist`, and a SwiftPM
executable has neither. The bundle must be launched through LaunchServices;
running the binary directly from a shell attributes the request to the terminal
and TCC terminates the process. See `Scripts/make_intelligibility_app.sh`.

## Result


- **Voice:** ORION
- **Recognizer:** Apple Speech (on-device)
- **Corpus:** 20 Harvard sentences
- **Pipeline:** rule-based formant

ORION (defaultParameters, Apple Speech (on-device)): 8.2% word accuracy against a 98% target — FAIL

| Reference | Transcribed | Accuracy |
|---|---|---:|
| The birch canoe slid on the smooth planks. | Right | 0% |
| Glue the sheet to the dark blue background. | Dora to the door to red | 25% |
| It's easy to tell the depth of a well. | Where | 0% |
| These days a chicken leg is a rare dish. | Please | 0% |
| Rice is often served in round bowls. | Rise is all round | 29% |
| The juice of lemons makes fine punch. | 185 | 0% |
| The box was thrown beside the parked truck. | Lonely about to run | 0% |
| The hogs were fed chopped corn and garbage. | Where are you going | 0% |
| Four hours of steady work faced us. | Call daddy later | 0% |
| A large size in stockings is hard to sell. | Laura come to | 11% |
| The boy was there when the sun rose. | I was there when the sun roll | 62% |
| A rod is used to catch pink salmon. | Play Raja will do that we travel | 0% |
| The source of the huge river is the clear spring. | There's all of the news where that will rain | 20% |
| Kick the ball straight and follow through. | Play Baru | 0% |
| Help the woman get back to her feet. | Hello try to hurry | 12% |
| A pot of tea helps to pass the evening. | Baja weather | 0% |
| Smoky fires lack flame and heat. | Slowly by your leg will be | 0% |
| The soft cushion broke the man's fall. | Brought | 0% |
| The salt breeze came across from the sea. | There's real game robbery | 0% |
| The girl at the booth sold fifty bonds. | Play | 0% |

> Measured through the rule-based formant pipeline. This is a
> development baseline, not a production voice: it says nothing
> about the naturalness, distinctness or fatigue gates, which
> still require trained models.
## Reading this number

8.2% is a machine-listener score. Apple's recognizer is trained on natural human
speech, and rule-based formant output is far outside that distribution, so a
human listener would very likely score higher. The number is not a measurement
of how a person would experience this audio.

What it does establish:

- The path is not intelligible by the QUA-004 gate, which is the gate the SRS
  actually specifies. Documentation that called the formant output
  "intelligible" was asserting something no one had measured, and is corrected.
- The output is genuinely speech, not a tone. The recognizer returns real words,
  and one sentence reached 62% ("The boy was there when the sun rose" was
  transcribed "I was there when the sun roll"). A test tone returns nothing.
- QUA-004 is now measurable at all. It previously could not run: the harness
  always constructed a mock-backed engine, and the tool aborted on TCC before
  reporting anything.

The obvious next measurement is the same corpus against a trained acoustic model
and vocoder, which is what the 98% target was written for.
