import Foundation

/// Age band of a voice, per SRS VOX-G-001.
public enum AgeBand: String, Sendable, CaseIterable, Codable {
    case child
    case youngAdult
    case middleAged
    case elderly

    /// Position of the band on the age axis, 1 (child) through 4 (elderly).
    ///
    /// Used where age must be interpolated numerically, such as the
    /// `ageShift` modifier of VOX-P-007.
    public var ordinal: Int {
        switch self {
        case .child: return 1
        case .youngAdult: return 2
        case .middleAged: return 3
        case .elderly: return 4
        }
    }
}

/// Gender presentation of a voice, per SRS VOX-G-001.
///
/// The specification defines exactly two presentations. Per VOX-P-006 the
/// distinction is realized through the joint setting of F0 range and formant
/// scale, never through F0 alone.
public enum GenderPresentation: String, Sendable, CaseIterable, Codable {
    case male
    case female
}

/// Recommended-use tag, per SRS VOX-G-004.
public enum VoiceUseTag: String, Sendable, CaseIterable, Codable {
    case narration
    case dialogue
    case ui
    case games
    case antagonist
}

/// The immutable design parameters of a voice.
///
/// Implements the parameter set required by SRS VOX-P-001 together with the
/// metadata required by VOX-G-004. Values come from the binding per-voice
/// profiles in SRS section 8 (`VOX-08-01` through `VOX-08-32`).
public struct VoiceProfile: Sendable, Equatable, Codable {
    // MARK: Identity (VOX-G-004)

    /// Stable identifier, e.g. `"choir.eld.male.villain.grimshaw"`.
    ///
    /// Permanent across versions per VOX-G-005.
    public let identifier: String

    /// Working name of the voice, e.g. `"GRIMSHAW"`.
    public let displayName: String

    public let ageBand: AgeBand
    public let gender: GenderPresentation

    /// Whether this voice is the villain archetype of its cell (VOX-V-001).
    public let isVillain: Bool

    /// One-line character description from the profile's `Character` row.
    public let characterDescription: String

    /// Recommended-use tags from the profile's `Recommended use` row.
    public let recommendedUse: [VoiceUseTag]

    // MARK: Acoustic design parameters (VOX-P-001)

    /// Median fundamental frequency in Hz.
    public let medianF0: Double

    /// Documented F0 envelope in Hz.
    public let f0Range: ClosedRange<Double>

    /// Formant scale factor, a vocal-tract-length proxy. 1.0 is the young
    /// adult male reference.
    public let formantScale: Double

    /// Spectral tilt in dB/octave; higher (less negative) is brighter.
    ///
    /// Section 8 specifies tilt qualitatively. The numeric mapping is a
    /// developer decision under SRS section 1.1; ``spectralTiltDescription``
    /// preserves the specified wording.
    public let spectralTilt: Double

    /// The tilt descriptor exactly as written in the voice's profile.
    public let spectralTiltDescription: String

    /// Breathiness index, 0...1.
    public let breathiness: Double

    /// Roughness/rasp index, 0...1.
    public let roughness: Double

    /// Base tempo in syllables per second.
    public let tempo: Double

    /// Pitch dynamism: standard deviation of the intonation contour, in
    /// semitones.
    public let pitchDynamism: Double
}

