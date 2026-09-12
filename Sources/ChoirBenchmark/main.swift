import Foundation
import Choir

/// Command-line entry point for the PRF-040 benchmark harness.
///
/// PRF-040 requires the harness to be part of the repository and to be run on
/// every reference device per release, with the report shipped alongside. This
/// makes it one command:
///
///     swift run choir-benchmark [--device R1|R2|R3|R4|R5] [--iterations N] [--output PATH]
///
/// The device is stated rather than detected wherever detection would be a
/// guess: an iPhone 13 and a current Pro are both "iOS" to this process, and
/// reporting the wrong one would compare a measurement against the wrong
/// target.

struct Options {
    var device: ReferenceDevice?
    var iterations = 5
    var outputPath: String?
    var json = false
    var intelligibility = false
    var voice: Voice = .isla
    var formant = false
    var sayText: String?
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())

    while let argument = arguments.first {
        arguments.removeFirst()
        switch argument {
        case "--device":
            guard let raw = arguments.first else { break }
            arguments.removeFirst()
            guard let device = ReferenceDevice(rawValue: raw.uppercased()) else {
                FileHandle.standardError.write(
                    Data("Unknown device '\(raw)'. Expected one of: \(ReferenceDevice.allCases.map(\.rawValue).joined(separator: ", "))\n".utf8))
                exit(2)
            }
            options.device = device
        case "--iterations":
            guard let raw = arguments.first, let value = Int(raw) else { break }
            arguments.removeFirst()
            options.iterations = max(1, value)
        case "--output":
            guard let path = arguments.first else { break }
            arguments.removeFirst()
            options.outputPath = path
        case "--json":
            options.json = true
        case "--intelligibility":
            options.intelligibility = true
        case "--formant":
            options.formant = true
        case "--say":
            guard let text = arguments.first else { break }
            arguments.removeFirst()
            options.sayText = text
        case "--voice":
            guard let raw = arguments.first else { break }
            arguments.removeFirst()
            guard let match = Voice.allCases.first(where: {
                $0.rawValue == raw || $0.displayName.lowercased() == raw.lowercased()
                    || "\($0)".lowercased() == raw.lowercased()
            }) else {
                FileHandle.standardError.write(Data("Unknown voice '\(raw)'\n".utf8))
                exit(2)
            }
            options.voice = match
        case "--help", "-h":
            print("""
            choir-benchmark — CHOIR performance harness (SRS PRF-040)

            Usage:
              swift run choir-benchmark [options]

            Options:
              --device R1|R2|R3|R4|R5   Reference device to compare targets against.
                                        Detected where unambiguous; state it otherwise.
              --iterations N            Timed repetitions per measurement (default 5).
              --output PATH             Write the report to PATH instead of stdout.
              --json                    Emit JSON instead of Markdown.
              --intelligibility         Run the QUA-004 intelligibility harness
                                        instead of the performance benchmark.
              --formant                 Use the rule-based formant pipeline
                                        instead of the mock one. This is the
                                        only built-in path that produces
                                        speech, so it is the only one an
                                        intelligibility run can measure.
              --say TEXT                Synthesize TEXT and write a WAV to
                                        --output (default choir.wav), then
                                        exit. Combine with --formant to get
                                        audible speech rather than a test tone.
              --voice NAME              Voice to measure (default ISLA).
              --help                    Show this message.
            """)
            exit(0)
        default:
            break
        }
    }
    return options
}

let options = parseOptions()
let device = options.device ?? ReferenceDevice.current

if device == nil {
    FileHandle.standardError.write(Data("""
    Note: this host is not a recognized reference device, so targets are not \
    applied and measurements are reported unjudged. Pass --device to compare \
    against a specific reference device's targets.

    """.utf8))
}

if BenchmarkReport.builtWithoutOptimization {
    FileHandle.standardError.write(Data("WARNING: this is an unoptimized build and its numbers are meaningless.\nRe-run with: swift run -c release choir-benchmark\n\n".utf8))
}

if let text = options.sayText {
    await runSay(text: text, voice: options.voice)
    exit(0)
}

if options.intelligibility {
    await runIntelligibility(voice: options.voice)
    exit(0)
}

let harness = BenchmarkHarness(iterations: options.iterations)
let report = await harness.run(device: device)

let output: String
if options.json {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    output = String(data: (try? encoder.encode(report)) ?? Data(), encoding: .utf8) ?? "{}"
} else {
    output = report.markdown()
}

if let path = options.outputPath {
    try? output.write(toFile: path, atomically: true, encoding: .utf8)
    print("Wrote benchmark report to \(path)")
} else {
    print(output)
}

// A failed target is a non-zero exit, so CI can gate on it once the numbers
// are meaningful. They are not yet: the acoustic model is a mock.
exit(report.allTargetsMet ? 0 : 1)


