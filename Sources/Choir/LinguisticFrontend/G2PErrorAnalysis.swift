import Foundation

/// Counts the specific phoneme errors a G2P run makes (SRS TXT-020).
///
/// The per-class breakdown in ``G2PDiagnostics`` says *which words* are wrong.
/// This says *what is wrong inside them*: the edit-distance alignment is
/// reconstructed rather than discarded, so a systematic error — one vowel
/// consistently predicted where another belongs — appears as a single large
/// count instead of being spread across every class that contains it.
public struct G2PErrorAnalysis: Sendable {

    /// One kind of mistake and how often it was made.
    public struct Confusion: Sendable, Equatable, Hashable {
        /// The phoneme the reference has, or nil for an insertion.
        public let expected: String?
        /// The phoneme the phonemizer produced, or nil for a deletion.
        public let predicted: String?
        public let count: Int

        public init(expected: String?, predicted: String?, count: Int) {
            self.expected = expected
            self.predicted = predicted
            self.count = count
        }

        public var label: String {
            switch (expected, predicted) {
            case let (e?, p?): return "\(e) → \(p)"
            case let (e?, nil): return "\(e) → (dropped)"
            case let (nil, p?): return "(inserted) \(p)"
            case (nil, nil): return "—"
            }
        }
    }

    public struct Report: Sendable {
        public let substitutions: [Confusion]
        public let deletions: [Confusion]
        public let insertions: [Confusion]
        public let totalErrors: Int

        public init(
            substitutions: [Confusion],
            deletions: [Confusion],
            insertions: [Confusion],
            totalErrors: Int
        ) {
            self.substitutions = substitutions
            self.deletions = deletions
            self.insertions = insertions
            self.totalErrors = totalErrors
        }
    }

    public init() {}

    /// Aligns prediction against reference for every word and tallies the
    /// differences.
    ///
    /// - Returns: substitutions, deletions and insertions, each ordered by
    ///   descending count so the first row is the most valuable thing to fix.
    public func analyze(
        words: [String],
        reference: (String) -> String?,
        phonemizer: Phonemizer
    ) -> Report {
        var substitutions: [Confusion: Int] = [:]
        var deletions: [String: Int] = [:]
        var insertions: [String: Int] = [:]
        var total = 0

        for rawWord in words {
            let word = rawWord.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, let arpabet = reference(word) else { continue }
            let conversion = PhonemeInventory.conversion(fromARPAbet: arpabet)
            guard conversion.isComplete, !conversion.phonemes.isEmpty else { continue }

            let expected = conversion.phonemes.map(\.symbol)
            let predicted = phonemizer.phonemize(word).map(\.symbol)

            for operation in Self.align(predicted: predicted, expected: expected) {
                total += 1
                switch operation {
                case let .substitute(from, to):
                    let key = Confusion(expected: from, predicted: to, count: 0)
                    substitutions[key, default: 0] += 1
                case let .delete(symbol):
                    deletions[symbol, default: 0] += 1
                case let .insert(symbol):
                    insertions[symbol, default: 0] += 1
                }
            }
        }

        return Report(
            substitutions: substitutions
                .map { Confusion(expected: $0.key.expected, predicted: $0.key.predicted, count: $0.value) }
                .sorted { $0.count > $1.count },
            deletions: deletions
                .map { Confusion(expected: $0.key, predicted: nil, count: $0.value) }
                .sorted { $0.count > $1.count },
            insertions: insertions
                .map { Confusion(expected: nil, predicted: $0.key, count: $0.value) }
                .sorted { $0.count > $1.count },
            totalErrors: total)
    }

    /// Renders the top rows of each category as Markdown.
    public func markdown(_ report: Report, limit: Int = 12) -> String {
        func table(_ title: String, _ rows: [Confusion]) -> String {
            var lines = ["**\(title)**", "", "| Error | Count | Share |", "|---|---:|---:|"]
            for row in rows.prefix(limit) {
                let share = report.totalErrors > 0
                    ? Double(row.count) / Double(report.totalErrors) * 100 : 0
                lines.append(String(format: "| %@ | %d | %.1f%% |", row.label, row.count, share))
            }
            return lines.joined(separator: "\n")
        }
        return [
            "Total phoneme errors: \(report.totalErrors)",
            "",
            table("Substitutions", report.substitutions),
            "",
            table("Dropped (reference had a phoneme, prediction did not)", report.deletions),
            "",
            table("Inserted (prediction invented a phoneme)", report.insertions),
        ].joined(separator: "\n")
    }

    // MARK: - Alignment

    enum Operation: Sendable, Equatable {
        case substitute(from: String, to: String)
        case delete(String)
        case insert(String)
    }

    /// Levenshtein alignment with a backtrace.
    ///
    /// `G2PEvaluator.editDistance` keeps only the final cost, which is what the
    /// accuracy figure needs. Diagnosing the errors needs the path that
    /// produced it, so the full matrix is retained here.
    static func align(predicted: [String], expected: [String]) -> [Operation] {
        let n = predicted.count, m = expected.count
        var cost = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { cost[i][0] = i }
        for j in 0...m { cost[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let match = predicted[i - 1] == expected[j - 1] ? 0 : 1
                    cost[i][j] = min(
                        cost[i - 1][j] + 1,
                        cost[i][j - 1] + 1,
                        cost[i - 1][j - 1] + match)
                }
            }
        }

        var operations: [Operation] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, predicted[i - 1] == expected[j - 1],
               cost[i][j] == cost[i - 1][j - 1] {
                i -= 1; j -= 1
                continue
            }
            if i > 0, j > 0, cost[i][j] == cost[i - 1][j - 1] + 1 {
                operations.append(.substitute(from: expected[j - 1], to: predicted[i - 1]))
                i -= 1; j -= 1
            } else if i > 0, cost[i][j] == cost[i - 1][j] + 1 {
                // The prediction has a phoneme the reference does not.
                operations.append(.insert(predicted[i - 1]))
                i -= 1
            } else if j > 0 {
                // The reference has a phoneme the prediction does not.
                operations.append(.delete(expected[j - 1]))
                j -= 1
            } else {
                break
            }
        }
        return operations.reversed()
    }
}
