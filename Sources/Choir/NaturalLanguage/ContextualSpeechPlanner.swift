import Foundation

/// Configuration for Choir's deterministic, on-device natural-language pass.
///
/// Every capability is independently switchable so applications can retain
/// literal delivery for code, measurements, or externally authored prosody.
public struct NaturalLanguageProcessingConfiguration: Sendable, Equatable, Hashable, Codable {
    /// Enables the contextual speech-planning pass.
    public var isEnabled: Bool

    /// Classifies statements, questions, exclamations, and commands.
    public var detectsIntent: Bool

    /// Infers a restrained delivery emotion from lexical context.
    public var detectsEmotion: Bool

    /// Finds contrastive focus such as "not this, but that".
    public var detectsEmphasis: Bool

    /// Marks quoted spans as dialogue.
    public var detectsDialogue: Bool

    /// Adds clause boundaries at punctuation and discourse transitions.
    public var detectsClauseBoundaries: Bool

    public init(
        isEnabled: Bool = true,
        detectsIntent: Bool = true,
        detectsEmotion: Bool = true,
        detectsEmphasis: Bool = true,
        detectsDialogue: Bool = true,
        detectsClauseBoundaries: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.detectsIntent = detectsIntent
        self.detectsEmotion = detectsEmotion
        self.detectsEmphasis = detectsEmphasis
        self.detectsDialogue = detectsDialogue
        self.detectsClauseBoundaries = detectsClauseBoundaries
    }

    /// Natural-language processing disabled for literal or externally planned speech.
    public static let disabled = NaturalLanguageProcessingConfiguration(isEnabled: false)
}

/// Communicative purpose inferred for one utterance.
public enum UtteranceIntent: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case statement
    case question
    case exclamation
    case command
    case fragment
}

/// Restrained delivery emotion inferred from lexical context.
///
/// This is a speech-planning signal, not a claim about an author's actual
/// psychological state.
public enum ContextualEmotion: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case neutral
    case joyful
    case sad
    case angry
    case fearful
    case tender
    case solemn

    /// Semitone movement applied to the sentence baseline.
    public var pitchOffsetSemitones: Double {
        switch self {
        case .neutral: return 0
        case .joyful: return 1.1
        case .sad: return -1.2
        case .angry: return 0.5
        case .fearful: return 0.9
        case .tender: return -0.4
        case .solemn: return -0.9
        }
    }

    /// Sentence-level pace multiplier.
    public var rateScale: Double {
        switch self {
        case .neutral: return 1
        case .joyful: return 1.04
        case .sad: return 0.91
        case .angry: return 0.97
        case .fearful: return 1.03
        case .tender: return 0.94
        case .solemn: return 0.90
        }
    }

    /// Sentence-level loudness movement in decibels.
    public var energyDeltaDB: Double {
        switch self {
        case .neutral: return 0
        case .joyful: return 1.5
        case .sad: return -2
        case .angry: return 2.5
        case .fearful: return 0.5
        case .tender: return -1.2
        case .solemn: return -0.8
        }
    }
}

/// Strength of contextual focus assigned to one normalized word.
public enum ContextualEmphasis: Int, Sendable, Equatable, Hashable, Codable, Comparable {
    case none = 0
    case moderate = 1
    case strong = 2

    public static func < (lhs: ContextualEmphasis, rhs: ContextualEmphasis) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Natural-language cues attached to a normalized word.
public struct WordSpeechCue: Sendable, Equatable, Hashable, Codable {
    public let wordIndex: Int
    public let emphasis: ContextualEmphasis
    public let isDialogue: Bool

    /// Local pitch movement in semitones.
    public let pitchOffsetSemitones: Double

    /// Local duration multiplier.
    public let durationScale: Double

    /// Local loudness movement in decibels.
    public let energyDeltaDB: Double

    public init(
        wordIndex: Int,
        emphasis: ContextualEmphasis = .none,
        isDialogue: Bool = false,
        pitchOffsetSemitones: Double = 0,
        durationScale: Double = 1,
        energyDeltaDB: Double = 0
    ) {
        self.wordIndex = max(0, wordIndex)
        self.emphasis = emphasis
        self.isDialogue = isDialogue
        self.pitchOffsetSemitones = Self.bounded(
            pitchOffsetSemitones, range: -3...3, fallback: 0)
        self.durationScale = Self.bounded(durationScale, range: 0.8...1.3, fallback: 1)
        self.energyDeltaDB = Self.bounded(energyDeltaDB, range: -6...6, fallback: 0)
    }

