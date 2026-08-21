import Foundation
import Testing
@testable import Choir

/// SRS TXT-020 (MUST) — the measured half of the requirement.
///
/// "...plus a trained neural or rule-based G2P fallback for out-of-vocabulary
/// words achieving ≥ 92% phoneme accuracy on a held-out OOV test set."
///
/// The lexicon half shipped in v0.7.0; this is the accuracy half, which was
/// recorded as unmeasured rather than claimed.
@Suite("SRS TXT-020 — G2P accuracy")
struct G2PAccuracyTests {

    /// Rules only. The built-in lexicon is withheld, which is exactly the
    /// situation an out-of-vocabulary word faces.
    private var rulesOnlyPhonemizer: Phonemizer {
        Phonemizer(builtInLexicon: nil)
    }

    @Test("Edit distance is correct")
    func testEditDistance() {
        #expect(G2PEvaluator.editDistance([], []) == 0)
        #expect(G2PEvaluator.editDistance(["a"], []) == 1)
        #expect(G2PEvaluator.editDistance([], ["a", "b"]) == 2)
        #expect(G2PEvaluator.editDistance(["a", "b"], ["a", "b"]) == 0)
        #expect(G2PEvaluator.editDistance(["a", "b"], ["a", "c"]) == 1)
        #expect(G2PEvaluator.editDistance(["a", "b", "c"], ["a", "c"]) == 1)
    }

    @Test("The sample is deterministic")
    func testSampleDeterministic() {
        let first = G2PEvaluator.sampleWords(from: BuiltInLexicon.shared, count: 200)
        let second = G2PEvaluator.sampleWords(from: BuiltInLexicon.shared, count: 200)
        #expect(first == second, "the held-out sample changed between runs")
        #expect(first.count == 200)
    }

    @Test("A perfect phonemizer scores 100%")
    func testPerfectScore() {
        let lexicon = BuiltInLexicon(entries: ["hello": "HH AH0 L OW1"])
        // Feeding the same lexicon in as the phonemizer's source makes this a
        // control: the harness must report 100% when prediction equals truth.
        let report = G2PEvaluator().evaluate(
            words: ["hello"],
            reference: { lexicon.arpabet(for: $0) },
            phonemizer: Phonemizer(builtInLexicon: lexicon))
        #expect(report.phonemeAccuracy == 1.0, "\(report.summary)")
        #expect(report.exactMatches == 1)
    }

    /// The measurement itself.
    ///
    /// This test does not assert the 92% target, because the rule-based
    /// fallback does not currently meet it and a permanently red build would
    /// teach the team to ignore it. It asserts a regression floor instead, and
    /// prints the measured figure. The shortfall is recorded in
    /// SRS_CONFORMANCE.md as an open requirement.
    @Test("TXT-020: measured OOV phoneme accuracy")
    func testMeasuredAccuracy() {
        let lexicon = BuiltInLexicon.shared
        let words = G2PEvaluator.sampleWords(from: lexicon, count: 2_000)

        let report = G2PEvaluator().evaluate(
            words: words,
            reference: { lexicon.arpabet(for: $0) },
            phonemizer: rulesOnlyPhonemizer)

        print("TXT-020 G2P evaluation: \(report.summary)")

        #expect(report.wordCount > 1_500, "too few words evaluated: \(report.wordCount)")
        #expect(report.referencePhonemeCount > 5_000)

        // Regression floor, not the requirement. Raise it as the rules improve.
        #expect(report.phonemeAccuracy > 0.30,
                "G2P accuracy regressed below the recorded floor: \(report.summary)")
        #expect(report.phonemeAccuracy <= 1.0)
    }

    /// Records the gap explicitly so it cannot be mistaken for compliance.
    @Test("TXT-020: the 92% target is not yet met")
    func testTargetNotYetMet() {
        let lexicon = BuiltInLexicon.shared
        let words = G2PEvaluator.sampleWords(from: lexicon, count: 1_000)
        let report = G2PEvaluator().evaluate(
            words: words,
            reference: { lexicon.arpabet(for: $0) },
            phonemizer: rulesOnlyPhonemizer)

        // When this expectation starts failing, the rules have reached the
        // target: delete this test and assert the requirement directly.
        #expect(!report.meetsTarget,
                "G2P now meets TXT-020 (\(report.summary)) — replace this test with the real assertion")
    }
}
