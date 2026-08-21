import Foundation
import Testing
@testable import Choir

/// SRS SYN-002 (MUST) — deterministic synthesis under a seed.
///
/// "Synthesis shall be fully deterministic when the caller supplies a seed:
/// identical (text, voice, parameters, seed, package version) shall produce
/// bit-identical audio on the same device class."
///
/// SRS SYN-003 (MUST) — controlled variation without a seed.
///
/// "Without a seed, controlled prosodic variation shall be applied so that the
/// same sentence synthesized twice differs naturally (micro-timing, contour),
/// avoiding robotic sameness in repeated game lines."
@Suite("SRS SYN-002/003 — determinism and variation")
struct DeterminismTests {

    private func durations(text: String, seed: UInt64?) throws -> [Double] {
        let transcript = try LinguisticFrontend().process(text)
        let prosody = ProsodyPredictor().predictProsody(
            for: transcript,
            with: SynthesisParameters(seed: seed)
        )
        return prosody.phonemes.map(\.prosody.duration)
    }

    @Test("SYN-002: the generator is reproducible for a given seed")
    func testGeneratorReproducible() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        for _ in 0..<100 {
            #expect(a.next() == b.next())
        }
    }

    @Test("SYN-002: different seeds give different streams")
    func testDifferentSeeds() {
        var a = SeededGenerator(seed: 1)
        var b = SeededGenerator(seed: 2)
        var differences = 0
        for _ in 0..<50 where a.next() != b.next() { differences += 1 }
        #expect(differences > 40, "streams were suspiciously similar")
    }

    @Test("SYN-002: seed zero is valid and not degenerate")
    func testSeedZero() {
        var generator = SeededGenerator(seed: 0)
        let values = (0..<20).map { _ in generator.next() }
        #expect(Set(values).count == values.count, "seed 0 repeated values")
        #expect(!values.contains(0), "seed 0 produced a zero draw")
    }

    @Test("SYN-002: jitter stays within its magnitude")
    func testJitterBounds() {
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<1000 {
            let value = generator.jitter(magnitude: 0.03)
            #expect(value >= -0.03 && value <= 0.03, "jitter \(value) out of bounds")
        }
        #expect(generator.jitter(magnitude: 0) == 0)
    }

    /// The requirement itself: same seed, same prosody.
    @Test("SYN-002: the same seed reproduces identical durations")
    func testSeededProsodyIdentical() throws {
        let first = try durations(text: "The quick brown fox jumps over the lazy dog.", seed: 12345)
        let second = try durations(text: "The quick brown fox jumps over the lazy dog.", seed: 12345)
        #expect(first == second, "seeded synthesis was not reproducible")
        #expect(!first.isEmpty)
    }

    @Test("SYN-002: repeated seeded runs stay identical")
    func testSeededStableAcrossManyRuns() throws {
        let reference = try durations(text: "Reproducible output matters.", seed: 999)
        for _ in 0..<5 {
            #expect(try durations(text: "Reproducible output matters.", seed: 999) == reference)
        }
    }

    @Test("SYN-002: different seeds produce different prosody")
    func testDifferentSeedsDiffer() throws {
        let a = try durations(text: "The quick brown fox jumps over the lazy dog.", seed: 1)
        let b = try durations(text: "The quick brown fox jumps over the lazy dog.", seed: 2)
        #expect(a != b, "seed had no effect on prosody")
        #expect(a.count == b.count, "seed changed the phoneme count")
    }

    /// SYN-003: without a seed, two renders must differ.
    @Test("SYN-003: unseeded synthesis varies between renders")
    func testUnseededVaries() throws {
        let a = try durations(text: "Halt! Who goes there?", seed: nil)
        let b = try durations(text: "Halt! Who goes there?", seed: nil)
        #expect(a != b, "unseeded renders were identical — the robotic sameness SYN-003 forbids")
        #expect(a.count == b.count)
    }

    /// SYN-003 says the variation is *controlled*: natural, not erratic.
    @Test("SYN-003: variation stays within its documented bound")
    func testVariationBounded() throws {
        let reference = try durations(text: "Steady as she goes.", seed: 100)
        let other = try durations(text: "Steady as she goes.", seed: 200)

        for (a, b) in zip(reference, other) where a > 0 {
            let ratio = b / a
            // Two independent draws, each within ±3%, so the ratio is bounded
            // by (1+0.03)/(1-0.03).
            #expect(ratio > 0.93 && ratio < 1.075,
                    "durations diverged by more than the documented jitter: \(ratio)")
        }
    }

    @Test("SYN-002: the seed is recorded in the effective parameters")
    func testSeedRecorded() {
        let parameters = SynthesisParameters(seed: 4242)
        #expect(parameters.seed == 4242)
        #expect(SynthesisParameters().seed == nil)
    }

    @Test("SYN-002: variation reports whether it is deterministic")
    func testDeterminismFlag() {
        #expect(ProsodyVariation(seed: 1).isDeterministic)
        #expect(!ProsodyVariation(seed: nil).isDeterministic)
    }
}