    private static func bounded(
        _ value: Double, range: ClosedRange<Double>, fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

/// NLP analysis for one sentence, expressed in normalized-word coordinates.
public struct PlannedUtterance: Sendable, Equatable, Hashable, Codable {
    public let startWordIndex: Int
    public let endWordIndex: Int
    public let intent: UtteranceIntent
    public let emotion: ContextualEmotion
    public let isDialogue: Bool

    /// Confidence in the strongest non-neutral classification, from 0 to 1.
    public let confidence: Double

    public init(
        startWordIndex: Int,
        endWordIndex: Int,
        intent: UtteranceIntent,
        emotion: ContextualEmotion = .neutral,
        isDialogue: Bool = false,
        confidence: Double = 0.5
    ) {
        let start = max(0, startWordIndex)
        self.startWordIndex = start
        self.endWordIndex = max(start, endWordIndex)
        self.intent = intent
        self.emotion = emotion
        self.isDialogue = isDialogue
        self.confidence = confidence.isFinite ? min(1, max(0, confidence)) : 0
    }

    public func contains(wordIndex: Int) -> Bool {
        wordIndex >= startWordIndex && wordIndex <= endWordIndex
    }
}

/// Complete contextual speech plan produced before phoneme-level prosody.
public struct ContextualSpeechPlan: Sendable, Equatable, Codable {
    public let languageCode: String
    public let utterances: [PlannedUtterance]
    public let wordCues: [Int: WordSpeechCue]
    public let inferredBoundaries: [Int: PhraseBoundary]

    public init(
        languageCode: String = "en",
        utterances: [PlannedUtterance] = [],
        wordCues: [Int: WordSpeechCue] = [:],
        inferredBoundaries: [Int: PhraseBoundary] = [:]
    ) {
        self.languageCode = languageCode
        self.utterances = utterances
        self.wordCues = wordCues
        self.inferredBoundaries = inferredBoundaries
    }

    public func utterance(containingWord index: Int) -> PlannedUtterance? {
        utterances.first { $0.contains(wordIndex: index) }
    }

    public func cue(forWord index: Int) -> WordSpeechCue? {
        wordCues[index]
    }
}

/// An offline English natural-language processor specialized for speech planning.
///
/// The default implementation is deterministic and allocation-bounded. It
/// intentionally performs conservative inference: explicit punctuation,
/// discourse markers, and strongly diagnostic vocabulary affect delivery;
/// ambiguous prose remains neutral. A learned planner can be introduced later
/// without changing the typed plan consumed by the prosody system.
public struct ContextualSpeechPlanner: Sendable {
    public let configuration: NaturalLanguageProcessingConfiguration

    public init(
        configuration: NaturalLanguageProcessingConfiguration = NaturalLanguageProcessingConfiguration()
    ) {
        self.configuration = configuration
    }

    /// Plans already-normalized words. Indices in the result are parallel to `words`.
    public func plan(normalizedWords words: [String]) -> ContextualSpeechPlan {
        guard configuration.isEnabled, !words.isEmpty else {
            return ContextualSpeechPlan()
        }

        let lexicalWords = words.map(Self.lexicalForm)
        let ranges = Self.sentenceRanges(in: words)
        var utterances: [PlannedUtterance] = []
        utterances.reserveCapacity(ranges.count)
        var cues: [Int: WordSpeechCue] = [:]
        var boundaries: [Int: PhraseBoundary] = [:]
        let dialogueWords = configuration.detectsDialogue
            ? Self.dialogueWordIndices(in: words)
            : []

        for range in ranges {
            let sentenceWords = Array(words[range])
            let sentenceLexemes = Array(lexicalWords[range])
            let intent = configuration.detectsIntent
                ? Self.intent(words: sentenceWords, lexemes: sentenceLexemes)
                : .statement
            let emotionResult = configuration.detectsEmotion
                ? Self.emotion(in: sentenceLexemes, intent: intent)
                : (emotion: ContextualEmotion.neutral, confidence: 0.5)
            let isDialogue = range.contains(where: { dialogueWords.contains($0) })

            utterances.append(PlannedUtterance(
                startWordIndex: range.lowerBound,
                endWordIndex: range.upperBound - 1,
                intent: intent,
                emotion: emotionResult.emotion,
                isDialogue: isDialogue,
                confidence: emotionResult.confidence))
            boundaries[range.upperBound - 1] = .major

            if configuration.detectsClauseBoundaries {
                Self.addClauseBoundaries(
                    words: words,
                    lexemes: lexicalWords,
                    range: range,
                    to: &boundaries)
            }

            if configuration.detectsEmphasis {
                Self.addEmphasisCues(
                    words: words,
                    lexemes: lexicalWords,
                    range: range,
                    dialogueWords: dialogueWords,
                    to: &cues)
            } else if isDialogue {
                for index in range where dialogueWords.contains(index) {
                    cues[index] = WordSpeechCue(wordIndex: index, isDialogue: true)
                }
            }
        }

        return ContextualSpeechPlan(
            utterances: utterances,
            wordCues: cues,
            inferredBoundaries: boundaries)
    }

    private static func sentenceRanges(in words: [String]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        for index in words.indices where endsSentence(words[index]) {
            ranges.append(start..<(index + 1))
            start = index + 1
        }
        if start < words.count { ranges.append(start..<words.count) }
        return ranges.isEmpty ? [0..<words.count] : ranges
    }

    private static func endsSentence(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(
            in: CharacterSet(charactersIn: "\"'”’)]}"))
        return trimmed.last.map { ".!?".contains($0) } ?? false
    }

    private static func lexicalForm(_ word: String) -> String {
        let lexicalCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "'"))
        return word.lowercased().trimmingCharacters(in: lexicalCharacters.inverted)
    }

