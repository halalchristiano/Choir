import Foundation

/// The standard intelligibility corpus (SRS QUA-004).
///
/// QUA-004 measures "word-level transcription accuracy ≥ 98% when standard
/// Harvard sentences synthesized by each voice (default parameters) are
/// transcribed by an independent ASR system".
///
/// These are the IEEE Harvard sentences: phonetically balanced lists of ten,
/// each sentence carrying a comparable distribution of English phonemes. They
/// are the standard corpus for speech intelligibility measurement precisely
/// because they are boring — no sentence gives a listener context that would
/// let them guess a word they did not actually hear.
public enum HarvardSentences {

    /// IEEE list 1.
    public static let list1 = [
        "The birch canoe slid on the smooth planks.",
        "Glue the sheet to the dark blue background.",
        "It's easy to tell the depth of a well.",
        "These days a chicken leg is a rare dish.",
        "Rice is often served in round bowls.",
        "The juice of lemons makes fine punch.",
        "The box was thrown beside the parked truck.",
        "The hogs were fed chopped corn and garbage.",
        "Four hours of steady work faced us.",
        "A large size in stockings is hard to sell.",
    ]

    /// IEEE list 2.
    public static let list2 = [
        "The boy was there when the sun rose.",
        "A rod is used to catch pink salmon.",
        "The source of the huge river is the clear spring.",
        "Kick the ball straight and follow through.",
        "Help the woman get back to her feet.",
        "A pot of tea helps to pass the evening.",
        "Smoky fires lack flame and heat.",
        "The soft cushion broke the man's fall.",
        "The salt breeze came across from the sea.",
        "The girl at the booth sold fifty bonds.",
    ]

    /// The corpus used by default: twenty sentences across two lists.
    public static let standard = list1 + list2

    /// The canonical lists in their published, one-based order.
    public static let lists = [list1, list2]

    /// Returns a published list by its one-based list number.
    public static func list(number: Int) -> [String]? {
        guard number > 0, number <= lists.count else { return nil }
        return lists[number - 1]
    }

    /// Selects a bounded, reproducible, list-balanced subset of the corpus.
    ///
    /// Each list is shuffled by the local fixed algorithm and then sampled in
    /// round-robin order. The result therefore does not depend on Swift's
    /// randomized hashing or on the random-number implementation of a host OS.
    public static func deterministicSelection(
        count: Int,
        seed: UInt64 = 0
    ) -> [String] {
        guard count > 0 else { return [] }
        let requestedCount = min(count, standard.count)
        let shuffledLists = lists.enumerated().map { index, list in
            stableShuffle(list, seed: seed &+ UInt64(index))
        }
        guard !shuffledLists.isEmpty else { return [] }

        let startingList = Int(seed % UInt64(shuffledLists.count))
        return (0..<requestedCount).map { offset in
            let listIndex = (startingList + offset) % shuffledLists.count
            let position = offset / shuffledLists.count
            return shuffledLists[listIndex][position]
        }
    }

    /// Total reference words in the standard corpus.
    public static var standardWordCount: Int {
        standard.reduce(0) { $0 + TranscriptionScoring.normalizedWords($1).count }
    }

    private static func stableShuffle(_ values: [String], seed: UInt64) -> [String] {
        guard values.count > 1 else { return values }
        var result = values
        var state = seed
        for upperBound in stride(from: result.count - 1, through: 1, by: -1) {
            let index = Int(nextRandom(&state) % UInt64(upperBound + 1))
            result.swapAt(upperBound, index)
        }
        return result
    }

    /// SplitMix64, embedded so corpus selection is stable across platforms.
    private static func nextRandom(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