/// The 32 voices of the CHOIR library.
///
/// Organized per SRS VOX-G-001 as 4 age bands x 2 gender presentations x 4
/// voices per cell, exactly one of which is a villain archetype (VOX-V-001).
///
/// The raw value of each case is its stable identifier from SRS section 8, and
/// is permanent across versions per VOX-G-005.
public enum Voice: String, Sendable, CaseIterable, Codable {
    case finch = "choir.child.male.finch"
    case scout = "choir.child.male.scout"
    case alder = "choir.child.male.alder"
    case wick = "choir.child.male.villain.wick"
    case wren = "choir.child.female.wren"
    case juniper = "choir.child.female.juniper"
    case clover = "choir.child.female.clover"
    case briar = "choir.child.female.villain.briar"
    case orion = "choir.ya.male.orion"
    case flint = "choir.ya.male.flint"
    case reed = "choir.ya.male.reed"
    case corvin = "choir.ya.male.villain.corvin"
    case lyra = "choir.ya.female.lyra"
    case isla = "choir.ya.female.isla"
    case nova = "choir.ya.female.nova"
    case sable = "choir.ya.female.villain.sable"
    case garrick = "choir.mid.male.garrick"
    case hale = "choir.mid.male.hale"
    case bram = "choir.mid.male.bram"
    case malvern = "choir.mid.male.villain.malvern"
    case marion = "choir.mid.female.marion"
    case tamsin = "choir.mid.female.tamsin"
    case greer = "choir.mid.female.greer"
    case ravenna = "choir.mid.female.villain.ravenna"
    case alaric = "choir.eld.male.alaric"
    case wilfred = "choir.eld.male.wilfred"
    case cormac = "choir.eld.male.cormac"
    case grimshaw = "choir.eld.male.villain.grimshaw"
    case maeve = "choir.eld.female.maeve"
    case odette = "choir.eld.female.odette"
    case hattie = "choir.eld.female.hattie"
    case hespera = "choir.eld.female.villain.hespera"

