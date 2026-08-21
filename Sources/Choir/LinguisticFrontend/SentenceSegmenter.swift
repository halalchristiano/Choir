import Foundation

/// Strength of a prosodic boundary (SRS TXT-030).
///
/// Passed to the prosody system so that pause length and pitch reset match the
/// structural weight of the break.
public enum PhraseBoundary: String, Sendable, Equatable, Codable, CaseIterable, Comparable {
    /// Within a sentence: a comma, or a breath group division.
    case minor

    /// Between sentences.
    case major

    /// Between paragraphs (TXT-032).
    case paragraph

    /// Between chapters or sections (TXT-032).
    case section

    /// Nominal pause in milliseconds before scaling by the voice's pause style.
    public var nominalPauseMs: Double {
        switch self {
        case .minor: return 200
        case .major: return 500
        case .paragraph: return 900
        case .section: return 1500
        }
    }

    /// Whether the boundary resets the pitch baseline (TXT-032).
    public var resetsPitch: Bool {
        self >= .paragraph
    }

    private var rank: Int {
        switch self {
        case .minor: return 0
        case .major: return 1
        case .paragraph: return 2
        case .section: return 3
        }
    }

    public static func < (lhs: PhraseBoundary, rhs: PhraseBoundary) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// A run of words to be spoken between two boundaries.
public struct BreathGroup: Sendable, Equatable {
    /// The text of the group.
    public let text: String

    /// The boundary that follows it.
    public let boundary: PhraseBoundary

    /// Number of whitespace-separated words.
    public var wordCount: Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    public init(text: String, boundary: PhraseBoundary) {
        self.text = text
        self.boundary = boundary
    }

    /// Estimated spoken duration in seconds at a voice's base tempo.
    public func estimatedDurationSeconds(syllablesPerSecond: Double) -> Double {
        guard syllablesPerSecond > 0 else { return 0 }
        return Double(estimatedSyllables) / syllablesPerSecond
    }

    /// A cheap syllable estimate: vowel groups per word, at least one each.
    ///
    /// Deliberately approximate. Breath-group division needs a length signal,
    /// not a phonemization, and running the full front end here would make
    /// segmentation depend on the thing it feeds.
    public var estimatedSyllables: Int {
        var total = 0
        for word in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            var count = 0
            var previousWasVowel = false
            for character in word {
                let isVowel = "aeiouy".contains(character)
                if isVowel && !previousWasVowel { count += 1 }
                previousWasVowel = isVowel
            }
            // Silent final "e" as in "make" is not its own syllable.
            if word.hasSuffix("e"), count > 1 { count -= 1 }
            total += max(1, count)
        }
        return max(1, total)
    }
}

/// Splits text into sentences and breath groups (SRS TXT-030, TXT-031, TXT-032).
///
/// TXT-030 requires segmentation robust to abbreviations ("Dr. Smith
/// arrived."), decimal points, quotations and dialogue punctuation, and
/// requires phrase-boundary strength to be passed on to prosody.
///
/// TXT-031 requires long sentences to be divided into breath groups at
/// syntactically plausible points, so that no group exceeds a duration the
/// voice can sustain.
public struct SentenceSegmenter: Sendable {

