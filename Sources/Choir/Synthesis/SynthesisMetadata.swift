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
        self.startMs = startMs
        self.endMs = max(startMs, endMs)
    }

    /// Duration of the span in milliseconds.
    public var durationMs: Double { endMs - startMs }

    /// Whether `timeMs` falls inside this span, start-inclusive and
    /// end-exclusive so that adjacent spans never both match.
    public func contains(_ timeMs: Double) -> Bool {
        timeMs >= startMs && timeMs < endMs
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
        self.timeMs = timeMs
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
        self.totalDurationMs = totalDurationMs
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
        // Spans are ordered and non-overlapping, so binary search is safe.
        var low = 0
        var high = words.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let span = words[mid]
            if span.contains(timeMs) { return mid }
            if timeMs < span.startMs { high = mid - 1 } else { low = mid + 1 }
        }
        return nil
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
        var low = 0
        var high = phonemes.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let span = phonemes[mid]
            if span.contains(timeMs) { return mid < phonemes.count ? span : nil }
            if timeMs < span.startMs { high = mid - 1 } else { low = mid + 1 }
        }
        return nil
    }

    /// The index in ``sentences`` containing `wordIndex`, if any.
    public func sentenceIndex(containingWord wordIndex: Int) -> Int? {
        sentences.firstIndex { $0.contains(wordIndex) }
    }

    /// The time of the mark named `name`, if it was emitted.
    public func time(ofMark name: String) -> Double? {
        marks.first { $0.name == name }?.timeMs
    }
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