    /// The immutable design profile for this voice (SRS section 8).
    public var profile: VoiceProfile {
        switch self {
        case .finch:
            return VoiceProfile(
                identifier: "choir.child.male.finch",
                displayName: "FINCH",
                ageBand: .child,
                gender: .male,
                isVillain: false,
                characterDescription: "Eager question-asker; sunlit, quick, open-hearted. The default \"young hero's friend.\"",
                recommendedUse: [.games, .narration, .ui],
                medianF0: 250,
                f0Range: 200...340,
                formantScale: 1.22,
                spectralTilt: -7.0,
                spectralTiltDescription: "bright",
                breathiness: 0.15,
                roughness: 0.05,
                tempo: 4.8,
                pitchDynamism: 3.5
            )
        case .scout:
            return VoiceProfile(
                identifier: "choir.child.male.scout",
                displayName: "SCOUT",
                ageBand: .child,
                gender: .male,
                isVillain: false,
                characterDescription: "10-12-year-old energy; capable, a little cocky, leader of the treehouse.",
                recommendedUse: [.games, .dialogue],
                medianF0: 225,
                f0Range: 180...300,
                formantScale: 1.16,
                spectralTilt: -7.5,
                spectralTiltDescription: "bright-neutral",
                breathiness: 0.1,
                roughness: 0.06,
                tempo: 5.0,
                pitchDynamism: 3.0
            )
        case .alder:
            return VoiceProfile(
                identifier: "choir.child.male.alder",
                displayName: "ALDER",
                ageBand: .child,
                gender: .male,
                isVillain: false,
                characterDescription: "The quiet, watchful child; old soul; speaks less, means more.",
                recommendedUse: [.dialogue, .narration],
                medianF0: 215,
                f0Range: 185...265,
                formantScale: 1.15,
                spectralTilt: -8.0,
                spectralTiltDescription: "neutral",
                breathiness: 0.2,
                roughness: 0.05,
                tempo: 4.0,
                pitchDynamism: 2.0
            )
        case .wick:
            return VoiceProfile(
                identifier: "choir.child.male.villain.wick",
                displayName: "WICK",
                ageBand: .child,
                gender: .male,
                isVillain: true,
                characterDescription: "Precocious menace; the smiling child who is three moves ahead. Unsettling through control, not growling.",
                recommendedUse: [.antagonist, .games],
                medianF0: 235,
                f0Range: 195...290,
                formantScale: 1.18,
                spectralTilt: -8.5,
                spectralTiltDescription: "neutral-dark for age",
                breathiness: 0.25,
                roughness: 0.08,
                tempo: 3.9,
                pitchDynamism: 1.8
            )
        case .wren:
            return VoiceProfile(
                identifier: "choir.child.female.wren",
                displayName: "WREN",
                ageBand: .child,
                gender: .female,
                isVillain: false,
                characterDescription: "Giggle-adjacent brightness; delight as a default state.",
                recommendedUse: [.games, .ui, .narration],
                medianF0: 275,
                f0Range: 225...370,
                formantScale: 1.24,
                spectralTilt: -6.0,
                spectralTiltDescription: "very bright",
                breathiness: 0.18,
                roughness: 0.04,
                tempo: 5.0,
                pitchDynamism: 3.8
            )
        case .juniper:
            return VoiceProfile(
                identifier: "choir.child.female.juniper",
                displayName: "JUNIPER",
                ageBand: .child,
                gender: .female,
                isVillain: false,
                characterDescription: "The child who narrates her own life; wonder with structure.",
                recommendedUse: [.narration, .dialogue],
                medianF0: 260,
                f0Range: 215...340,
                formantScale: 1.2,
                spectralTilt: -7.0,
                spectralTiltDescription: "bright",
                breathiness: 0.15,
                roughness: 0.05,
                tempo: 4.5,
                pitchDynamism: 3.2
            )
        case .clover:
            return VoiceProfile(
                identifier: "choir.child.female.clover",
                displayName: "CLOVER",
                ageBand: .child,
                gender: .female,
                isVillain: false,
                characterDescription: "Soft-spoken sweetness; the trusting youngest sibling.",
                recommendedUse: [.dialogue, .narration],
                medianF0: 265,
                f0Range: 225...330,
                formantScale: 1.22,
                spectralTilt: -7.5,
                spectralTiltDescription: "bright-soft",
                breathiness: 0.3,
                roughness: 0.03,
                tempo: 4.1,
                pitchDynamism: 2.6
            )
        case .briar:
            return VoiceProfile(
                identifier: "choir.child.female.villain.briar",
                displayName: "BRIAR",
                ageBand: .child,
                gender: .female,
                isVillain: true,
                characterDescription: "Porcelain-doll sweetness with something wrong underneath; manipulation wearing innocence.",
                recommendedUse: [.antagonist, .games],
                medianF0: 268,
                f0Range: 225...345,
                formantScale: 1.21,
                spectralTilt: -7.0,
                spectralTiltDescription: "bright with hollowed mids",
                breathiness: 0.35,
                roughness: 0.05,
                tempo: 3.8,
                pitchDynamism: 1.6
            )
        case .orion:
            return VoiceProfile(
                identifier: "choir.ya.male.orion",
                displayName: "ORION",
                ageBand: .youngAdult,
                gender: .male,
                isVillain: false,
                characterDescription: "Early-twenties idealist; open, earnest, easy to root for.",
                recommendedUse: [.dialogue, .narration, .games],
                medianF0: 120,
                f0Range: 85...190,
                formantScale: 1.0,
                spectralTilt: -8.5,
                spectralTiltDescription: "neutral-warm",
                breathiness: 0.15,
                roughness: 0.04,
                tempo: 4.7,
                pitchDynamism: 3.0
            )
        case .flint:
            return VoiceProfile(
                identifier: "choir.ya.male.flint",
                displayName: "FLINT",
                ageBand: .youngAdult,
                gender: .male,
                isVillain: false,
                characterDescription: "Late-twenties competence; steady hands, dry humour available.",
                recommendedUse: [.games, .narration, .dialogue],
                medianF0: 108,
                f0Range: 80...165,
                formantScale: 0.99,
                spectralTilt: -9.0,
                spectralTiltDescription: "neutral-dark",
                breathiness: 0.1,
                roughness: 0.07,
                tempo: 4.3,
                pitchDynamism: 2.4
            )
        case .reed:
            return VoiceProfile(
                identifier: "choir.ya.male.reed",
                displayName: "REED",
                ageBand: .youngAdult,
                gender: .male,
                isVillain: false,
                characterDescription: "Sensitive interiority; the poet, the grieving brother, the anxious friend.",
                recommendedUse: [.narration, .dialogue],
                medianF0: 125,
                f0Range: 95...180,
                formantScale: 1.01,
                spectralTilt: -9.5,
                spectralTiltDescription: "soft",
                breathiness: 0.35,
                roughness: 0.04,
                tempo: 3.9,
                pitchDynamism: 2.6
            )
        case .corvin:
            return VoiceProfile(
                identifier: "choir.ya.male.villain.corvin",
                displayName: "CORVIN",
                ageBand: .youngAdult,
                gender: .male,
                isVillain: true,
                characterDescription: "The charming young villain; velvet over wire; seduction as strategy.",
                recommendedUse: [.antagonist, .dialogue],
                medianF0: 105,
                f0Range: 78...160,
                formantScale: 0.98,
                spectralTilt: -10.0,
                spectralTiltDescription: "dark-smooth",
                breathiness: 0.28,
                roughness: 0.06,
                tempo: 3.7,
                pitchDynamism: 2.0
            )
        case .lyra:
            return VoiceProfile(
                identifier: "choir.ya.female.lyra",
                displayName: "LYRA",
                ageBand: .youngAdult,
                gender: .female,
                isVillain: false,
                characterDescription: "Bright drive; warmth plus will; the heroine who moves the plot.",
                recommendedUse: [.dialogue, .narration, .games],
                medianF0: 210,
                f0Range: 160...300,
                formantScale: 1.18,
                spectralTilt: -7.0,
                spectralTiltDescription: "bright",
                breathiness: 0.15,
                roughness: 0.04,
                tempo: 4.8,
                pitchDynamism: 3.4
            )
        case .isla:
            return VoiceProfile(
                identifier: "choir.ya.female.isla",
                displayName: "ISLA",
                ageBand: .youngAdult,
                gender: .female,
                isVillain: false,
                characterDescription: "Calm certainty; low-drama competence; trustworthy centre of gravity.",
                recommendedUse: [.narration, .dialogue],
                medianF0: 195,
                f0Range: 150...260,
                formantScale: 1.16,
                spectralTilt: -8.5,
                spectralTiltDescription: "neutral-warm",
                breathiness: 0.18,
                roughness: 0.04,
                tempo: 4.2,
                pitchDynamism: 2.4
            )
        case .nova:
            return VoiceProfile(
                identifier: "choir.ya.female.nova",
                displayName: "NOVA",
                ageBand: .youngAdult,
                gender: .female,
                isVillain: false,
                characterDescription: "Contained fire; conviction at the edge of eruption.",
                recommendedUse: [.dialogue, .games],
                medianF0: 205,
                f0Range: 155...290,
                formantScale: 1.17,
                spectralTilt: -6.5,
                spectralTiltDescription: "bright-hard",
                breathiness: 0.1,
                roughness: 0.08,
                tempo: 4.6,
                pitchDynamism: 3.6
            )
        case .sable:
            return VoiceProfile(
                identifier: "choir.ya.female.villain.sable",
                displayName: "SABLE",
                ageBand: .youngAdult,
                gender: .female,
                isVillain: true,
                characterDescription: "Intelligence as a weapon; beauty with the warmth removed; every word chosen.",
                recommendedUse: [.antagonist, .dialogue],
                medianF0: 188,
                f0Range: 145...250,
                formantScale: 1.14,
                spectralTilt: -9.5,
                spectralTiltDescription: "dark-glassy",
                breathiness: 0.22,
                roughness: 0.05,
                tempo: 3.8,
                pitchDynamism: 1.7
            )
        case .garrick:
            return VoiceProfile(
                identifier: "choir.mid.male.garrick",
                displayName: "GARRICK",
                ageBand: .middleAged,
                gender: .male,
                isVillain: false,
                characterDescription: "Command earned by experience; gravity without cruelty.",
                recommendedUse: [.narration, .dialogue, .games],
                medianF0: 100,
                f0Range: 72...150,
                formantScale: 0.98,
                spectralTilt: -10.0,
                spectralTiltDescription: "dark",
                breathiness: 0.1,
                roughness: 0.12,
                tempo: 4.0,
                pitchDynamism: 2.2
            )
        case .hale:
            return VoiceProfile(
                identifier: "choir.mid.male.hale",
                displayName: "HALE",
                ageBand: .middleAged,
                gender: .male,
                isVillain: false,
                characterDescription: "The teacher you remember; patience, humour, safety.",
                recommendedUse: [.narration, .dialogue],
                medianF0: 110,
                f0Range: 82...160,
                formantScale: 0.99,
                spectralTilt: -9.0,
                spectralTiltDescription: "warm",
                breathiness: 0.2,
                roughness: 0.08,
                tempo: 4.1,
                pitchDynamism: 2.6
            )
        case .bram:
            return VoiceProfile(
                identifier: "choir.mid.male.bram",
                displayName: "BRAM",
                ageBand: .middleAged,
                gender: .male,
                isVillain: false,
                characterDescription: "Noir tiredness; decency that has paid its costs.",
                recommendedUse: [.narration, .dialogue],
                medianF0: 96,
                f0Range: 70...140,
                formantScale: 0.98,
                spectralTilt: -10.0,
                spectralTiltDescription: "dark-dry",
                breathiness: 0.28,
                roughness: 0.16,
                tempo: 3.7,
                pitchDynamism: 2.0
            )
        case .malvern:
            return VoiceProfile(
                identifier: "choir.mid.male.villain.malvern",
                displayName: "MALVERN",
                ageBand: .middleAged,
                gender: .male,
                isVillain: true,
                characterDescription: "Institutional evil; the man who signs the order and sleeps well.",
                recommendedUse: [.antagonist, .games],
                medianF0: 94,
                f0Range: 68...135,
                formantScale: 0.97,
                spectralTilt: -9.0,
                spectralTiltDescription: "dark-metallic edge",
                breathiness: 0.12,
                roughness: 0.14,
                tempo: 3.6,
                pitchDynamism: 1.4
            )
        case .marion:
            return VoiceProfile(
                identifier: "choir.mid.female.marion",
                displayName: "MARION",
                ageBand: .middleAged,
                gender: .female,
                isVillain: false,
                characterDescription: "Grace with spine; the judge, the abbess, the matriarch in her prime.",
                recommendedUse: [.narration, .dialogue],
                medianF0: 185,
                f0Range: 140...245,
                formantScale: 1.14,
                spectralTilt: -9.5,
                spectralTiltDescription: "warm-dark",
                breathiness: 0.14,
                roughness: 0.07,
                tempo: 3.9,
                pitchDynamism: 2.3
            )
        case .tamsin:
            return VoiceProfile(
                identifier: "choir.mid.female.tamsin",
                displayName: "TAMSIN",
                ageBand: .middleAged,
                gender: .female,
                isVillain: false,
                characterDescription: "Crisp modern competence; broadcast-clean clarity.",
                recommendedUse: [.ui, .narration, .dialogue],
                medianF0: 192,
                f0Range: 150...250,
                formantScale: 1.15,
                spectralTilt: -7.5,
                spectralTiltDescription: "neutral-bright",
                breathiness: 0.1,
                roughness: 0.05,
                tempo: 4.4,
                pitchDynamism: 2.5
            )
        case .greer:
            return VoiceProfile(
                identifier: "choir.mid.female.greer",
                displayName: "GREER",
                ageBand: .middleAged,
                gender: .female,
                isVillain: false,
                characterDescription: "Sardonic survivor; wit with sandpaper edges.",
                recommendedUse: [.dialogue, .narration],
                medianF0: 172,
                f0Range: 130...225,
                formantScale: 1.12,
                spectralTilt: -10.0,
                spectralTiltDescription: "dark-dry",
                breathiness: 0.24,
                roughness: 0.15,
                tempo: 3.8,
                pitchDynamism: 2.0
            )
        case .ravenna:
            return VoiceProfile(
                identifier: "choir.mid.female.villain.ravenna",
                displayName: "RAVENNA",
                ageBand: .middleAged,
                gender: .female,
                isVillain: true,
                characterDescription: "Ambition with a crown in mind; contempt dressed as courtesy.",
                recommendedUse: [.antagonist, .dialogue],
                medianF0: 178,
                f0Range: 135...240,
                formantScale: 1.13,
                spectralTilt: -9.0,
                spectralTiltDescription: "dark with brilliant edge",
                breathiness: 0.15,
                roughness: 0.1,
                tempo: 3.7,
                pitchDynamism: 1.8
            )
        case .alaric:
            return VoiceProfile(
                identifier: "choir.eld.male.alaric",
                displayName: "ALARIC",
                ageBand: .elderly,
                gender: .male,
                isVillain: false,
                characterDescription: "The scholar-statesman; every sentence weighed and found exact.",
                recommendedUse: [.narration, .dialogue],
                medianF0: 112,
                f0Range: 85...160,
                formantScale: 0.985,
                spectralTilt: -10.5,
                spectralTiltDescription: "dark-mellow",
                breathiness: 0.22,
                roughness: 0.18,
                tempo: 3.5,
                pitchDynamism: 2.0
            )
        case .wilfred:
            return VoiceProfile(
                identifier: "choir.eld.male.wilfred",
                displayName: "WILFRED",
                ageBand: .elderly,
                gender: .male,
                isVillain: false,
                characterDescription: "Fireside kindness; stories, chuckles held in reserve, unconditional welcome.",
                recommendedUse: [.narration, .dialogue],
                medianF0: 118,
                f0Range: 90...165,
                formantScale: 0.99,
                spectralTilt: -9.5,
                spectralTiltDescription: "warm-soft",
                breathiness: 0.3,
                roughness: 0.2,
                tempo: 3.4,
                pitchDynamism: 2.4
            )
        case .cormac:
            return VoiceProfile(
                identifier: "choir.eld.male.cormac",
                displayName: "CORMAC",
                ageBand: .elderly,
                gender: .male,
                isVillain: false,
                characterDescription: "Age without dullness; the old man who still wins every argument.",
                recommendedUse: [.dialogue, .narration, .games],
                medianF0: 122,
                f0Range: 92...175,
                formantScale: 0.99,
                spectralTilt: -8.5,
                spectralTiltDescription: "neutral-dry",
                breathiness: 0.2,
                roughness: 0.17,
                tempo: 3.9,
                pitchDynamism: 2.8
            )
        case .grimshaw:
            return VoiceProfile(
                identifier: "choir.eld.male.villain.grimshaw",
                displayName: "GRIMSHAW",
                ageBand: .elderly,
                gender: .male,
                isVillain: true,
                characterDescription: "Accumulated darkness; a lifetime of cruelty distilled into patience.",
                recommendedUse: [.antagonist, .narration],
                medianF0: 98,
                f0Range: 70...140,
                formantScale: 0.98,
                spectralTilt: -11.0,
                spectralTiltDescription: "very dark, subharmonic body",
                breathiness: 0.25,
                roughness: 0.3,
                tempo: 3.1,
                pitchDynamism: 1.5
            )
        case .maeve:
            return VoiceProfile(
                identifier: "choir.eld.female.maeve",
                displayName: "MAEVE",
                ageBand: .elderly,
                gender: .female,
                isVillain: false,
                characterDescription: "Maternal wisdom; the blessing voice; tea, scripture, and certainty that you are loved.",
                recommendedUse: [.narration, .dialogue],
                medianF0: 175,
                f0Range: 135...225,
                formantScale: 1.11,
                spectralTilt: -9.5,
                spectralTiltDescription: "warm-soft",
                breathiness: 0.32,
                roughness: 0.15,
                tempo: 3.4,
                pitchDynamism: 2.3
            )
        case .odette:
            return VoiceProfile(
                identifier: "choir.eld.female.odette",
                displayName: "ODETTE",
                ageBand: .elderly,
                gender: .female,
                isVillain: false,
                characterDescription: "Stillness after the storm; contemplative depth; peace that was fought for.",
                recommendedUse: [.narration, .dialogue],
                medianF0: 168,
                f0Range: 130...210,
                formantScale: 1.1,
                spectralTilt: -9.5,
                spectralTiltDescription: "dark-luminous",
                breathiness: 0.28,
                roughness: 0.12,
                tempo: 3.2,
                pitchDynamism: 1.8
            )
        case .hattie:
            return VoiceProfile(
                identifier: "choir.eld.female.hattie",
                displayName: "HATTIE",
                ageBand: .elderly,
                gender: .female,
                isVillain: false,
                characterDescription: "Front-porch raconteur; mischief intact at eighty.",
                recommendedUse: [.narration, .dialogue, .games],
                medianF0: 180,
                f0Range: 138...240,
                formantScale: 1.12,
                spectralTilt: -7.5,
                spectralTiltDescription: "neutral-bright for band",
                breathiness: 0.24,
                roughness: 0.18,
                tempo: 3.8,
                pitchDynamism: 2.9
            )
        case .hespera:
            return VoiceProfile(
                identifier: "choir.eld.female.villain.hespera",
                displayName: "HESPERA",
                ageBand: .elderly,
                gender: .female,
                isVillain: true,
                characterDescription: "Malevolent experience; the witch at the end of every wrong road.",
                recommendedUse: [.antagonist, .narration],
                medianF0: 162,
                f0Range: 120...215,
                formantScale: 1.09,
                spectralTilt: -9.0,
                spectralTiltDescription: "dark with whistling top edge",
                breathiness: 0.35,
                roughness: 0.24,
                tempo: 3.2,
                pitchDynamism: 1.7
            )
        }
    }

