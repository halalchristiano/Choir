import Foundation
import Testing
@testable import Choir

/// SRS TXT-020 — per-class G2P diagnostics.
///
/// The aggregate accuracy figure cannot be acted on. These tests exercise the
/// breakdown that can be, and print it so a run of the suite leaves the current
/// per-rule picture in the log.
@Suite("SRS TXT-020 — G2P diagnostics by orthographic class")
struct G2PDiagnosticsTests {

    private var rulesOnlyPhonemizer: Phonemizer {
        Phonemizer(builtInLexicon: nil)
    }

    @Test("Classes select the words they name")
    func testClassMatching() {
        func matcher(_ name: String) -> (String) -> Bool {
            G2PDiagnostics.standardClasses.first { $0.name == name }!.matches
        }

        let tion = matcher("-tion / -sion / -cion")
        #expect(tion("nation"))
        #expect(tion("tension"))
        #expect(!tion("national"))

        let silentE = matcher("silent final e")
        #expect(silentE("hope"))
        #expect(silentE("rate"))
        #expect(!silentE("see"), "a vowel before the e is not a silent-e pattern")
        #expect(!silentE("be"), "too short to be the silent-e pattern")

        let doubled = matcher("doubled consonant")
        #expect(doubled("hopping"))
        #expect(!doubled("hoping"))
        #expect(!doubled("aardvark"), "a doubled vowel is not a doubled consonant")

        let ough = matcher("-ough")
        #expect(ough("thorough"))
        #expect(!ough("though!".replacingOccurrences(of: "ough!", with: "xx")))
    }

    @Test("A perfect phonemizer scores 100% in every class")
    func testPerfectControl() {
        let lexicon = BuiltInLexicon(entries: [
            "nation": "N EY1 SH AH0 N",
            "hoping": "HH OW1 P IH0 NG",
        ])
        let diagnostics = G2PDiagnostics()
        let (overall, classes) = diagnostics.evaluate(
            words: ["nation", "hoping"],
            reference: { lexicon.arpabet(for: $0) },
            phonemizer: Phonemizer(builtInLexicon: lexicon))

        #expect(overall.phonemeAccuracy == 1.0)
        #expect(!classes.isEmpty)
        for entry in classes {
            #expect(entry.report.phonemeAccuracy == 1.0,
                    "class '\(entry.name)' should be perfect: \(entry.report.summary)")
            #expect(entry.shortfall == 0)
        }
    }

    @Test("Worst class sorts first")
    func testOrdering() {
        let lexicon = BuiltInLexicon.shared
        let words = G2PEvaluator.sampleWords(from: lexicon, count: 400)
        let (_, classes) = G2PDiagnostics().evaluate(
            words: words,
            reference: { lexicon.arpabet(for: $0) },
            phonemizer: rulesOnlyPhonemizer)

        #expect(classes.count >= 2)
        for (lhs, rhs) in zip(classes, classes.dropFirst()) {
            #expect(lhs.report.phonemeAccuracy <= rhs.report.phonemeAccuracy,
                    "classes are not ordered worst-first")
        }
    }

    /// The measurement. Prints the table so every suite run records the
    /// current per-rule picture rather than only the aggregate.
    @Test("TXT-020: per-class accuracy breakdown")
    func testBreakdown() {
        let lexicon = BuiltInLexicon.shared
        let words = G2PEvaluator.sampleWords(from: lexicon, count: 2_000)
        let diagnostics = G2PDiagnostics()
        let (overall, classes) = diagnostics.evaluate(
            words: words,
            reference: { lexicon.arpabet(for: $0) },
            phonemizer: rulesOnlyPhonemizer)

        print("\nTXT-020 per-class G2P breakdown (rules only, no lexicon):\n")
        print(diagnostics.markdown(overall: overall, classes: classes))
        print("")

        #expect(overall.hasUsableSample)
        #expect(classes.count >= 8, "too few classes reported to be diagnostic")
        // A floor, not a band: this number is meant to climb, and a band
        // would fail the build for an improvement.
        #expect(overall.phonemeAccuracy > 0.68,
                "G2P accuracy regressed: \(overall.summary)")
    }
}

