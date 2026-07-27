import Foundation

/// Represents one of the 32 available voices in the Choir library.
///
/// Voices are organized by age band and gender presentation, including six villain archetypes.
/// Each voice is an engineered synthetic instrument, not a clone of any real speaker.
public enum Voice: String, Sendable, CaseIterable {
    // Child voices (age band 1)
    case childNeutral1 = "child_neutral_1"
    case childNeutral2 = "child_neutral_2"
    case childMasculine = "child_masculine"
    case childFeminine = "child_feminine"

    // Young adult voices (age band 2)
    case youngAdultNeutral1 = "young_adult_neutral_1"
    case youngAdultNeutral2 = "young_adult_neutral_2"
    case youngAdultMasculine = "young_adult_masculine"
    case youngAdultFeminine = "young_adult_feminine"

    // Middle-aged voices (age band 3)
    case middleAgedNeutral1 = "middle_aged_neutral_1"
    case middleAgedNeutral2 = "middle_aged_neutral_2"
    case middleAgedMasculine = "middle_aged_masculine"
    case middleAgedFeminine = "middle_aged_feminine"

    // Elderly voices (age band 4)
    case elderlyNeutral1 = "elderly_neutral_1"
    case elderlyNeutral2 = "elderly_neutral_2"
    case elderlyMasculine = "elderly_masculine"
    case elderlyFeminine = "elderly_feminine"

    // Villain archetypes
    case villainMasculine1 = "villain_masculine_1"
    case villainMasculine2 = "villain_masculine_2"
    case villainFeminine1 = "villain_feminine_1"
    case villainFeminine2 = "villain_feminine_2"
    case villainNeutral1 = "villain_neutral_1"
    case villainNeutral2 = "villain_neutral_2"

    // Narrator voices
    case narratorMasculine = "narrator_masculine"
    case narratorFeminine = "narrator_feminine"

    // Teenager voices (between child and young adult)
    case teenageMasculine = "teenage_masculine"
    case teenageFeminine = "teenage_feminine"

    // Character/specialty voices for games and media
    case characterWitchyFeminine = "character_witchy_feminine"
    case characterGrufMasculine = "character_gruf_masculine"
    case characterMysticalNeutral = "character_mystical_neutral"
    case characterRobotNeutral = "character_robot_neutral"
    case characterMysteryMasculine = "character_mystery_masculine"

    // High-quality specialty voice
    case audiobook = "audiobook"

    /// A human-readable display name for this voice.
    public var displayName: String {
        let parts = self.rawValue.split(separator: "_").map { String($0) }
        return parts
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// The age band of this voice (1-4), or 0 for specialty voices.
    public var ageBand: Int {
        let ageBandMap: [Voice: Int] = [
            .childNeutral1: 1, .childNeutral2: 1, .childMasculine: 1, .childFeminine: 1,
            .youngAdultNeutral1: 2, .youngAdultNeutral2: 2, .youngAdultMasculine: 2, .youngAdultFeminine: 2,
            .middleAgedNeutral1: 3, .middleAgedNeutral2: 3, .middleAgedMasculine: 3, .middleAgedFeminine: 3,
            .elderlyNeutral1: 4, .elderlyNeutral2: 4, .elderlyMasculine: 4, .elderlyFeminine: 4,
            .villainMasculine1: 3, .villainMasculine2: 3, .villainFeminine1: 3, .villainFeminine2: 3, .villainNeutral1: 3, .villainNeutral2: 3,
            .narratorMasculine: 3, .narratorFeminine: 3,
            .teenageMasculine: 2, .teenageFeminine: 2,
            .characterWitchyFeminine: 0, .characterGrufMasculine: 0, .characterMysticalNeutral: 0, .characterRobotNeutral: 0, .characterMysteryMasculine: 0,
            .audiobook: 0
        ]
        return ageBandMap[self] ?? 0
    }

    /// Whether this is a villain voice archetype.
    public var isVillain: Bool {
        self.rawValue.hasPrefix("villain")
    }
}
