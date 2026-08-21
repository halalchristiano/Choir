import Foundation

/// Word-level accuracy scoring for intelligibility testing (SRS QUA-004).
public enum TranscriptionScoring {

    /// Reduces a sentence to comparable words.
    ///
    /// An ASR system returns neither punctuation nor reliable casing, so
    /// comparing raw strings would score correct transcriptions as errors.
    /// Contractions are kept intact — "it's" and "its" are different words and
    /// conflating them would hide a real intelligibility failure.
    public static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { word in
                String(word.filter { $0.isLetter || $0.isNumber || $0 == "'" })
            }
            .filter { !$0.isEmpty }
    }

    /// Word error rate: (substitutions + deletions + insertions) / reference words.
    ///
    /// The standard measure, and the one QUA-004's "word-level transcription
    /// accuracy" is the complement of.
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let referenceWords = normalizedWords(reference)
        let hypothesisWords = normalizedWords(hypothesis)
        guard !referenceWords.isEmpty else { return hypothesisWords.isEmpty ? 0 : 1 }

        let distance = EditDistance.between(hypothesisWords, referenceWords)
        return Double(distance) / Double(referenceWords.count)
    }

    /// Word accuracy: 1 - WER, floored at zero.
    ///
    /// Floored because insertions can drive WER above 1, and a "negative
    /// accuracy" is not a meaningful thing to report.
    public static func wordAccuracy(reference: String, hypothesis: String) -> Double {
        max(0, 1 - wordErrorRate(reference: reference, hypothesis: hypothesis))
    }
}

/// Levenshtein distance over token sequences.
///
/// Shared by the G2P evaluator, which scores phonemes, and the intelligibility
/// harness, which scores words. The algorithm is identical; only the token
/// differs.
enum EditDistance {
    static func between(_ lhs: [String], _ rhs: [String]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        // Two rows rather than a full matrix: only the distance is needed,
        // never the alignment.
        var previous = Array(0...rhs.count)
        var current = [Int](repeating: 0, count: rhs.count + 1)

        for i in 1...lhs.count {
            current[0] = i
            for j in 1...rhs.count {
                let substitution = previous[j - 1] + (lhs[i - 1] == rhs[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }
}