    // MARK: Convenience accessors

    /// Stable identifier, e.g. `"choir.child.male.finch"` (VOX-G-004).
    public var identifier: String { profile.identifier }

    /// Working name of the voice, e.g. `"FINCH"`.
    public var displayName: String { profile.displayName }

    public var ageBand: AgeBand { profile.ageBand }
    public var gender: GenderPresentation { profile.gender }

    /// Whether this voice is the villain archetype of its cell.
    public var isVillain: Bool { profile.isVillain }

    /// All voices in a given (age band, gender) cell.
    ///
    /// Per VOX-G-001 this always yields exactly four voices, exactly one of
    /// which has ``isVillain`` set.
    public static func voices(ageBand: AgeBand, gender: GenderPresentation) -> [Voice] {
        allCases.filter { $0.ageBand == ageBand && $0.gender == gender }
    }

    /// The eight villain voices, one per cell (VOX-V-001).
    public static var villains: [Voice] {
        allCases.filter(\.isVillain)
    }

    /// Voices carrying a given recommended-use tag (VOX-G-004).
    public static func voices(for tag: VoiceUseTag) -> [Voice] {
        allCases.filter { $0.profile.recommendedUse.contains(tag) }
    }

    /// Looks up a voice by its stable identifier (VOX-G-005).
    public static func voice(withIdentifier identifier: String) -> Voice? {
        allCases.first { $0.identifier == identifier }
    }
}
