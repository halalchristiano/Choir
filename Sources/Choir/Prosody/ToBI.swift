import Foundation

/// ToBI (Tones and Break Indices) annotation for phonological prosody.
///
/// Provides linguistic-level prosody control separate from acoustic F0.
public struct ToBI: Sendable {
    /// Pitch accent: H* (high), L* (low), L+H* (rising), H+L* (falling), L*+H (delayed rise).
    public enum PitchAccent: String, Sendable {
        case H_star = "H*"
        case L_star = "L*"
        case L_H = "L+H*"
        case H_L = "H+L*"
        case L_H_delayed = "L*+H"
        case none = "none"
    }

    /// Phrase accent: H- (high), L- (low).
    public enum PhraseAccent: String, Sendable {
        case high = "H-"
        case low = "L-"
        case none = "none"
    }

    /// Boundary tone: H% (high), L% (low), M% (mid).
    public enum BoundaryTone: String, Sendable {
        case high = "H%"
        case low = "L%"
        case mid = "M%"
        case none = "none"
    }

    /// Break index: 0-4 indicating prosodic strength.
    /// 0 = no break, 1 = word boundary, 2 = intermediate phrase, 3 = intonational phrase, 4 = utterance boundary.
    public enum BreakIndex: Int, Sendable {
        case none = 0
        case word = 1
        case intermediate = 2
        case intonational = 3
        case utterance = 4
    }

    /// Pitch accent on this syllable.
    public let pitchAccent: PitchAccent

    /// Phrase accent after this phrase.
    public let phraseAccent: PhraseAccent

    /// Boundary tone at utterance end.
    public let boundaryTone: BoundaryTone

    /// Break index before next word.
    public let breakIndex: BreakIndex

    public init(
        pitchAccent: PitchAccent = .none,
        phraseAccent: PhraseAccent = .none,
        boundaryTone: BoundaryTone = .none,
        breakIndex: BreakIndex = .none
    ) {
        self.pitchAccent = pitchAccent
        self.phraseAccent = phraseAccent
        self.boundaryTone = boundaryTone
        self.breakIndex = breakIndex
    }

    /// Generates ToBI annotation string (e.g., "L+H* H- L%").
    public var annotation: String {
        [pitchAccent.rawValue, phraseAccent.rawValue, boundaryTone.rawValue]
            .filter { $0 != "none" }
            .joined(separator: " ")
    }
}

/// Predicts ToBI prosodic structure from text and phonetics.
public struct ToBIPredictor: Sendable {
    public init() {}

    /// Predicts ToBI annotations for a phonetic transcription.
    ///
    /// - Parameters:
    ///   - transcript: The phonetic transcription with word boundaries.
    ///   - wordCount: Number of words in the utterance.
    /// - Returns: ToBI annotations for each word.
    public func predictToBI(
        for transcript: PhoneticTranscription,
        wordCount: Int
    ) -> [ToBI] {
        var annotations: [ToBI] = []
        let words = transcript.words

        for (wordIdx, word) in words.enumerated() {
            let isLastWord = wordIdx == words.count - 1
            let isStressed = word.contains { $0.stress > 0 }

            // Pitch accent: Stressed syllables get H*, unstressed get L*
            let pitchAccent: ToBI.PitchAccent = isStressed ? .H_star : .L_star

            // Phrase accent: Higher on non-final words
            let phraseAccent: ToBI.PhraseAccent = isLastWord ? .low : .high

            // Boundary tone: Final word gets boundary tone
            let boundaryTone: ToBI.BoundaryTone = isLastWord ? .low : .none

            // Break index: Increases for prosodic boundaries
            let breakIndex: ToBI.BreakIndex = isLastWord ? .utterance : .word

            let tobi = ToBI(
                pitchAccent: pitchAccent,
                phraseAccent: phraseAccent,
                boundaryTone: boundaryTone,
                breakIndex: breakIndex
            )

            annotations.append(tobi)
        }

        return annotations
    }

    /// Applies ToBI structure to modify F0 contour.
    public func applyToBIToF0(
        baseF0: Double,
        tobi: ToBI,
        position: Double  // 0.0 to 1.0 within syllable
    ) -> Double {
        var f0 = baseF0

        // Apply pitch accent effects
        switch tobi.pitchAccent {
        case .H_star:
            f0 += 20  // Higher pitch for H*
        case .L_star:
            f0 -= 10  // Lower pitch for L*
        case .L_H:
            // Starts 15 Hz low and rises 30 Hz across the syllable.
            // Note `-=` would subtract the whole sum and fall instead.
            f0 += -15 + (30 * position)
        case .H_L:
            f0 += 15 - (30 * position)  // Falling accent
        case .L_H_delayed:
            let delayedPos = max(0, position - 0.3)  // Rise delayed
            f0 += -15 + (30 * delayedPos)
        case .none:
            break
        }

        // Apply phrase accent
        switch tobi.phraseAccent {
        case .high:
            f0 += 5
        case .low:
            f0 -= 5
        case .none:
            break
        }

        return max(50, min(400, f0))  // Keep in reasonable range
    }
}