    private static func intent(
        words: [String], lexemes: [String]
    ) -> UtteranceIntent {
        let joined = words.joined(separator: " ")
        if joined.contains("?") { return .question }
        if joined.contains("!") { return .exclamation }

        let first = lexemes.first(where: { !$0.isEmpty }) ?? ""
        let second = lexemes.dropFirst().first(where: { !$0.isEmpty }) ?? ""
        if commandStarters.contains(first)
            || (first == "please" && commandStarters.contains(second)) {
            return .command
        }
        if joined.contains(".") { return .statement }
        if questionStarters.contains(first) { return .question }
        return .fragment
    }

    private static func emotion(
        in lexemes: [String], intent: UtteranceIntent
    ) -> (emotion: ContextualEmotion, confidence: Double) {
        var scores: [ContextualEmotion: Double] = [:]
        var previous = ""
        for lexeme in lexemes where !lexeme.isEmpty {
            let multiplier = intensifiers.contains(previous) ? 1.6 : 1
            for (emotion, vocabulary) in emotionVocabulary where vocabulary.contains(lexeme) {
                scores[emotion, default: 0] += multiplier
            }
            previous = lexeme
        }

        if intent == .exclamation, scores[.angry, default: 0] == 0 {
            scores[.joyful, default: 0] += 0.35
        }
        guard let strongest = scores.max(by: { lhs, rhs in
            lhs.value == rhs.value
                ? lhs.key.rawValue > rhs.key.rawValue
                : lhs.value < rhs.value
        }), strongest.value >= 1 else {
            return (.neutral, 0.55)
        }
        let evidence = scores.values.reduce(0, +)
        let dominance = strongest.value / max(1, evidence)
        let confidence = min(0.95, 0.55 + strongest.value * 0.12 + dominance * 0.18)
        return (strongest.key, confidence)
    }

    private static func dialogueWordIndices(in words: [String]) -> Set<Int> {
        var insideDialogue = false
        var result: Set<Int> = []
        for index in words.indices {
            let quoteCount = words[index].reduce(into: 0) { count, character in
                if "\"“”".contains(character) { count += 1 }
            }
            if insideDialogue || quoteCount > 0 { result.insert(index) }
            if quoteCount % 2 == 1 { insideDialogue.toggle() }
        }
        return result
    }

    private static func addClauseBoundaries(
        words: [String],
        lexemes: [String],
        range: Range<Int>,
        to boundaries: inout [Int: PhraseBoundary]
    ) {
        guard !range.isEmpty else { return }
        for index in range.dropLast() {
            let word = words[index]
            if word.contains(",") || word.contains(";") || word.contains(":")
                || word.contains("—") || word.contains("–") {
                boundaries[index] = max(boundaries[index] ?? .minor, .minor)
                continue
            }
            let next = index + 1
            if next < range.upperBound, discourseTransitions.contains(lexemes[next]) {
                boundaries[index] = max(boundaries[index] ?? .minor, .minor)
            }
        }
    }