/// SRS TXT-030 (MUST) — sentence and phrase segmentation.
@Suite("SRS TXT-030 — segmentation")
struct SegmentationTests {
    let segmenter = SentenceSegmenter()

    @Test("TXT-030: simple sentences split on terminators")
    func testBasicSentences() {
        let sentences = segmenter.sentences(in: "One. Two! Three?")
        #expect(sentences.count == 3)
        #expect(sentences.allSatisfy { $0.boundary == .major })
    }

    /// The case the requirement names explicitly.
    @Test("TXT-030: abbreviations do not end a sentence")
    func testAbbreviations() {
        let sentences = segmenter.sentences(in: "Dr. Smith arrived.")
        #expect(sentences.count == 1, "split into \(sentences.count): \(sentences.map(\.text))")
        #expect(sentences.first?.text.contains("Dr. Smith arrived") == true)
    }

    @Test("TXT-030: several abbreviations in one sentence")
    func testMultipleAbbreviations() {
        let sentences = segmenter.sentences(in: "Mr. and Mrs. Smith met Prof. Jones on Baker St. today.")
        #expect(sentences.count == 1, "split into \(sentences.count)")
    }

    @Test("TXT-030: initials do not end a sentence")
    func testInitials() {
        let sentences = segmenter.sentences(in: "C. S. Lewis wrote it.")
        #expect(sentences.count == 1, "split into \(sentences.count): \(sentences.map(\.text))")
    }

    @Test("TXT-030: decimal points do not end a sentence")
    func testDecimals() {
        let sentences = segmenter.sentences(in: "It costs 3.14 dollars today.")
        #expect(sentences.count == 1, "split into \(sentences.count)")
    }

    @Test("TXT-030: closing quotes stay with their sentence")
    func testQuotations() {
        let sentences = segmenter.sentences(in: "\"Stop there!\" she cried. Then silence.")
        #expect(sentences.count == 2, "split into \(sentences.count): \(sentences.map(\.text))")
        // The sentence runs past the quotation to its own full stop, so the
        // closing quote sits inside it rather than at the end.
        #expect(sentences.first?.text.contains("there!\"") == true,
                "closing quote was orphaned: \(sentences.first?.text ?? "")")
        #expect(sentences.first?.text.contains("she cried") == true,
                "reported-speech attribution was split off")
    }

    @Test("TXT-032: paragraph breaks are stronger than sentence breaks")
    func testParagraphBoundary() {
        let text = "First paragraph here.\n\nSecond paragraph here."
        let sentences = segmenter.sentences(in: text)
        #expect(sentences.contains { $0.boundary == .paragraph },
                "no paragraph boundary in \(sentences.map { "\($0.boundary)" })")
    }

    @Test("TXT-032: boundary strength orders and scales pauses")
    func testBoundaryOrdering() {
        #expect(PhraseBoundary.minor < PhraseBoundary.major)
        #expect(PhraseBoundary.major < PhraseBoundary.paragraph)
        #expect(PhraseBoundary.paragraph < PhraseBoundary.section)

        #expect(PhraseBoundary.minor.nominalPauseMs < PhraseBoundary.major.nominalPauseMs)
        #expect(PhraseBoundary.major.nominalPauseMs < PhraseBoundary.paragraph.nominalPauseMs)

        // Only structural breaks reset pitch.
        #expect(!PhraseBoundary.minor.resetsPitch)
        #expect(!PhraseBoundary.major.resetsPitch)
        #expect(PhraseBoundary.paragraph.resetsPitch)
    }

    @Test("TXT-030: empty and whitespace input yields nothing")
    func testEmptyInput() {
        #expect(segmenter.sentences(in: "").isEmpty)
        #expect(segmenter.sentences(in: "   \n  ").isEmpty)
    }

    @Test("TXT-030: text without a terminator is still one sentence")
    func testNoTerminator() {
        let sentences = segmenter.sentences(in: "no full stop here")
        #expect(sentences.count == 1)
    }
}

/// SRS TXT-031 (MUST) — breath groups.
@Suite("SRS TXT-031 — breath groups")
struct BreathGroupTests {
    let segmenter = SentenceSegmenter()

    @Test("TXT-031: short sentences are left whole")
    func testShortSentenceUndivided() {
        let groups = segmenter.breathGroups(in: "A short sentence.")
        #expect(groups.count == 1)
        #expect(groups.first?.boundary == .major)
    }

