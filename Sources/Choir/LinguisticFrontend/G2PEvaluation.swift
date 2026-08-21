import Foundation

/// Measures grapheme-to-phoneme accuracy against a reference lexicon
/// (SRS TXT-020).
///
/// TXT-020 requires the rule-based fallback to achieve "≥ 92% phoneme accuracy
/// on a held-out OOV test set". That target cannot be claimed without
/// measuring it, so this exists to produce the number.
///
/// The built-in lexicon doubles as ground truth: holding words out of it and
/// phonemizing them by rule alone reproduces exactly the situation a genuinely
/// out-of-vocabulary word encounters.
public struct G2PEvaluator: Sendable {

    /// The outcome of an evaluation run.
    public struct Report: Sendable, Equatable {
        /// Words evaluated.
        public let wordCount: Int

        /// Reference phonemes across all words.
        public let referencePhonemeCount: Int

        /// Total edit distance between predicted and reference sequences.
        public let totalEditDistance: Int

        /// Words predicted exactly, with no substitutions or omissions.
        public let exactMatches: Int

        /// Phoneme accuracy: 1 - (edit distance / reference length).
        ///
        /// This is the standard phoneme-error-rate complement, and is what
        /// TXT-020's "phoneme accuracy" figure refers to.
        public var phonemeAccuracy: Double {
            guard referencePhonemeCount > 0 else { return 0 }
            return max(0, 1.0 - Double(totalEditDistance) / Double(referencePhonemeCount))
        }

        /// Proportion of words predicted exactly.
        public var wordAccuracy: Double {
            guard wordCount > 0 else { return 0 }
            return Double(exactMatches) / Double(wordCount)
        }

        /// Whether the TXT-020 target is met.
        public var meetsTarget: Bool { phonemeAccuracy >= 0.92 }

        public var summary: String {
            String(
                format: "%d words, %d reference phonemes: phoneme accuracy %.1f%%, word accuracy %.1f%% (TXT-020 target 92%%: %@)",
                wordCount, referencePhonemeCount,
                phonemeAccuracy * 100, wordAccuracy * 100,
                meetsTarget ? "met" : "NOT met")
        }
    }

    public init() {}

    /// Evaluates `phonemizer` against reference pronunciations.
    ///
    /// - Parameters:
    ///   - words: the held-out words to test.
    ///   - reference: ground-truth pronunciations, as ARPAbet.
    ///   - phonemizer: the phonemizer under test, which must not have access
    ///     to the words being held out.
    public func evaluate(
        words: [String],
        reference: (String) -> String?,
        phonemizer: Phonemizer
    ) -> Report {
        var referenceCount = 0
        var distance = 0
        var exact = 0
        var evaluated = 0

        for word in words {
            guard let arpabet = reference(word) else { continue }
            let expected = PhonemeInventory.phonemes(fromARPAbet: arpabet).map(\.symbol)
            guard !expected.isEmpty else { continue }

            let predicted = phonemizer.phonemize(word).map(\.symbol)

            evaluated += 1
            referenceCount += expected.count
            let d = Self.editDistance(predicted, expected)
            distance += d
            if d == 0 { exact += 1 }
        }

        return Report(
            wordCount: evaluated,
            referencePhonemeCount: referenceCount,
            totalEditDistance: distance,
            exactMatches: exact
        )
    }

    /// Levenshtein distance between two phoneme sequences.
    ///
    /// Delegates to the shared implementation, which the intelligibility
    /// harness also uses for words: the algorithm is identical and only the
    /// token differs.
    static func editDistance(_ lhs: [String], _ rhs: [String]) -> Int {
        EditDistance.between(lhs, rhs)
    }

    /// A deterministic sample of words from the built-in lexicon.
    ///
    /// Sampling by a fixed stride rather than at random keeps the set stable
    /// across runs, so a change in the reported accuracy means the G2P rules
    /// changed and not the sample.
    public static func sampleWords(from lexicon: BuiltInLexicon, count: Int) -> [String] {
        let all = lexicon.allWords.sorted()
        guard all.count > count, count > 0 else { return all }
        let stride = all.count / count
        return (0..<count).compactMap { index in
            let position = index * stride
            return position < all.count ? all[position] : nil
        }
    }
}