    /// Words that end in a period without ending a sentence.
    ///
    /// The list matters: "Dr. Smith arrived." must be one sentence, and the
    /// specification names that exact case.
    static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "rev", "fr", "sr", "jr", "st",
        "ave", "blvd", "rd", "ln", "ct", "vs", "etc", "inc", "ltd", "co",
        "corp", "dept", "est", "fig", "vol", "no", "op", "pp", "ed", "al",
        "approx", "appt", "apt", "dec", "jan", "feb", "mar", "apr", "jun",
        "jul", "aug", "sep", "sept", "oct", "nov", "min", "max", "misc",
        "gen", "exod", "lev", "num", "deut", "josh", "judg", "ps", "prov",
        "eccl", "isa", "jer", "lam", "ezek", "dan", "hos", "obad", "jon",
        "mic", "nah", "hab", "zeph", "hag", "zech", "mal", "matt", "rom",
        "cor", "gal", "eph", "phil", "col", "thess", "tim", "tit", "philem",
        "heb", "jas", "pet", "rev", "am", "pm", "ca", "cf", "eg", "ie",
    ]

    /// Conjunctions and subordinators that make a plausible breath boundary.
    ///
    /// Splitting before one of these lands on a phrase edge rather than in the
    /// middle of a constituent, which is what TXT-031 means by "syntactically
    /// plausible".
    static let breathCandidates: Set<String> = [
        "and", "but", "or", "nor", "yet", "so", "for",
        "because", "although", "though", "while", "whereas", "unless",
        "until", "when", "whenever", "where", "wherever", "which", "who",
        "whom", "whose", "that", "if", "since", "after", "before", "as",
        "however", "therefore", "moreover", "meanwhile", "then",
    ]

    /// Word count above which a sentence is divided (TXT-031's "~30 words").
    public let maxWordsPerBreathGroup: Int

    /// Longest a breath group may last, in seconds.
    public let maxBreathGroupSeconds: Double

    public init(maxWordsPerBreathGroup: Int = 30, maxBreathGroupSeconds: Double = 9.0) {
        self.maxWordsPerBreathGroup = maxWordsPerBreathGroup
        self.maxBreathGroupSeconds = maxBreathGroupSeconds
    }

    // MARK: - Sentences

    /// Splits `text` into sentences, each with the boundary that follows it.
    public func sentences(in text: String) -> [BreathGroup] {
        var results: [BreathGroup] = []
        var current = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            current.append(character)

            if character == "\n" {
                // Two or more newlines are a paragraph break (TXT-032).
                var lookahead = text.index(after: index)
                var newlines = 1
                while lookahead < text.endIndex,
                      text[lookahead] == "\n" || text[lookahead] == "\r" || text[lookahead] == " " {
                    if text[lookahead] == "\n" { newlines += 1 }
                    lookahead = text.index(after: lookahead)
                }
                if newlines >= 2 {
                    let boundary: PhraseBoundary = newlines >= 3 ? .section : .paragraph
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        results.append(BreathGroup(text: trimmed, boundary: boundary))
                    } else if let last = results.popLast() {
                        // The sentence already ended at its full stop, so the
                        // break belongs to it: promote its boundary rather
                        // than discarding the paragraph entirely.
                        results.append(BreathGroup(text: last.text, boundary: boundary))
                    }
                    current = ""
                    index = lookahead
                    continue
                }
            }

            if ".!?".contains(character), Self.isSentenceEnd(text, at: index) {
                // Absorb trailing quotes and brackets belonging to the sentence.
                var end = text.index(after: index)
                while end < text.endIndex, "\"'”’)]".contains(text[end]) {
                    current.append(text[end])
                    end = text.index(after: end)
                }
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    results.append(BreathGroup(text: trimmed, boundary: .major))
                }
                current = ""
                index = end
                continue
            }

            index = text.index(after: index)
        }

        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            results.append(BreathGroup(text: trimmed, boundary: .major))
        }
        return results
    }

    /// Whether the terminator at `index` genuinely ends a sentence.
    ///
    /// Rejects decimal points, abbreviations and initials.
    static func isSentenceEnd(_ text: String, at index: String.Index) -> Bool {
        // Dialogue punctuation: in `"Stop there!" she cried.` the '!' closes
        // the quotation, not the sentence. A lowercase word after the
        // terminator (and any closing quotes) marks a continuation.
        var probe = text.index(after: index)
        var sawClosingQuote = false
        while probe < text.endIndex, "\"'”’)]".contains(text[probe]) {
            sawClosingQuote = true
            probe = text.index(after: probe)
        }
        var sawSpace = false
        while probe < text.endIndex, text[probe].isWhitespace {
            sawSpace = true
            probe = text.index(after: probe)
        }
        // A closing quote must intervene. Without that condition the rule
        // swallows every boundary in lowercased text -- "one. two. three."
        // becomes a single sentence -- because a following lowercase word is
        // then the norm rather than the signal.
        if sawClosingQuote, sawSpace, probe < text.endIndex, text[probe].isLowercase {
            return false
        }

        guard text[index] == "." else { return true }  // '!' and '?' otherwise end

        // A digit either side means a decimal point: "3.14".
        let after = text.index(after: index)
        if after < text.endIndex, text[after].isNumber,
           index > text.startIndex, text[text.index(before: index)].isNumber {
            return false
        }

        // Collect the word before the period.
        var start = index
        var word = ""
        while start > text.startIndex {
            let previous = text.index(before: start)
            let character = text[previous]
            if character.isWhitespace { break }
            word.insert(character, at: word.startIndex)
            start = previous
        }
        let bare = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"'([{"))

        // A single letter is an initial: "C. S. Lewis".
        if bare.count == 1, bare.first?.isLetter == true { return false }

        if abbreviations.contains(bare) {
            // An abbreviation ends the sentence only if what follows starts a
            // new one: end of input, or a capitalized word after the space.
            var lookahead = after
            while lookahead < text.endIndex, text[lookahead].isWhitespace {
                lookahead = text.index(after: lookahead)
            }
            guard lookahead < text.endIndex else { return true }
            // "Dr. Smith" continues; "etc. The" starts anew only weakly, so
            // abbreviations are treated as non-terminal, which is the safer
            // error: a missed break shortens a pause, a false one truncates.
            return false
        }

        return true
    }

    // MARK: - Breath groups

    /// Divides a sentence into breath groups (TXT-031).
    ///
    /// A sentence short enough to speak in one breath is returned unchanged.
    /// Longer ones are split at commas, semicolons and colons first, since
    /// those are already prosodic boundaries, and then before conjunctions
    /// when a run is still too long.
    public func breathGroups(
        in sentence: String,
        syllablesPerSecond: Double = 4.5,
        finalBoundary: PhraseBoundary = .major
    ) -> [BreathGroup] {
        let whole = BreathGroup(text: sentence, boundary: finalBoundary)
        guard needsDivision(whole, syllablesPerSecond: syllablesPerSecond) else {
            return [whole]
        }

        // Pass 1: split on punctuation that is already a boundary.
        var chunks = splitOnPunctuation(sentence)

        // Pass 2: any chunk still too long is split before a conjunction.
        var refined: [String] = []
        for chunk in chunks {
            let candidate = BreathGroup(text: chunk, boundary: .minor)
            if needsDivision(candidate, syllablesPerSecond: syllablesPerSecond) {
                refined.append(contentsOf: splitOnConjunctions(chunk))
            } else {
                refined.append(chunk)
            }
        }
        // Pass 3: the word cap alone does not bound duration -- thirty
        // polysyllabic words last far longer than thirty short ones -- so any
        // chunk still over the ceiling is divided by estimated syllables.
        chunks = refined.flatMap { enforceDuration($0, syllablesPerSecond: syllablesPerSecond) }
        chunks = chunks.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !chunks.isEmpty else { return [whole] }

        return chunks.enumerated().map { index, text in
            BreathGroup(
                text: text.trimmingCharacters(in: .whitespaces),
                boundary: index == chunks.count - 1 ? finalBoundary : .minor
            )
        }
    }

    /// Segments text fully: sentences, each divided into breath groups.
    public func segment(_ text: String, syllablesPerSecond: Double = 4.5) -> [BreathGroup] {
        sentences(in: text).flatMap { sentence in
            breathGroups(
                in: sentence.text,
                syllablesPerSecond: syllablesPerSecond,
                finalBoundary: sentence.boundary
            )
        }
    }

    /// Splits a chunk that still exceeds the duration ceiling.
    ///
    /// Divides into the fewest equal parts that each fit, at word boundaries.
    private func enforceDuration(_ chunk: String, syllablesPerSecond: Double) -> [String] {
        let group = BreathGroup(text: chunk, boundary: .minor)
        let duration = group.estimatedDurationSeconds(syllablesPerSecond: syllablesPerSecond)
        guard duration > maxBreathGroupSeconds else { return [chunk] }

        let words = chunk.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > 1 else { return [chunk] }

        let parts = Int(ceil(duration / maxBreathGroupSeconds))
        let perPart = max(1, Int(ceil(Double(words.count) / Double(parts))))

        var result: [String] = []
        var index = 0
        while index < words.count {
            let end = min(index + perPart, words.count)
            result.append(words[index..<end].joined(separator: " "))
            index = end
        }
        return result
    }

    private func needsDivision(_ group: BreathGroup, syllablesPerSecond: Double) -> Bool {
        group.wordCount > maxWordsPerBreathGroup
            || group.estimatedDurationSeconds(syllablesPerSecond: syllablesPerSecond) > maxBreathGroupSeconds
    }

    private func splitOnPunctuation(_ sentence: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in sentence {
            current.append(character)
            if ",;:".contains(character) {
                chunks.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { chunks.append(current) }
        return chunks.isEmpty ? [sentence] : chunks
    }

    private func splitOnConjunctions(_ chunk: String) -> [String] {
        let words = chunk.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count > maxWordsPerBreathGroup else { return [chunk] }

        var chunks: [String] = []
        var current: [String] = []

        for word in words {
            let bare = word.lowercased().trimmingCharacters(
                in: CharacterSet(charactersIn: ",.;:!?\"'()"))

            // Break *before* the conjunction, and only once the run is long
            // enough that breaking improves it.
            if Self.breathCandidates.contains(bare), current.count >= maxWordsPerBreathGroup / 2 {
                chunks.append(current.joined(separator: " "))
                current = [word]
                continue
            }
            current.append(word)

            // Hard limit: never exceed the word cap even with no candidate.
            if current.count >= maxWordsPerBreathGroup {
                chunks.append(current.joined(separator: " "))
                current = []
            }
        }
        if !current.isEmpty { chunks.append(current.joined(separator: " ")) }
        return chunks.isEmpty ? [chunk] : chunks
    }
}