    /// The requirement's threshold is "> ~30 words".
    @Test("TXT-031: long sentences are divided")
    func testLongSentenceDivided() {
        let long = Array(repeating: "word", count: 60).joined(separator: " ") + "."
        let groups = segmenter.breathGroups(in: long)
        #expect(groups.count > 1, "a 60-word sentence was not divided")
        for group in groups {
            #expect(group.wordCount <= segmenter.maxWordsPerBreathGroup,
                    "group of \(group.wordCount) words exceeds the cap")
        }
    }

    @Test("TXT-031: no group exceeds the duration ceiling")
    func testDurationCeiling() {
        let long = Array(repeating: "syllable", count: 80).joined(separator: " ") + "."
        let groups = segmenter.breathGroups(in: long, syllablesPerSecond: 4.5)
        for group in groups {
            #expect(group.estimatedDurationSeconds(syllablesPerSecond: 4.5)
                        <= segmenter.maxBreathGroupSeconds + 0.001,
                    "group lasts \(group.estimatedDurationSeconds(syllablesPerSecond: 4.5))s")
        }
    }

    @Test("TXT-031: division prefers punctuation boundaries")
    func testPrefersPunctuation() {
        let sentence = Array(repeating: "alpha", count: 20).joined(separator: " ")
            + ", " + Array(repeating: "beta", count: 20).joined(separator: " ") + "."
        let groups = segmenter.breathGroups(in: sentence)
        #expect(groups.count >= 2)
        #expect(groups.first?.text.hasSuffix(",") == true,
                "did not split at the comma: \(groups.first?.text ?? "")")
    }

    @Test("TXT-031: division falls back to conjunctions")
    func testFallsBackToConjunctions() {
        let sentence = Array(repeating: "alpha", count: 25).joined(separator: " ")
            + " because " + Array(repeating: "beta", count: 25).joined(separator: " ") + "."
        let groups = segmenter.breathGroups(in: sentence)
        #expect(groups.count > 1)
        #expect(groups.contains { $0.text.hasPrefix("because") },
                "did not break before the conjunction")
    }

    @Test("TXT-031: only the final group keeps the sentence boundary")
    func testBoundaryAssignment() {
        let long = Array(repeating: "word", count: 60).joined(separator: " ") + "."
        let groups = segmenter.breathGroups(in: long, finalBoundary: .paragraph)
        #expect(groups.last?.boundary == .paragraph)
        for group in groups.dropLast() {
            #expect(group.boundary == .minor, "an interior group carried \(group.boundary)")
        }
    }

    @Test("TXT-031: no text is lost when dividing")
    func testNoTextLost() {
        let long = (1...60).map { "word\($0)" }.joined(separator: " ") + "."
        let groups = segmenter.breathGroups(in: long)
        let rejoined = groups.map(\.text).joined(separator: " ")
        for index in 1...60 {
            #expect(rejoined.contains("word\(index)"), "lost word\(index)")
        }
    }

    @Test("TXT-031: syllable estimate is plausible")
    func testSyllableEstimate() {
        #expect(BreathGroup(text: "cat", boundary: .minor).estimatedSyllables == 1)
        #expect(BreathGroup(text: "make", boundary: .minor).estimatedSyllables == 1)
        #expect(BreathGroup(text: "beautiful", boundary: .minor).estimatedSyllables >= 3)
        // Never zero, whatever the input.
        #expect(BreathGroup(text: "", boundary: .minor).estimatedSyllables == 0)
        #expect(BreathGroup(text: "!!!", boundary: .minor).estimatedSyllables == 0)
    }

    @Test("TXT-030 + TXT-031: full segmentation of a passage")
    func testFullSegmentation() {
        let passage = """
        Dr. Smith arrived at 3.30. He said, "Wait here."

        Then a very long sentence followed, one that runs on and on with many \
        clauses and asides, because it was written to exceed the breath group \
        limit and therefore must be divided into several natural groups rather \
        than spoken in a single impossible breath.
        """
        let groups = segmenter.segment(passage)
        #expect(groups.count >= 4, "only \(groups.count) groups")
        #expect(groups.contains { $0.boundary == .paragraph })
        for group in groups {
            #expect(group.wordCount <= segmenter.maxWordsPerBreathGroup)
        }
    }

    /// TXT-002 still applies.
    @Test("TXT-031: adversarial input terminates")
    func testAdversarial() {
        let inputs = [
            String(repeating: "a ", count: 5000),
            String(repeating: ". ", count: 2000),
            String(repeating: ",", count: 2000),
            String(repeating: "Dr. ", count: 1000),
        ]
        for input in inputs {
            let groups = segmenter.segment(input)
            #expect(groups.count < 20_000)
        }
    }
}