    private static func addEmphasisCues(
        words: [String],
        lexemes: [String],
        range: Range<Int>,
        dialogueWords: Set<Int>,
        to cues: inout [Int: WordSpeechCue]
    ) {
        guard !range.isEmpty else { return }
        var requested: [Int: ContextualEmphasis] = [:]

        for index in range {
            let lexeme = lexemes[index]
            if contrastMarkers.contains(lexeme) {
                requested[index] = max(requested[index] ?? .none, .moderate)
                if let focus = nextContentWord(after: index, in: range, lexemes: lexemes) {
                    requested[focus] = max(requested[focus] ?? .none, .strong)
                }
            } else if intensifiers.contains(lexeme),
                      let focus = nextContentWord(after: index, in: range, lexemes: lexemes) {
                requested[focus] = max(requested[focus] ?? .none, .strong)
            }
        }

        // A sentence's final content word normally carries nuclear stress.
        if let finalFocus = range.reversed().first(where: {
            isContentWord(lexemes[$0])
        }) {
            requested[finalFocus] = max(requested[finalFocus] ?? .none, .moderate)
        }

        let allIndices = Set(requested.keys).union(
            dialogueWords.filter { range.contains($0) })
        for index in allIndices {
            let emphasis = requested[index] ?? .none
            let pitch: Double = emphasis == .strong ? 1.25 : emphasis == .moderate ? 0.55 : 0
            let duration: Double = emphasis == .strong ? 1.12 : emphasis == .moderate ? 1.06 : 1
            let energy: Double = emphasis == .strong ? 1.8 : emphasis == .moderate ? 0.8 : 0
            cues[index] = WordSpeechCue(
                wordIndex: index,
                emphasis: emphasis,
                isDialogue: dialogueWords.contains(index),
                pitchOffsetSemitones: pitch,
                durationScale: duration,
                energyDeltaDB: energy)
        }
    }

    private static func nextContentWord(
        after index: Int,
        in range: Range<Int>,
        lexemes: [String]
    ) -> Int? {
        guard index + 1 < range.upperBound else { return nil }
        return (index + 1..<range.upperBound).first { isContentWord(lexemes[$0]) }
    }

    private static func isContentWord(_ lexeme: String) -> Bool {
        !lexeme.isEmpty && !functionWords.contains(lexeme)
    }

    private static let questionStarters: Set<String> = [
        "who", "what", "when", "where", "why", "how", "which", "whose",
        "is", "are", "am", "was", "were", "do", "does", "did", "can",
        "could", "will", "would", "shall", "should", "has", "have", "had",
    ]

    private static let commandStarters: Set<String> = [
        "add", "answer", "ask", "be", "bring", "call", "choose", "close",
        "come", "continue", "do", "enter", "find", "give", "go", "help",
        "keep", "leave", "let", "listen", "look", "make", "open", "read",
        "remember", "return", "say", "send", "show", "speak", "stand",
        "stop", "take", "tell", "turn", "wait", "walk", "watch", "write",
    ]

    private static let intensifiers: Set<String> = [
        "absolutely", "deeply", "especially", "extremely", "really", "so",
        "truly", "utterly", "very",
    ]

    private static let contrastMarkers: Set<String> = [
        "actually", "but", "even", "however", "instead", "never", "not",
        "only", "rather", "yet",
    ]

    private static let discourseTransitions: Set<String> = [
        "although", "because", "but", "however", "instead", "meanwhile",
        "moreover", "nevertheless", "otherwise", "therefore", "though", "yet",
    ]

    private static let functionWords: Set<String> = [
        "a", "an", "and", "as", "at", "be", "been", "being", "by", "for",
        "from", "he", "her", "hers", "him", "his", "i", "in", "into", "is",
        "it", "its", "me", "my", "of", "on", "or", "our", "ours", "she",
        "that", "the", "their", "theirs", "them", "they", "this", "to", "us",
        "we", "with", "you", "your", "yours",
    ]

    private static let emotionVocabulary: [ContextualEmotion: Set<String>] = [
        .joyful: [
            "amazing", "beautiful", "celebrate", "delight", "glad", "happy",
            "hope", "joy", "joyful", "love", "rejoice", "thankful", "wonderful",
        ],
        .sad: [
            "alone", "cry", "despair", "grief", "grieve", "lonely", "loss",
            "mourn", "sad", "sorrow", "tears", "weep",
        ],
        .angry: [
            "anger", "angry", "betray", "fury", "hate", "rage", "rebuke",
            "wrath",
        ],
        .fearful: [
            "afraid", "anxious", "danger", "dread", "fear", "frightened",
            "panic", "terrified", "tremble", "worry",
        ],
        .tender: [
            "beloved", "care", "cherish", "comfort", "dear", "embrace",
            "gentle", "mercy", "peace", "tender",
        ],
        .solemn: [
            "amen", "covenant", "death", "eternal", "holy", "judgment",
            "oath", "sacred", "solemn", "truly",
        ],
    ]
}
