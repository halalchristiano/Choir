import Foundation
import Testing
@testable import Choir

/// The recording script in RECORDING_PROTOCOL.md must earn its claims
/// (SRS ML-A, DOC-001).
///
/// A recording session is expensive and effectively unrepeatable — the room,
/// the mic position and the speaker's voice on the day cannot be recovered
/// later. A script that turns out to have missed a phoneme, or to have quietly
/// included the evaluation corpus, is discovered after the session when it is
/// too late to fix cheaply. So the script is checked here instead.
@Suite("Recording script coverage")
struct RecordingScriptTests {

    static var protocolText: String? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try? String(
            contentsOf: root.appendingPathComponent("RECORDING_PROTOCOL.md"),
            encoding: .utf8)
    }

    /// The numbered sentences of Parts B, C and D.
    static var scriptSentences: [String] {
        guard let text = protocolText else { return [] }
        var sentences: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // "12. Some sentence." — the numbered script lines. Bold markdown
            // list items and prose are not numbered this way.
            guard let dot = trimmed.firstIndex(of: "."),
                  Int(trimmed[trimmed.startIndex..<dot]) != nil else { continue }
            let sentence = trimmed[trimmed.index(after: dot)...]
                .trimmingCharacters(in: .whitespaces)
            guard sentence.count > 12, !sentence.hasPrefix("**") else { continue }
            sentences.append(sentence)
        }
        return sentences
    }

    @Test("The script is found and parsed")
    func testScriptParses() {
        #expect(Self.protocolText != nil, "RECORDING_PROTOCOL.md not found")
        #expect(Self.scriptSentences.count >= 70,
                "parsed only \(Self.scriptSentences.count) sentences; the parser or the script changed")
    }

    /// The expensive mistake: a phoneme the speaker never said.
    ///
    /// A model cannot learn a sound that is absent from its training data, and
    /// the gap does not show up until synthesis produces a word containing it.
    @Test("ML-A: the script exercises every phoneme in the inventory")
    func testPhonemeCoverage() {
        let phonemizer = Phonemizer()
        var produced = Set<String>()
        for sentence in Self.scriptSentences {
            for word in sentence.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
            where !word.isEmpty {
                for phoneme in phonemizer.phonemize(word) {
                    produced.insert(phoneme.symbol)
                }
            }
        }

        let inventory = Set(PhonemeInventory.all.map(\.ipa))
        let missing = inventory.subtracting(produced).sorted()

        #expect(missing.isEmpty, """
            The recording script never elicits: \(missing.joined(separator: " "))

            A model cannot learn a sound the speaker never made. Add a sentence
            containing each missing symbol before recording, not after.
            """)
    }

    /// The contamination mistake: training on the evaluation corpus.
    ///
    /// QUA-004 is the only quality measurement this project has. A model
    /// trained on the Harvard sentences would be scored on material it had
    /// memorised, and the number would mean nothing.
    @Test("QUA-004: the script does not include the evaluation corpus")
    func testNoEvaluationCorpusOverlap() {
        func normalize(_ text: String) -> String {
            text.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        let corpus = Set(HarvardSentences.standard.map(normalize))
        #expect(!corpus.isEmpty, "the evaluation corpus is empty; this guard proves nothing")

        let overlap = Self.scriptSentences
            .map(normalize)
            .filter { corpus.contains($0) }

        #expect(overlap.isEmpty, """
            The recording script contains \(overlap.count) sentence(s) from the
            QUA-004 evaluation corpus:

            \(overlap.joined(separator: "\n"))

            Training on these makes the intelligibility measurement meaningless.
            """)
    }

    /// Utterances that are too long are hard to align and hard to read
    /// consistently; the protocol itself advises 5-20 words.
    @Test("Script sentences are a sensible length to record")
    func testSentenceLength() {
        for sentence in Self.scriptSentences {
            let words = sentence.split(separator: " ").count
            #expect(words <= 25,
                    "too long to record in one clean take (\(words) words): \(sentence)")
        }
    }
}
