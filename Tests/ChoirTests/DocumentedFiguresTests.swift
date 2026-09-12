import Foundation
import Testing
@testable import Choir

/// Every measurable figure quoted in the documentation must match the
/// measurement (SRS DOC-001).
///
/// This repository's one durable habit is replacing unverifiable claims with
/// measured ones, and it has lost that fight three times: PROJECT_STATUS.md
/// declared the project proprietary while LICENSE was MIT; seven files called
/// the formant output "intelligible" with nothing behind the word; and the G2P
/// accuracy figure appeared in five documents that had to be edited by hand
/// every time it moved, which is how one of them ended up wrong.
///
/// The fix is not more care. It is a test that fails when a number in a
/// document disagrees with the number the code produces. A figure only needs
/// to be written down once here to be defended everywhere.
@Suite("SRS DOC-001 — documented figures match measurement")
struct DocumentedFiguresTests {

    /// Repository root, derived from this file's own location so the test does
    /// not depend on the working directory a runner happens to choose.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)          // .../Tests/ChoirTests/<this>.swift
            .deletingLastPathComponent()          // .../Tests/ChoirTests
            .deletingLastPathComponent()          // .../Tests
            .deletingLastPathComponent()          // repository root
    }

    /// The documents that quote measured figures.
    static let documents = [
        "README.md",
        "PROJECT_STATUS.md",
        "SRS_CONFORMANCE.md",
        "REMAINING_WORK.md",
        "QUA004_FORMANT.md",
        "CHANGELOG.md",
    ]

    static func text(of name: String) -> String? {
        try? String(contentsOf: repositoryRoot.appendingPathComponent(name), encoding: .utf8)
    }

    /// Every percentage in `text` that is presented as a G2P accuracy figure.
    ///
    /// Matches a percentage preceded, within a short window, by wording that
    /// marks it as the OOV accuracy measurement. Historical entries are
    /// deliberately excluded by the caller rather than here.
    static func quotedPercentages(in text: String, matching pattern: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: text) else { return nil }
            return Double(text[captured])
        }
    }


    /// Whether two substrings occur within `within` characters of each other.
    static func areNear(_ text: String, _ lhs: String, _ rhs: String, within: Int) -> Bool {
        let chars = Array(text)
        func offsets(of needle: String) -> [Int] {
            let target = Array(needle)
            guard !target.isEmpty, chars.count >= target.count else { return [] }
            return (0...(chars.count - target.count)).filter { start in
                Array(chars[start..<(start + target.count)]) == target
            }
        }
        let left = offsets(of: lhs), right = offsets(of: rhs)
        for a in left where right.contains(where: { abs($0 - a) <= within }) { _ = a; return true }
        return false
    }

    // MARK: - Figures the code can produce right now

    @Test("Documents exist where the test expects them")
    func testDocumentsFound() {
        for name in Self.documents {
            #expect(Self.text(of: name) != nil,
                    "\(name) not found at \(Self.repositoryRoot.path); the guard would pass vacuously")
        }
    }

    @Test("DOC-001: the quoted voice count matches Voice.allCases")
    func testVoiceCount() {
        let measured = Voice.allCases.count
        // Only phrasings that state the size of the library. A bare "N voices"
        // also matches roadmap lines like "expand to 4 voices", which are not
        // claims about the current library and must not fail the build.
        let patterns = [
            #"(\d+)[- ](?:stable )?[Vv]oice cases"#,
            #"(\d+)-voice library"#,
            #"all (\d+) voices"#,
            #"[Tt]he (\d+) voices"#,
        ]
        var checked = 0
        for name in Self.documents {
            guard let text = Self.text(of: name) else { continue }
            for pattern in patterns {
                for value in Self.quotedPercentages(in: text, matching: pattern) {
                    checked += 1
                    #expect(Int(value) == measured,
                            "\(name) claims \(Int(value)) voices; Voice.allCases has \(measured)")
                }
            }
        }
        #expect(checked > 0, "no library-size claim found; the guard protects nothing")
    }

    @Test("DOC-001: the quoted theological lexicon size matches the lexicon")
    func testTheologicalLexiconSize() {
        let measured = TheologicalLexicon.entries.count
        for name in Self.documents {
            guard let text = Self.text(of: name) else { continue }
            let quoted = Self.quotedPercentages(
                in: text, matching: #"(\d+)\s+entries against the 2,500"#)
            for value in quoted {
                #expect(Int(value) == measured,
                        "\(name) claims \(Int(value)) theological entries; the lexicon has \(measured)")
            }
        }
    }

    /// The figure that has drifted most often.
    ///
    /// Only the current-state documents are checked. CHANGELOG.md and the
    /// audit log in REMAINING_WORK.md record what was true at a past commit,
    /// and rewriting history to satisfy a test would defeat the point of
    /// keeping it.
    @Test("DOC-001: the quoted G2P accuracy matches the measurement")
    func testG2PAccuracy() {
        let lexicon = BuiltInLexicon.shared
        let words = G2PEvaluator.sampleWords(from: lexicon, count: 2_000)
        let report = G2PEvaluator().evaluate(
            words: words,
            reference: { lexicon.arpabet(for: $0) },
            phonemizer: Phonemizer(builtInLexicon: nil))
        let measured = (report.phonemeAccuracy * 1000).rounded() / 10  // one decimal

        var checked = 0
        for name in ["PROJECT_STATUS.md", "SRS_CONFORMANCE.md", "REMAINING_WORK.md"] {
            guard let text = Self.text(of: name) else { continue }
            // A percentage stated against the 92% target is the OOV figure.
            let patterns = [
                #"accuracy is \*?\*?([\d.]+)%\*?\*? against"#,
                #"measured at \*\*([\d.]+)%\*\* against a 92%"#,
                #"Phoneme accuracy \| \*\*([\d.]+)%\*\*"#,
            ]
            for pattern in patterns {
                for value in Self.quotedPercentages(in: text, matching: pattern) {
                    checked += 1
                    #expect(abs(value - measured) < 0.15,
                            "\(name) quotes G2P accuracy \(value)%; measured \(measured)%")
                }
            }
        }

        #expect(checked > 0,
                "no G2P figure found in any current-state document; the guard is not protecting anything")
    }

    /// The word this repository has misused before.
    ///
    /// "Intelligible" was applied to the formant path in seven files with no
    /// measurement behind it, and the measurement — 8.2% against a 98% target —
    /// contradicted it. The word is allowed near the formant path only where a
    /// figure appears alongside it.
    @Test("DOC-001: 'intelligible' is not claimed of the formant path unqualified")
    func testIntelligibilityClaims() {
        let sources = (try? FileManager.default.subpathsOfDirectory(
            atPath: Self.repositoryRoot.appendingPathComponent("Sources").path)) ?? []
        let swiftFiles = sources.filter { $0.hasSuffix(".swift") }.map { "Sources/" + $0 }

        // Paragraphs, not lines: these documents are hard-wrapped, so "formant"
        // and "intelligible" routinely land on different lines of one sentence.
        for name in Self.documents + swiftFiles {
            guard let text = Self.text(of: name) else { continue }
            for paragraph in text.components(separatedBy: "\n\n") {
                let lower = paragraph.lowercased()
                guard lower.contains("intelligible"), lower.contains("formant") else { continue }
                // Proximity, not mere co-occurrence: a conformance table or a
                // long bullet list contains both words without ever making the
                // claim. Require them within one sentence's reach.
                guard Self.areNear(lower, "intelligible", "formant", within: 220) else { continue }
                // A quoted mention discusses the word rather than asserting it,
                // which is what the entry recording its removal does.
                guard !paragraph.contains("\"intelligible\"") else { continue }
                let qualified = lower.contains("not intelligible")
                    || lower.contains("rather than")
                    || lower.contains("8.2%")
                    || lower.contains("98%")
                    || lower.contains("qua-004")
                    || lower.contains("qua004")
                    || lower.contains("without that number")
                #expect(qualified,
                        """
                        \(name) describes the formant path as intelligible with no measurement:

                        \(paragraph.trimmingCharacters(in: .whitespacesAndNewlines))

                        Cite the QUA-004 figure, or say what it is not.
                        """)
            }
        }
    }
}
