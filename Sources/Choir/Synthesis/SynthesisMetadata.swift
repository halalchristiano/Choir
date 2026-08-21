import Foundation

/// Timing for one unit of speech, in milliseconds from the start of the audio.
public struct TimedSpan: Sendable, Equatable, Codable {
    /// The text or phoneme symbol this span covers.
    public let content: String

    /// Start offset in milliseconds.
    public let startMs: Double

    /// End offset in milliseconds.
    public let endMs: Double

    public init(content: String, startMs: Double, endMs: Double) {
        self.content = content
        let safeStart = startMs.isFinite ? max(0, startMs) : 0
        let safeEnd = endMs.isFinite ? max(safeStart, endMs) : safeStart
        self.startMs = safeStart
        self.endMs = safeEnd
    }

    /// Duration of the span in milliseconds.
    public var durationMs: Double { endMs - startMs }

    public var midpointMs: Double { startMs + durationMs / 2 }

    public var isEmpty: Bool { durationMs == 0 }

    /// Whether `timeMs` falls inside this span, start-inclusive and
    /// end-exclusive so that adjacent spans never both match.
    public func contains(_ timeMs: Double) -> Bool {
        timeMs.isFinite && timeMs >= startMs && timeMs < endMs
    }

    /// Progress through the span, clamped to 0...1.
    public func progress(at timeMs: Double) -> Double {
        guard timeMs.isFinite, durationMs > 0 else { return 0 }
        return max(0, min(1, (timeMs - startMs) / durationMs))
    }
}

/// The position of an SSML-C `<mark>` in the synthesized audio.
public struct MarkPosition: Sendable, Equatable, Codable {
    /// The `name` attribute of the mark.
    public let name: String

    /// Offset in milliseconds from the start of the audio.
    public let timeMs: Double

    public init(name: String, timeMs: Double) {
        self.name = name
        self.timeMs = timeMs.isFinite ? max(0, timeMs) : 0
    }
}

/// A non-fatal observation made while synthesizing.
///
/// Carries the markup warnings TXT-041 requires to be returned alongside the
/// result rather than thrown.
public struct SynthesisDiagnostic: Sendable, Equatable, Codable {
    public enum Severity: String, Sendable, Equatable, Codable {
        case info
        case warning
    }

    public let severity: Severity
    public let message: String

    public init(severity: Severity = .warning, message: String) {
        self.severity = severity
        self.message = message
    }
}

/// Timing and provenance data accompanying every synthesis result.
///
/// Implements SRS SYN-005 (MUST): every synthesis result shall include total
/// duration, per-word and per-phoneme timing, sentence boundaries, the
/// positions of all `<mark>` tags, the effective parameter set, and any
/// diagnostics.
///
/// The specification is emphatic that this is "a core deliverable, not an
/// extra", because verse highlighting in THE ONE, subtitle and caption sync,
/// lip-sync in games, and timeline placement in video all depend on it.
public struct SynthesisMetadata: Sendable, Equatable, Codable {
    /// Total duration of the synthesized audio in milliseconds.
    public let totalDurationMs: Double

    /// Per-word timing, in speaking order.
    public let words: [TimedSpan]

    /// Per-phoneme timing, in speaking order.
    public let phonemes: [TimedSpan]

    /// Index ranges into ``words`` delimiting each sentence.
    public let sentences: [Range<Int>]

    /// Positions of every `<mark>` tag encountered.
    public let marks: [MarkPosition]

    /// The parameters actually used, after clamping and style application.
    public let effectiveParameters: SynthesisParameters

    /// The voice used.
    public let voice: Voice

    /// Non-fatal observations, including markup warnings (TXT-041).
    public let diagnostics: [SynthesisDiagnostic]

    public init(
        totalDurationMs: Double,
        words: [TimedSpan] = [],
        phonemes: [TimedSpan] = [],
        sentences: [Range<Int>] = [],
        marks: [MarkPosition] = [],
        effectiveParameters: SynthesisParameters = SynthesisParameters(),
        voice: Voice,
        diagnostics: [SynthesisDiagnostic] = []
    ) {
        self.totalDurationMs = totalDurationMs.isFinite ? max(0, totalDurationMs) : 0
        self.words = words
        self.phonemes = phonemes
        self.sentences = sentences
        self.marks = marks
        self.effectiveParameters = effectiveParameters
        self.voice = voice
        self.diagnostics = diagnostics
    }

    // MARK: - Queries

    /// The index in ``words`` being spoken at `timeMs`, if any.
    ///
    /// This is the primitive behind verse highlighting and karaoke-style
    /// follow-along.
    public func wordIndex(at timeMs: Double) -> Int? {
        words.firstIndex { $0.contains(timeMs) }
    }

