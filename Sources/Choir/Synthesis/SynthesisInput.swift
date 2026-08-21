import Foundation

/// A caller-supplied phoneme sequence with optional aligned prosody (TXT-050).
///
/// Supplying neither contour preserves the ordinary predicted prosody while
/// still bypassing normalization, tokenization, G2P, and stress assignment.
/// Supplying a contour replaces that part of the prediction exactly, enabling
/// precise lip-sync and research workflows without forcing callers to invent
/// values for the controls they do not need.
public struct PhonemeProsodySequence: Sendable, Equatable, Codable {
    /// Phonemes in speaking order.
    public let phonemes: [Phoneme]

    /// Optional duration for every phoneme, in milliseconds.
    public let durationsMs: [Double]?

    /// Optional fundamental-frequency target for every phoneme, in hertz.
    /// A value of zero is valid for an unvoiced phoneme.
    public let pitchTargetsHz: [Double]?

    /// Optional word starts, expressed as indices into ``phonemes``.
    public let wordBoundaries: [Int]

    /// Optional labels parallel to ``wordBoundaries`` for timing metadata.
    public let wordTexts: [String]

    public init(
        phonemes: [Phoneme],
        durationsMs: [Double]? = nil,
        pitchTargetsHz: [Double]? = nil,
        wordBoundaries: [Int] = [],
        wordTexts: [String] = []
    ) {
        self.phonemes = phonemes
        self.durationsMs = durationsMs
        self.pitchTargetsHz = pitchTargetsHz
        self.wordBoundaries = wordBoundaries
        self.wordTexts = wordTexts
    }

    /// Validates the parallel phoneme/prosody tensors before model inference.
    public func validate() throws {
        guard !phonemes.isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "phonemes", reason: "At least one phoneme is required")
        }
        guard phonemes.count <= 1_000_000 else {
            throw ChoirError.invalidParameter(
                parameter: "phonemes", reason: "A request may contain at most 1,000,000 phonemes")
        }

        let unknown = phonemes.map(\.symbol).filter { !PhonemeInventory.isValidIPA($0) }
        guard unknown.isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "phonemes",
                reason: "Phonemes outside the documented inventory: \(unknown.joined(separator: ", "))")
        }

        if let durationsMs {
            guard durationsMs.count == phonemes.count else {
                throw ChoirError.invalidParameter(
                    parameter: "durationsMs",
                    reason: "A duration must be supplied for every phoneme")
            }
            guard durationsMs.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 10_000 }) else {
                throw ChoirError.invalidParameter(
                    parameter: "durationsMs",
                    reason: "Durations must be finite and within (0, 10,000] ms")
            }
            let totalDurationMs = durationsMs.reduce(0, +)
            guard totalDurationMs.isFinite, totalDurationMs <= 86_400_000 else {
                throw ChoirError.invalidParameter(
                    parameter: "durationsMs",
                    reason: "Explicit phoneme timing may not exceed 24 hours")
            }
        }

        if let pitchTargetsHz {
            guard pitchTargetsHz.count == phonemes.count else {
                throw ChoirError.invalidParameter(
                    parameter: "pitchTargetsHz",
                    reason: "A pitch target must be supplied for every phoneme")
            }
            guard pitchTargetsHz.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
                throw ChoirError.invalidParameter(
                    parameter: "pitchTargetsHz",
                    reason: "Pitch targets must be finite and non-negative")
            }
        }

        if !wordBoundaries.isEmpty {
            guard wordBoundaries.first == 0,
                  wordBoundaries.allSatisfy({ phonemes.indices.contains($0) }),
                  zip(wordBoundaries, wordBoundaries.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
                throw ChoirError.invalidParameter(
                    parameter: "wordBoundaries",
                    reason: "Word boundaries must begin at zero and be strictly increasing phoneme indices")
            }
            guard wordTexts.isEmpty || wordTexts.count == wordBoundaries.count else {
                throw ChoirError.invalidParameter(
                    parameter: "wordTexts",
                    reason: "Word labels must be empty or parallel to word boundaries")
            }
        } else if !wordTexts.isEmpty {
            throw ChoirError.invalidParameter(
                parameter: "wordTexts", reason: "Word labels require word boundaries")
        }
    }

    /// The transcription presented to prosody prediction and metadata.
    var transcription: PhoneticTranscription {
        let boundaries = wordBoundaries.isEmpty ? [0] : wordBoundaries
        let labels: [String]
        if wordTexts.isEmpty {
            labels = boundaries.enumerated().map { index, start in
                let end = index + 1 < boundaries.count ? boundaries[index + 1] : phonemes.count
                return phonemes[start..<end].map(\.description).joined()
            }
        } else {
            labels = wordTexts
        }
        return PhoneticTranscription(
            phonemes: phonemes,
            originalText: labels.joined(separator: " "),
            wordBoundaries: boundaries,
            wordTexts: labels)
    }
}

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
        self.seconds = seconds.isFinite ? max(0, seconds) : 0
        self.syllables = max(0, syllables)
        self.breathGroupCount = max(0, breathGroupCount)
        self.pauseSeconds = pauseSeconds.isFinite ? max(0, pauseSeconds) : 0
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
        let effectiveRate = rate.isFinite ? max(0.1, rate) : 1
        let effectiveTempo = max(0.1, voice.profile.tempo * effectiveRate)
        let speechSeconds = Double(syllables) / effectiveTempo

        // Boundaries contribute pause time, scaled by rate as pauses shorten
        // with faster speech.
        let pauseSeconds = groups.reduce(0.0) { total, group in
            total + group.boundary.nominalPauseMs / 1000 / effectiveRate
        }

        return DurationEstimate(
            seconds: speechSeconds + pauseSeconds,
            syllables: syllables,
            breathGroupCount: groups.count,
            pauseSeconds: pauseSeconds
        )
    }
}
