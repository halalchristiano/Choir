import Foundation

/// One independently rendered line in a video/audio assembly timeline.
public struct TimelineAudioLine: Sendable, Equatable {
    public let fileName: String
    public let audio: AudioBuffer
    public let words: [TimedSpan]

    public init(fileName: String, audio: AudioBuffer, words: [TimedSpan]) {
        self.fileName = fileName
        self.audio = audio
        self.words = words
    }
}

public struct TimelineWordTiming: Sendable, Equatable, Codable {
    public let word: String
    public let startSeconds: Double
    public let endSeconds: Double
}

public struct TimelineSidecarEntry: Sendable, Equatable, Codable {
    public let file: String
    public let durationSeconds: Double
    public let wordTimings: [TimelineWordTiming]
}

public struct TimelineExportFile: Sendable, Equatable {
    public let name: String
    public let data: Data
}

/// In-memory AUD-040 export, which can be written atomically to a directory.
public struct TimelineExportBundle: Sendable, Equatable {
    public let audioFiles: [TimelineExportFile]
    public let timingJSON: Data
    public let srt: String
    public let webVTT: String

    /// Writes every artifact using atomic file replacement. File names are
    /// validated by ``TimelineAudioExporter`` before a bundle is created.
    @discardableResult
    public func write(to directory: URL) throws -> [URL] {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [URL] = []
        for file in audioFiles {
            let url = directory.appendingPathComponent(file.name, isDirectory: false)
            try file.data.write(to: url, options: .atomic)
            written.append(url)
        }
        let artifacts: [(String, Data)] = [
            ("timing.json", timingJSON),
            ("captions.srt", Data(srt.utf8)),
            ("captions.vtt", Data(webVTT.utf8)),
        ]
        for (name, data) in artifacts {
            let url = directory.appendingPathComponent(name, isDirectory: false)
            try data.write(to: url, options: .atomic)
            written.append(url)
        }
        return written
    }
}

/// Per-line WAV, timing JSON, SRT, and WebVTT generation for scripted video
/// assembly (AUD-040).
public struct TimelineAudioExporter: Sendable {
    private let encoder = AudioEncoder()

    public init() {}

    public func export(_ lines: [TimelineAudioLine]) throws -> TimelineExportBundle {
        guard !lines.isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "lines", reason: "At least one timeline line is required")
        }

        var files: [TimelineExportFile] = []
        var sidecar: [TimelineSidecarEntry] = []
        var cues: [CaptionCue] = []
        var timelineOffset = 0.0
        var names = Set<String>()

        for line in lines {
            try line.audio.validate()
            let name = try normalizedWAVFileName(line.fileName)
            guard names.insert(name.lowercased()).inserted else {
                throw ChoirError.invalidParameter(
                    parameter: "fileName", reason: "Timeline file names must be unique")
            }
            try validate(line.words, durationSeconds: line.audio.duration)

            files.append(TimelineExportFile(
                name: name,
                data: try encoder.encodeWAV(
                    line.audio,
                    metadata: AudioFileMetadata(title: name))))
            sidecar.append(TimelineSidecarEntry(
                file: name,
                durationSeconds: line.audio.duration,
                wordTimings: line.words.map {
                    TimelineWordTiming(
                        word: $0.content,
                        startSeconds: $0.startMs / 1_000,
                        endSeconds: $0.endMs / 1_000)
                }))

            let caption = safeCaptionText(line.words.map(\.content).joined(separator: " "))
            if !caption.isEmpty,
               let firstWord = line.words.first,
               let lastWord = line.words.last {
                cues.append(CaptionCue(
                    index: cues.count + 1,
                    startSeconds: timelineOffset + firstWord.startMs / 1_000,
                    endSeconds: timelineOffset + lastWord.endMs / 1_000,
                    text: caption))
            }
            timelineOffset += line.audio.duration
        }

        let jsonEncoder = JSONEncoder()
        jsonEncoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = try jsonEncoder.encode(sidecar)
        return TimelineExportBundle(
            audioFiles: files,
            timingJSON: json,
            srt: makeSRT(cues),
            webVTT: makeWebVTT(cues))
    }

    private func normalizedWAVFileName(_ proposed: String) throws -> String {
        let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("\0") else {
            throw ChoirError.invalidParameter(
                parameter: "fileName", reason: "Timeline file names must be safe base names")
        }
        return trimmed.lowercased().hasSuffix(".wav") ? trimmed : trimmed + ".wav"
    }

    private func validate(_ words: [TimedSpan], durationSeconds: Double) throws {
        var previousEnd = 0.0
        let durationMilliseconds = durationSeconds * 1_000
        for word in words {
            guard !word.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  word.startMs.isFinite,
                  word.endMs.isFinite,
                  word.startMs >= 0,
                  word.startMs <= word.endMs,
                  word.startMs >= previousEnd,
                  word.endMs <= durationMilliseconds + 0.001 else {
                throw ChoirError.invalidParameter(
                    parameter: "words",
                    reason: "Word timings must be named, finite, non-overlapping, and contained by their line")
            }
            previousEnd = word.endMs
        }
    }

    private func makeSRT(_ cues: [CaptionCue]) -> String {
        cues.map { cue in
            """
            \(cue.index)
            \(timestamp(cue.startSeconds, separator: ",")) --> \(timestamp(cue.endSeconds, separator: ","))
            \(cue.text)
            """
        }.joined(separator: "\n\n") + "\n"
    }

    private func safeCaptionText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "-->", with: "→")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private func makeWebVTT(_ cues: [CaptionCue]) -> String {
        let body = cues.map { cue in
            """
            \(timestamp(cue.startSeconds, separator: ".")) --> \(timestamp(cue.endSeconds, separator: "."))
            \(cue.text)
            """
        }.joined(separator: "\n\n")
        return "WEBVTT\n\n" + body + (body.isEmpty ? "" : "\n")
    }

    private func timestamp(_ seconds: Double, separator: Character) -> String {
        let totalMilliseconds = max(0, Int((seconds * 1_000).rounded()))
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60_000 % 60
        let wholeSeconds = totalMilliseconds / 1_000 % 60
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%02d:%02d:%02d", hours, minutes, wholeSeconds)
            + String(separator)
            + String(format: "%03d", milliseconds)
    }
}

private struct CaptionCue {
    let index: Int
    let startSeconds: Double
    let endSeconds: Double
    let text: String
}
