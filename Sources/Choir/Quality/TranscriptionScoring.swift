import Foundation

/// Word-level accuracy scoring for intelligibility testing (SRS QUA-004).
public enum TranscriptionScoring {

    public enum EditOperation: Sendable, Equatable, Codable {
        case match(String)
        case substitution(reference: String, hypothesis: String)
        case deletion(String)
        case insertion(String)
    }

    public struct WordErrorBreakdown: Sendable, Equatable, Codable {
        public let referenceWordCount: Int
        public let hypothesisWordCount: Int
        public let substitutions: Int
        public let deletions: Int
        public let insertions: Int
        public let correct: Int
        public let operations: [EditOperation]

        public var totalErrors: Int { substitutions + deletions + insertions }

        public var wordErrorRate: Double {
            guard referenceWordCount > 0 else { return hypothesisWordCount == 0 ? 0 : 1 }
            return Double(totalErrors) / Double(referenceWordCount)
        }

        public var wordAccuracy: Double { max(0, 1 - wordErrorRate) }

        public var isExactMatch: Bool { totalErrors == 0 }
    }

    /// Reduces a sentence to comparable words.
    ///
    /// An ASR system returns neither punctuation nor reliable casing, so
    /// comparing raw strings would score correct transcriptions as errors.
    /// Contractions are kept intact — "it's" and "its" are different words and
    /// conflating them would hide a real intelligibility failure.
    public static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‐", with: " ")
            .replacingOccurrences(of: "‑", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "-", with: " ")
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
        breakdown(reference: reference, hypothesis: hypothesis).wordErrorRate
    }

    /// Word accuracy: 1 - WER, floored at zero.
    ///
    /// Floored because insertions can drive WER above 1, and a "negative
    /// accuracy" is not a meaningful thing to report.
    public static func wordAccuracy(reference: String, hypothesis: String) -> Double {
        breakdown(reference: reference, hypothesis: hypothesis).wordAccuracy
    }

    /// Returns an explainable alignment and separate error counts.
    public static func breakdown(reference: String, hypothesis: String) -> WordErrorBreakdown {
        let referenceWords = normalizedWords(reference)
        let hypothesisWords = normalizedWords(hypothesis)
        let operations = alignment(reference: referenceWords, hypothesis: hypothesisWords)

        var substitutions = 0
        var deletions = 0
        var insertions = 0
        var correct = 0
        for operation in operations {
            switch operation {
            case .match: correct += 1
            case .substitution: substitutions += 1
            case .deletion: deletions += 1
            case .insertion: insertions += 1
            }
        }
        return WordErrorBreakdown(
            referenceWordCount: referenceWords.count,
            hypothesisWordCount: hypothesisWords.count,
            substitutions: substitutions,
            deletions: deletions,
            insertions: insertions,
            correct: correct,
            operations: operations)
    }

    private static func alignment(
        reference: [String], hypothesis: [String]
    ) -> [EditOperation] {
        let rows = reference.count + 1
        let columns = hypothesis.count + 1
        var matrix = Array(
            repeating: [Int](repeating: 0, count: columns), count: rows)
        for row in 0..<rows { matrix[row][0] = row }
        for column in 0..<columns { matrix[0][column] = column }

        if reference.count > 0, hypothesis.count > 0 {
            for row in 1...reference.count {
                for column in 1...hypothesis.count {
                    let substitutionCost = reference[row - 1] == hypothesis[column - 1] ? 0 : 1
                    matrix[row][column] = min(
                        matrix[row - 1][column - 1] + substitutionCost,
                        matrix[row - 1][column] + 1,
                        matrix[row][column - 1] + 1)
                }
            }
        }

        var operations: [EditOperation] = []
        var row = reference.count
        var column = hypothesis.count
        while row > 0 || column > 0 {
            if row > 0, column > 0 {
                let same = reference[row - 1] == hypothesis[column - 1]
                let diagonalCost = matrix[row - 1][column - 1] + (same ? 0 : 1)
                if matrix[row][column] == diagonalCost {
                    operations.append(same
                        ? .match(reference[row - 1])
                        : .substitution(
                            reference: reference[row - 1], hypothesis: hypothesis[column - 1]))
                    row -= 1
                    column -= 1
                    continue
                }
            }
            if row > 0, matrix[row][column] == matrix[row - 1][column] + 1 {
                operations.append(.deletion(reference[row - 1]))
                row -= 1
            } else if column > 0 {
                operations.append(.insertion(hypothesis[column - 1]))
                column -= 1
            }
        }
        return Array(operations.reversed())
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
