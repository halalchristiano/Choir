import Foundation

/// Predicts which syllable of an out-of-vocabulary word carries primary stress
/// (SRS TXT-021).
///
/// Unstressed English vowels reduce to /ə/, and the rule fallback emitted a
/// full vowel in every position, which made schwa substitutions the largest
/// single category of G2P error. Reducing vowels by position was tried twice
/// and made accuracy worse both times: medial-group reduction scored 70.9% and
/// an `a`-only variant 71.7%, against 71.9% for doing nothing. Position is not
/// a usable proxy for English stress.
///
/// What works is that English suffixes place stress relative to the *end* of
/// the word, and the bundled lexicon already carries ground-truth stress marks
/// for 116,586 words. The table below is measured from it rather than invented:
/// each entry is the position that actually dominates, with the share of words
/// it covers.
///
/// Reduction is applied only where that share is high. A rule that is right 60%
/// of the time introduces more error than it removes, which is exactly how the
/// earlier attempts failed.
public struct StressPredictor: Sendable {

    /// A suffix and where it places primary stress.
    struct Rule: Sendable {
        /// Syllables back from the last one. 0 is the final syllable.
        let fromEnd: Int
        /// Share of lexicon words with this suffix that follow the rule.
        let confidence: Double
    }

    /// Minimum confidence before a prediction is trusted enough to reduce on.
    static let confidenceFloor = 0.72

    /// Measured over the bundled CMUdict, longest suffix first so that
    /// "ation" and "ical" are tested before "tion" and "ic".
    static let suffixRules: [(suffix: String, rule: Rule)] = [
        ("ical",  Rule(fromEnd: 2, confidence: 0.99)),
        ("ation", Rule(fromEnd: 1, confidence: 0.94)),
        ("ition", Rule(fromEnd: 1, confidence: 0.94)),
        ("ution", Rule(fromEnd: 1, confidence: 0.94)),
        ("tion",  Rule(fromEnd: 1, confidence: 0.96)),
        ("sion",  Rule(fromEnd: 1, confidence: 0.91)),
        ("ity",   Rule(fromEnd: 2, confidence: 0.96)),
        ("ive",   Rule(fromEnd: 1, confidence: 0.83)),
        ("ette",  Rule(fromEnd: 0, confidence: 0.80)),
        ("less",  Rule(fromEnd: 1, confidence: 0.77)),
        ("ous",   Rule(fromEnd: 2, confidence: 0.72)),
        ("ic",    Rule(fromEnd: 1, confidence: 0.94)),
    ]

    /// Two-syllable words take initial stress in 89% of the lexicon, which is
    /// the only syllable-count default strong enough to act on. Three- and
    /// four-syllable words without a known suffix top out near 55% and 39%,
    /// well below the floor, so they are left alone.
    static let twoSyllableRule = Rule(fromEnd: 1, confidence: 0.89)

    public init() {}

    /// The stressed syllable index, counted from the start, or nil when no rule
    /// is confident enough to say.
    ///
    /// - Parameters:
    ///   - word: the lowercased spelling.
    ///   - syllableCount: number of vowel groups in the word.
    public func stressedSyllable(of word: String, syllableCount: Int) -> Int? {
        guard syllableCount >= 2 else { return syllableCount == 1 ? 0 : nil }

        for (suffix, rule) in Self.suffixRules where word.hasSuffix(suffix) {
            guard rule.confidence >= Self.confidenceFloor else { return nil }
            let index = syllableCount - 1 - rule.fromEnd
            return (0..<syllableCount).contains(index) ? index : nil
        }

        if syllableCount == 2, Self.twoSyllableRule.confidence >= Self.confidenceFloor {
            let index = syllableCount - 1 - Self.twoSyllableRule.fromEnd
            return index
        }
        return nil
    }
}
