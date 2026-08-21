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