/// Runs the QUA-004 intelligibility harness.
///
/// Separated from the performance path because it needs a working recognizer
/// and, more importantly, a working acoustic model: against the current mock
/// it will score near zero, correctly, because the audio is not speech.
func runIntelligibility(voice: Voice) async {
    let transcriber = AppleSpeechTranscriber()

    guard await transcriber.isAvailable else {
        FileHandle.standardError.write(Data("""
        Intelligibility cannot be measured here.

        The recognizer '\(transcriber.identifier)' is unavailable. That usually \
        means speech-recognition authorization has not been granted, or the \
        on-device model for this locale is not installed.

        This is a failure to measure, not a score of zero.

        A plain SwiftPM executable has no Info.plist, so it cannot hold the \
        NSSpeechRecognitionUsageDescription that speech authorization \
        requires. Run this from a host app bundle that declares that key, or \
        pre-authorize speech recognition for the binary, to obtain a QUA-004 \
        number.

        """.utf8))
        exit(3)
    }

    let engine = ChoirEngine(pipeline: options.formant ? .formant() : nil)
    do {
        try await engine.initialize()
    } catch {
        FileHandle.standardError.write(Data("Engine failed to initialize: \(error)\n".utf8))
        exit(4)
    }

    let harness = IntelligibilityHarness()
    do {
        let report = try await harness.evaluate(
            voice: voice, engine: engine, transcriber: transcriber)

        var lines: [String] = []
        lines.append("# CHOIR Intelligibility Report (QUA-004)")
        lines.append("")
        lines.append("- **Voice:** \(report.voice.displayName)")
        lines.append("- **Recognizer:** \(report.transcriberIdentifier)")
        lines.append("- **Corpus:** \(harness.sentences.count) Harvard sentences")
        lines.append("- **Pipeline:** \(options.formant ? "rule-based formant" : "mock")")
        lines.append("")
        lines.append(report.summary)
        lines.append("")
        lines.append("| Reference | Transcribed | Accuracy |")
        lines.append("|---|---|---:|")
        for score in report.scores {
            lines.append(String(format: "| %@ | %@ | %.0f%% |",
                                score.reference,
                                score.hypothesis.isEmpty ? "_(nothing)_" : score.hypothesis,
                                score.wordAccuracy * 100))
        }
        lines.append("")
        if options.formant {
            lines.append("> Measured through the rule-based formant pipeline. This is a")
            lines.append("> development baseline, not a production voice: it says nothing")
            lines.append("> about the naturalness, distinctness or fatigue gates, which")
            lines.append("> still require trained models.")
        } else {
            lines.append("> The acoustic model is currently a mock and the vocoder is")
            lines.append("> Griffin-Lim. A near-zero score here is the correct result: the")
            lines.append("> audio is not speech. Re-run with --formant to measure the path")
            lines.append("> that speaks.")
        }

        let text = lines.joined(separator: "\n")
        // The report has to be writable to a file, not just stdout. Speech
        // authorization is only granted to a bundle launched through
        // LaunchServices, and `open` discards stdout, so a run that can
        // actually measure is a run whose output would otherwise be lost.
        if let path = options.outputPath {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        } else {
            print(text)
        }
    } catch {
        FileHandle.standardError.write(Data("Intelligibility run failed: \(error)\n".utf8))
        exit(5)
    }
}


/// Renders text to a WAV file.
///
/// The package had no way to produce an audio file from the command line, so
/// the only evidence that any of this makes sound was a unit test asserting a
/// buffer was non-empty. Pair this with `--formant` to hear speech; without it
/// the default pipeline writes its 200 Hz test tone.
func runSay(text: String, voice: Voice) async {
    let engine = ChoirEngine(pipeline: options.formant ? .formant() : nil)
    do {
        try await engine.initialize()
    } catch {
        FileHandle.standardError.write(Data("Engine failed to initialize: \(error)\n".utf8))
        exit(4)
    }

    let path = options.outputPath ?? "choir.wav"
    do {
        let audio = try await engine.synthesize(text: text, voice: voice)
        let data = try AudioEncoder().encodeWAV(audio)
        try data.write(to: URL(fileURLWithPath: path))

        let seconds = Double(audio.samples.count)
            / Double(audio.format.sampleRate * audio.format.channels)
        print(String(format: "Wrote %@ — %.2fs, %@, %@ pipeline",
                     path,
                     seconds,
                     voice.displayName,
                     options.formant ? "formant" : "mock"))
        if !options.formant {
            print("This is a 200 Hz test tone, not speech. Re-run with --formant.")
        }
    } catch {
        FileHandle.standardError.write(Data("Synthesis failed: \(error)\n".utf8))
        exit(5)
    }
}