/// SRS AUD-001 — export-format capability is queryable.
///
/// The unimplemented encoders throw a clear error, but a caller had no way to
/// find out except by attempting an export and catching it.
@Suite("Export format capability")
struct AudioOutputFormatCapabilityTests {

    @Test("Only WAV reports as implemented")
    func testImplementedSet() {
        #expect(AudioOutputFormat.wav.isImplemented)
        #expect(!AudioOutputFormat.mp3.isImplemented)
        #expect(!AudioOutputFormat.aac.isImplemented)
        #expect(!AudioOutputFormat.flac.isImplemented)
        #expect(AudioOutputFormat.implemented == [.wav])
    }

    /// The query must track the encoders, not drift from them.
    @Test("Unimplemented formats actually throw")
    func testUnimplementedThrow() {
        let buffer = AudioBuffer(
            samples: [0, 1, -1, 0], format: AudioFormat())
        let encoder = AudioEncoder()

        #expect(throws: ChoirError.self) { try encoder.encodeMP3(buffer) }
        #expect(throws: ChoirError.self) { try encoder.encodeAAC(buffer) }
        #expect(throws: ChoirError.self) { try encoder.encodeFLAC(buffer) }
        #expect(throws: Never.self) { _ = try encoder.encodeWAV(buffer) }
    }
}

/// SRS TXT-020 — which phonemes the rules actually get wrong.
@Suite("SRS TXT-020 — G2P error analysis")
struct G2PErrorAnalysisTests {

    private var rulesOnlyPhonemizer: Phonemizer {
        Phonemizer(builtInLexicon: nil)
    }

    @Test("Alignment classifies each edit")
    func testAlignment() {
        #expect(G2PErrorAnalysis.align(predicted: ["a"], expected: ["a"]).isEmpty)

        #expect(G2PErrorAnalysis.align(predicted: ["b"], expected: ["a"])
            == [.substitute(from: "a", to: "b")])

        // Prediction invented a phoneme.
        #expect(G2PErrorAnalysis.align(predicted: ["a", "b"], expected: ["a"])
            == [.insert("b")])

        // Prediction dropped one the reference had.
        #expect(G2PErrorAnalysis.align(predicted: ["a"], expected: ["a", "b"])
            == [.delete("b")])
    }

    @Test("A perfect prediction records no errors")
    func testNoErrors() {
        let lexicon = BuiltInLexicon(entries: ["hello": "HH AH0 L OW1"])
        let report = G2PErrorAnalysis().analyze(
            words: ["hello"],
            reference: { lexicon.arpabet(for: $0) },
            phonemizer: Phonemizer(builtInLexicon: lexicon))
        #expect(report.totalErrors == 0)
        #expect(report.substitutions.isEmpty)
    }

    /// Prints the confusion tables so a suite run names the next defect.
    @Test("TXT-020: most frequent phoneme errors")
    func testConfusions() {
        let lexicon = BuiltInLexicon.shared
        let words = G2PEvaluator.sampleWords(from: lexicon, count: 2_000)
        let analysis = G2PErrorAnalysis()
        let report = analysis.analyze(
            words: words,
            reference: { lexicon.arpabet(for: $0) },
            phonemizer: rulesOnlyPhonemizer)

        print("\nTXT-020 phoneme error analysis (rules only, no lexicon):\n")
        print(analysis.markdown(report))
        print("")

        #expect(report.totalErrors > 0)
        #expect(!report.substitutions.isEmpty)
        // Ordered most-frequent-first, so the first row is the next fix.
        for (lhs, rhs) in zip(report.substitutions, report.substitutions.dropFirst()) {
            #expect(lhs.count >= rhs.count)
        }
    }
}
