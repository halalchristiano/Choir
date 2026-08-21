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

    /// Total reference words in the standard corpus.
    public static var standardWordCount: Int {
        standard.reduce(0) { $0 + TranscriptionScoring.normalizedWords($1).count }
    }
}
