import Foundation

/// Breaks a G2P evaluation down by orthographic class (SRS TXT-020).
///
/// The aggregate figure — 54.2% against a 92% target — names no defect. It
/// says the rule fallback is wrong more often than it is right, but not which
/// rule, so there is nothing to fix in response to it. This splits the same
/// sample into classes that correspond to individual letter-to-sound rules, so
/// a bad rule shows up as a bad row rather than as a fraction of one number.
///
/// A word belongs to every class whose pattern it matches; the classes are
/// diagnostic buckets, not a partition. `overall` is the whole sample and is
/// directly comparable with `G2PEvaluator.Report`.
public struct G2PDiagnostics: Sendable {

    /// One orthographic pattern and the accuracy of the words carrying it.
    public struct ClassReport: Sendable, Equatable {
        public let name: String
        public let report: G2PEvaluator.Report

        public init(name: String, report: G2PEvaluator.Report) {
            self.name = name
            self.report = report
        }

        /// Accuracy shortfall against the TXT-020 target, in percentage points.
        public var shortfall: Double {
            max(0, 0.92 - report.phonemeAccuracy) * 100
        }
    }

    /// An orthographic class, defined by the words it selects.
    public struct WordClass: Sendable {
        public let name: String
        public let matches: @Sendable (String) -> Bool

        public init(name: String, matches: @escaping @Sendable (String) -> Bool) {
            self.name = name
            self.matches = matches
        }
    }

    /// The classes the rule fallback is expected to handle.
    ///
    /// Each one corresponds to a rule that either exists or is missing, so a
    /// row here maps to a specific piece of work rather than to "G2P".
    public static let standardClasses: [WordClass] = [
        WordClass(name: "-tion / -sion / -cion") { w in
            w.hasSuffix("tion") || w.hasSuffix("sion") || w.hasSuffix("cion")
        },
        WordClass(name: "-ough") { $0.contains("ough") },
        WordClass(name: "silent final e") { w in
            guard w.count >= 4, w.hasSuffix("e") else { return false }
            let stem = w.dropLast()
            guard let last = stem.last else { return false }
            return !Self.vowels.contains(last)
        },
        WordClass(name: "doubled consonant") { w in
            let chars = Array(w)
            for i in 1..<max(1, chars.count)
            where chars[i] == chars[i - 1] && !Self.vowels.contains(chars[i]) {
                return true
            }
            return false
        },
        WordClass(name: "-ity / -ic / -ion stress") { w in
            w.hasSuffix("ity") || w.hasSuffix("ic") || w.hasSuffix("ion")
        },
        WordClass(name: "-ing") { $0.hasSuffix("ing") },
        WordClass(name: "-ed") { $0.hasSuffix("ed") },
        WordClass(name: "plural / 3sg -s") { w in
            w.hasSuffix("s") && !w.hasSuffix("ss") && !w.hasSuffix("us")
        },
        WordClass(name: "vowel digraph") { w in
            ["ai", "ea", "ee", "ie", "oa", "oo", "ou", "ue", "ei", "au"]
                .contains { w.contains($0) }
        },
        WordClass(name: "initial consonant cluster") { w in
            let chars = Array(w)
            guard chars.count >= 3 else { return false }
            return !Self.vowels.contains(chars[0]) && !Self.vowels.contains(chars[1])
        },
        WordClass(name: "contains y") { $0.contains("y") },
        WordClass(name: "1–4 letters") { $0.count <= 4 },
        WordClass(name: "5–8 letters") { $0.count >= 5 && $0.count <= 8 },
        WordClass(name: "9+ letters") { $0.count >= 9 },
    ]

    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u"]

    public init() {}

    /// Evaluates each class over the same sample.
    ///
    /// - Parameters:
    ///   - words: the held-out sample, as produced by
    ///     ``G2PEvaluator/sampleWords(from:count:)``.
    ///   - reference: ground-truth ARPAbet for a word, or nil to skip it.
    ///   - phonemizer: the phonemizer under test, normally rules-only.
    ///   - classes: the classes to report; defaults to ``standardClasses``.
    /// - Returns: the overall report and one report per non-empty class,
    ///   worst accuracy first so the top row is the next thing to fix.
    public func evaluate(
        words: [String],
        reference: (String) -> String?,
        phonemizer: Phonemizer,
        classes: [WordClass] = G2PDiagnostics.standardClasses
    ) -> (overall: G2PEvaluator.Report, classes: [ClassReport]) {
        let evaluator = G2PEvaluator()
        let overall = evaluator.evaluate(
            words: words, reference: reference, phonemizer: phonemizer)

        var reports: [ClassReport] = []
        for wordClass in classes {
            let subset = words.filter { wordClass.matches($0) }
            guard !subset.isEmpty else { continue }
            let report = evaluator.evaluate(
                words: subset, reference: reference, phonemizer: phonemizer)
            guard report.hasUsableSample else { continue }
            reports.append(ClassReport(name: wordClass.name, report: report))
        }

        reports.sort { lhs, rhs in
            lhs.report.phonemeAccuracy == rhs.report.phonemeAccuracy
                ? lhs.report.wordCount > rhs.report.wordCount
                : lhs.report.phonemeAccuracy < rhs.report.phonemeAccuracy
        }
        return (overall, reports)
    }

    /// Renders the breakdown as a Markdown table, worst class first.
    public func markdown(
        overall: G2PEvaluator.Report,
        classes: [ClassReport]
    ) -> String {
        var lines: [String] = []
        lines.append("| Orthographic class | Words | Phoneme accuracy | Gap to 92% |")
        lines.append("|---|---:|---:|---:|")
        lines.append(String(
            format: "| **all sampled words** | %d | **%.1f%%** | %.1f pt |",
            overall.wordCount,
            overall.phonemeAccuracy * 100,
            max(0, 0.92 - overall.phonemeAccuracy) * 100))
        for entry in classes {
            lines.append(String(
                format: "| %@ | %d | %.1f%% | %.1f pt |",
                entry.name,
                entry.report.wordCount,
                entry.report.phonemeAccuracy * 100,
                entry.shortfall))
        }
        return lines.joined(separator: "\n")
    }
}