    /// The word being spoken at `timeMs`, if any.
    public func word(at timeMs: Double) -> TimedSpan? {
        wordIndex(at: timeMs).map { words[$0] }
    }

    /// The phoneme being spoken at `timeMs`, if any.
    ///
    /// Used for lip-sync, where the viseme follows the phoneme rather than
    /// the word.
    public func phoneme(at timeMs: Double) -> TimedSpan? {
        phonemes.first { $0.contains(timeMs) }
    }

    /// The index in ``sentences`` containing `wordIndex`, if any.
    public func sentenceIndex(containingWord wordIndex: Int) -> Int? {
        sentences.firstIndex { $0.contains(wordIndex) }
    }

    /// The time of the mark named `name`, if it was emitted.
    public func time(ofMark name: String) -> Double? {
        marks.first { $0.name == name }?.timeMs
    }

    /// Every occurrence of a mark name, preserving emission order.
    public func times(ofMark name: String) -> [Double] {
        marks.filter { $0.name == name }.map(\.timeMs)
    }

    public var durationSeconds: Double { totalDurationMs / 1000 }

    public var warnings: [SynthesisDiagnostic] {
        diagnostics.filter { $0.severity == .warning }
    }

    public var informationalDiagnostics: [SynthesisDiagnostic] {
        diagnostics.filter { $0.severity == .info }
    }

    /// Structural issues that make timing metadata inconsistent.
    public var validationIssues: [String] {
        var issues: [String] = []
        func inspect(_ spans: [TimedSpan], label: String) {
            for (index, span) in spans.enumerated() {
                if span.endMs > totalDurationMs {
                    issues.append("\(label) \(index) ends after total duration")
                }
                if index > 0, span.startMs < spans[index - 1].startMs {
                    issues.append("\(label) spans are not ordered at index \(index)")
                }
            }
        }
        inspect(words, label: "word")
        inspect(phonemes, label: "phoneme")
        for (index, range) in sentences.enumerated() where range.lowerBound < 0 || range.upperBound > words.count {
            issues.append("sentence \(index) references words outside the word list")
        }
        for mark in marks where mark.timeMs > totalDurationMs {
            issues.append("mark '\(mark.name)' occurs after total duration")
        }
        return issues
    }

    public var isStructurallyValid: Bool { validationIssues.isEmpty }
}

/// Audio together with the metadata SYN-005 requires.
///
/// Returned by the metadata-bearing synthesis entry points. The plain
/// `AudioBuffer`-returning calls remain for callers that do not need timing.
public struct SynthesisResult: Sendable {
    public let audio: AudioBuffer
    public let metadata: SynthesisMetadata

    public init(audio: AudioBuffer, metadata: SynthesisMetadata) {
        self.audio = audio
        self.metadata = metadata
    }
}

/// Timing information delivered alongside one streaming audio chunk (STR-004).
///
/// Spans use the request-wide timeline, not offsets local to the chunk. A span
/// is included when it intersects the chunk, so consumers can begin a word or
/// viseme on one chunk and finish it on the next without reconstructing the
/// global clock.
public struct StreamingMetadataUpdate: Sendable, Equatable {
    /// Start of the corresponding audio chunk, in milliseconds.
    public let startMs: Double

    /// End of the corresponding audio chunk, in milliseconds.
    public let endMs: Double

    /// Word spans intersecting this chunk.
    public let words: [TimedSpan]

    /// Phoneme spans intersecting this chunk.
    public let phonemes: [TimedSpan]

    /// Marks whose positions fall within this chunk.
    public let marks: [MarkPosition]

    /// Number of sentence ranges completed by the end of this chunk.
    public let completedSentenceCount: Int

    public init(
        startMs: Double,
        endMs: Double,
        words: [TimedSpan] = [],
        phonemes: [TimedSpan] = [],
        marks: [MarkPosition] = [],
        completedSentenceCount: Int = 0
    ) {
        let start = startMs.isFinite ? max(0, startMs) : 0
        let end = endMs.isFinite ? max(start, endMs) : start
        self.startMs = start
        self.endMs = end
        self.words = words
        self.phonemes = phonemes
        self.marks = marks
        self.completedSentenceCount = max(0, completedSentenceCount)
    }
}

/// One incremental streaming delivery: PCM plus synchronized timing metadata.
public struct SynthesisStreamChunk: Sendable, Equatable {
    public let audio: AudioChunk
    public let metadata: StreamingMetadataUpdate

    public init(audio: AudioChunk, metadata: StreamingMetadataUpdate) {
        self.audio = audio
        self.metadata = metadata
    }

    public var isFinal: Bool { audio.isFinal }
}
