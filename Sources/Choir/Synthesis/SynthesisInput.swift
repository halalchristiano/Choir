import Foundation

/// How input is to be interpreted (SRS TXT-003).
///
/// "Input shall be accepted as (a) plain text, (b) plain text with SSML-C
/// inline markup, or (c) a pre-phonemized sequence, selected explicitly by
/// API — never by guessing."
///
/// The prohibition is the point. Sniffing for a `<` to decide whether markup
/// is present makes `"5 < 7"` unpredictable and means a document containing
/// one stray bracket is read differently from the same document without it.
/// The caller states the mode; the engine never infers it.
public enum SynthesisInput: Sendable, Equatable {
    /// Plain text. Markup characters are spoken literally, not parsed.
    case plainText(String)

    /// Plain text carrying SSML-C inline markup (TXT-040).
    case markup(String)

    /// A fully specified phoneme sequence, bypassing the front end (TXT-050).
    ///
    /// Symbols must come from the documented inventory of ``PhonemeInventory``.
    case phonemes([Phoneme])

    /// The text carried by this input, or `nil` for a phoneme sequence.
    public var text: String? {
        switch self {
        case .plainText(let text), .markup(let text): return text
        case .phonemes: return nil
        }
    }

    /// Whether the input is empty and cannot be synthesized.
    public var isEmpty: Bool {
        switch self {
        case .plainText(let text), .markup(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .phonemes(let phonemes):
            return phonemes.isEmpty
        }
    }

    /// Validates a pre-phonemized sequence against the documented inventory
    /// (TXT-024, TXT-050).
    ///
    /// - Returns: the symbols that are not part of the inventory.
    public var unknownPhonemeSymbols: [String] {
        guard case .phonemes(let phonemes) = self else { return [] }
        return phonemes.map(\.symbol).filter { !PhonemeInventory.isValidIPA($0) }
    }
}

/// A predicted duration, without performing synthesis (SRS SYN-010).
///
/// "The engine shall expose a lightweight duration estimate API (predicted
/// speech duration for text+voice+rate without full synthesis, ±10% accuracy)
/// for layout, pagination, and video planning."
public struct DurationEstimate: Sendable, Equatable {
    /// Predicted duration in seconds.
    public let seconds: Double

    /// Syllables the estimate is based on.
    public let syllables: Int

    /// Breath groups the text divides into (TXT-031).
    public let breathGroupCount: Int

    /// Pause time contributed by phrase boundaries, in seconds.
    public let pauseSeconds: Double

    public init(seconds: Double, syllables: Int, breathGroupCount: Int, pauseSeconds: Double) {
        self.seconds = seconds
        self.syllables = syllables
        self.breathGroupCount = breathGroupCount
        self.pauseSeconds = pauseSeconds
    }

    /// Duration in milliseconds.
    public var milliseconds: Double { seconds * 1000 }
}

/// Estimates speech duration without synthesizing (SRS SYN-010).
///
/// Works from the voice's designed tempo (`VOX-P-001`) and a syllable count,
/// plus the pauses the segmenter's phrase boundaries imply. It deliberately
/// does not run the acoustic model: the requirement asks for a *lightweight*
/// estimate for layout and pagination, where being fast matters more than
/// being exact, and ±10% is the stated tolerance.
public struct DurationEstimator: Sendable {
    private let segmenter: SentenceSegmenter
    private let normalizer: TextNormalizer

    public init(
        segmenter: SentenceSegmenter = SentenceSegmenter(),
        normalizer: TextNormalizer = TextNormalizer()
    ) {
        self.segmenter = segmenter
        self.normalizer = normalizer
    }

    /// Estimates how long `text` takes to speak in `voice` at `rate`.
    public func estimate(
        text: String,
        voice: Voice,
        rate: Double = 1.0
    ) -> DurationEstimate {
        // Normalize first: "$1,250" is five syllables as written and eight
        // spoken, and layout wants the spoken length.
        let normalized = normalizer.normalize(text)
        let groups = segmenter.segment(
            normalized,
            syllablesPerSecond: voice.profile.tempo
        )

        let syllables = groups.reduce(0) { $0 + $1.estimatedSyllables }
        let effectiveTempo = max(0.1, voice.profile.tempo * max(0.1, rate))
        let speechSeconds = Double(syllables) / effectiveTempo

        // Boundaries contribute pause time, scaled by rate as pauses shorten
        // with faster speech.
        let pauseSeconds = groups.reduce(0.0) { total, group in
            total + group.boundary.nominalPauseMs / 1000 / max(0.1, rate)
        }

        return DurationEstimate(
            seconds: speechSeconds + pauseSeconds,
            syllables: syllables,
            breathGroupCount: groups.count,
            pauseSeconds: pauseSeconds
        )
    }
}
