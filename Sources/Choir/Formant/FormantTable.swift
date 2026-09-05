import Foundation

/// How a phoneme is produced, which decides what the source generator does.
public enum FormantManner: String, Sendable, Equatable, Codable, CaseIterable {
    /// Vowels and diphthongs: fully voiced, formants clearly resolved.
    case vowel
    /// Nasals: voiced but heavily damped, with a low first formant.
    case nasal
    /// Approximants and glides, including the liquids /l/ and /r/.
    case approximant
    /// Voiced fricatives: voicing plus turbulence.
    case voicedFricative
    /// Voiceless fricatives: turbulence only.
    case fricative
    /// Voiced stops: a short voice bar, then a burst.
    case voicedStop
    /// Voiceless stops: silence, then a burst and aspiration.
    case stop
    /// Voiced affricates: stop closure, then voiced turbulence.
    case voicedAffricate
    /// Voiceless affricates: stop closure, then turbulence.
    case affricate
    /// Glottal /h/: aspiration shaped by the neighbouring vowel.
    case aspirate
    /// Silence, used for pauses and for the closure phase of a stop.
    case silence
}

/// One formant target: three resonances with their bandwidths.
///
/// Values are steady-state measurements for an adult male General American
/// speaker, which is the reference the whole table shares so that
/// ``VoiceProfile/formantScale`` can move every phoneme consistently.
public struct FormantTarget: Sendable, Equatable, Codable {
    public let f1: Double
    public let f2: Double
    public let f3: Double
    public let b1: Double
    public let b2: Double
    public let b3: Double

    public init(
        f1: Double, f2: Double, f3: Double,
        b1: Double = 60, b2: Double = 90, b3: Double = 150
    ) {
        self.f1 = f1
        self.f2 = f2
        self.f3 = f3
        self.b1 = b1
        self.b2 = b2
        self.b3 = b3
    }

    /// Linear interpolation between two targets, used for coarticulation and
    /// for the glide inside a diphthong.
    public func interpolated(towards other: FormantTarget, fraction: Double) -> FormantTarget {
        let t = min(1, max(0, fraction))
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return FormantTarget(
            f1: mix(f1, other.f1), f2: mix(f2, other.f2), f3: mix(f3, other.f3),
            b1: mix(b1, other.b1), b2: mix(b2, other.b2), b3: mix(b3, other.b3))
    }

    /// Scales the resonances by a vocal-tract length factor. Bandwidths are
    /// deliberately left alone: they track damping, not tract length.
    public func scaled(by factor: Double) -> FormantTarget {
        let safe = min(2.0, max(0.5, factor))
        return FormantTarget(
            f1: f1 * safe, f2: f2 * safe, f3: f3 * safe,
            b1: b1, b2: b2, b3: b3)
    }
}

/// The articulatory description of one phoneme.
public struct FormantDefinition: Sendable, Equatable {
    /// Formants held during the steady portion of the phoneme.
    public let target: FormantTarget

    /// Second target for diphthongs, which glide from `target` to this.
    public let glideTarget: FormantTarget?

    public let manner: FormantManner

    /// Centre frequency of the turbulence for fricatives, affricates and
    /// stop bursts, in Hz.
    public let noiseFrequency: Double

    /// Bandwidth of that turbulence, in Hz.
    public let noiseBandwidth: Double

    /// Relative loudness of the phoneme, 0...1.
    public let amplitude: Double

    public init(
        target: FormantTarget,
        glideTarget: FormantTarget? = nil,
        manner: FormantManner,
        noiseFrequency: Double = 0,
        noiseBandwidth: Double = 1_000,
        amplitude: Double = 1.0
    ) {
        self.target = target
        self.glideTarget = glideTarget
        self.manner = manner
        self.noiseFrequency = noiseFrequency
        self.noiseBandwidth = noiseBandwidth
        self.amplitude = amplitude
    }

    /// Whether the phoneme carries voicing for any part of its duration.
    public var isVoiced: Bool {
        switch manner {
        case .vowel, .nasal, .approximant, .voicedFricative, .voicedStop, .voicedAffricate:
            return true
        case .fricative, .stop, .affricate, .aspirate, .silence:
            return false
        }
    }

    /// Whether the phoneme begins with an oral closure, which is rendered as
    /// near-silence before the burst.
    public var hasClosure: Bool {
        switch manner {
        case .stop, .voicedStop, .affricate, .voicedAffricate:
            return true
        default:
            return false
        }
    }
}

/// Formant targets for every symbol in ``PhonemeInventory``.
///
/// The table is the acoustic knowledge that a trained model would otherwise
/// have to learn from recordings. Vowel values follow the classic Peterson and
/// Barney measurements of General American English; consonant values use the
/// standard locus and turbulence frequencies for each place of articulation.
/// The result is intelligible rather than natural, and is intended as the
/// data-free path that proves the pipeline end to end.
public enum FormantTable {

    /// Neutral vocal-tract position, used for silence and as the fallback for
    /// an unrecognized symbol.
    public static let neutral = FormantTarget(f1: 500, f2: 1_500, f3: 2_500)

    /// The definition for an IPA symbol of the inventory.
    public static func definition(for ipa: String) -> FormantDefinition? {
        definitions[ipa]
    }

    /// The definition for an encoded phoneme index, as produced by
    /// ``PhonemeEncoder``.
    public static func definition(forIndex index: Int) -> FormantDefinition? {
        guard index >= 0, index < PhonemeInventory.all.count else { return nil }
        return definitions[PhonemeInventory.all[index].ipa]
    }

    /// Silence, used for pauses and for the closure phase of a stop.
    public static let silence = FormantDefinition(
        target: neutral, manner: .silence, amplitude: 0)

    // MARK: - Vowels

    // Monophthong targets, also reused as the endpoints of the diphthongs.
    private static let iy = FormantTarget(f1: 270, f2: 2_290, f3: 3_010, b1: 55, b2: 100, b3: 160)
    private static let ih = FormantTarget(f1: 390, f2: 1_990, f3: 2_550, b1: 60, b2: 100, b3: 160)
    private static let eh = FormantTarget(f1: 530, f2: 1_840, f3: 2_480, b1: 70, b2: 100, b3: 160)
    private static let ae = FormantTarget(f1: 660, f2: 1_720, f3: 2_410, b1: 90, b2: 100, b3: 160)
    private static let aa = FormantTarget(f1: 730, f2: 1_090, f3: 2_440, b1: 90, b2: 90, b3: 160)
    private static let ao = FormantTarget(f1: 570, f2: 840, f3: 2_410, b1: 80, b2: 80, b3: 160)
    private static let uh = FormantTarget(f1: 440, f2: 1_020, f3: 2_240, b1: 70, b2: 80, b3: 160)
    private static let uw = FormantTarget(f1: 300, f2: 870, f3: 2_240, b1: 60, b2: 80, b3: 160)
    private static let ah = FormantTarget(f1: 640, f2: 1_190, f3: 2_390, b1: 80, b2: 90, b3: 160)
    private static let ax = FormantTarget(f1: 500, f2: 1_500, f3: 2_500, b1: 80, b2: 100, b3: 160)
    // The r-coloured vowel is defined by its very low third formant.
    private static let er = FormantTarget(f1: 490, f2: 1_350, f3: 1_690, b1: 70, b2: 100, b3: 140)

    private static let definitions: [String: FormantDefinition] = [
        // Monophthongs
        "iː": FormantDefinition(target: iy, manner: .vowel),
        "ɪ": FormantDefinition(target: ih, manner: .vowel),
        "ɛ": FormantDefinition(target: eh, manner: .vowel),
        "æ": FormantDefinition(target: ae, manner: .vowel),
        "ɑ": FormantDefinition(target: aa, manner: .vowel),
        "ɔ": FormantDefinition(target: ao, manner: .vowel),
        "ʊ": FormantDefinition(target: uh, manner: .vowel),
        "uː": FormantDefinition(target: uw, manner: .vowel),
        "ʌ": FormantDefinition(target: ah, manner: .vowel),
        "ə": FormantDefinition(target: ax, manner: .vowel, amplitude: 0.8),
        "ɝ": FormantDefinition(target: er, manner: .vowel),

        // Diphthongs glide from the first target to the second.
        "aʊ": FormantDefinition(target: aa, glideTarget: uh, manner: .vowel),
        "aɪ": FormantDefinition(target: aa, glideTarget: ih, manner: .vowel),
        "eɪ": FormantDefinition(target: eh, glideTarget: ih, manner: .vowel),
        "oʊ": FormantDefinition(target: ao, glideTarget: uh, manner: .vowel),
        "ɔɪ": FormantDefinition(target: ao, glideTarget: ih, manner: .vowel),

        // MARK: Nasals
        // Low, heavily damped first formant plus a place-dependent murmur.
        "m": FormantDefinition(
            target: FormantTarget(f1: 250, f2: 1_000, f3: 2_200, b1: 120, b2: 200, b3: 250),
            manner: .nasal, amplitude: 0.75),
        "n": FormantDefinition(
            target: FormantTarget(f1: 250, f2: 1_600, f3: 2_600, b1: 120, b2: 200, b3: 250),
            manner: .nasal, amplitude: 0.75),
        "ŋ": FormantDefinition(
            target: FormantTarget(f1: 250, f2: 2_000, f3: 2_500, b1: 120, b2: 200, b3: 250),
            manner: .nasal, amplitude: 0.75),

        // MARK: Approximants
        // /r/ shares the low third formant of the r-coloured vowel; that dip
        // is what separates it from /l/.
        "l": FormantDefinition(
            target: FormantTarget(f1: 350, f2: 1_100, f3: 2_600, b1: 80, b2: 100, b3: 200),
            manner: .approximant, amplitude: 0.75),
        "r": FormantDefinition(
            target: FormantTarget(f1: 350, f2: 1_100, f3: 1_600, b1: 80, b2: 100, b3: 160),
            manner: .approximant, amplitude: 0.75),
        "w": FormantDefinition(
            target: FormantTarget(f1: 300, f2: 800, f3: 2_200, b1: 70, b2: 90, b3: 160),
            manner: .approximant, amplitude: 0.7),
        "j": FormantDefinition(
            target: FormantTarget(f1: 280, f2: 2_200, f3: 3_000, b1: 70, b2: 100, b3: 160),
            manner: .approximant, amplitude: 0.7),

        // MARK: Fricatives
        // Sibilants carry most of their energy well above the third formant,
        // so the turbulence centre matters more than the formant target.
        "f": FormantDefinition(
            target: FormantTarget(f1: 400, f2: 1_100, f3: 2_200),
            manner: .fricative, noiseFrequency: 4_500, noiseBandwidth: 3_000, amplitude: 0.25),
        "v": FormantDefinition(
            target: FormantTarget(f1: 350, f2: 1_100, f3: 2_200),
            manner: .voicedFricative, noiseFrequency: 4_500, noiseBandwidth: 3_000,
            amplitude: 0.3),
        "θ": FormantDefinition(
            target: FormantTarget(f1: 400, f2: 1_400, f3: 2_400),
            manner: .fricative, noiseFrequency: 5_500, noiseBandwidth: 3_500, amplitude: 0.22),
        "ð": FormantDefinition(
            target: FormantTarget(f1: 350, f2: 1_400, f3: 2_400),
            manner: .voicedFricative, noiseFrequency: 5_500, noiseBandwidth: 3_500,
            amplitude: 0.3),
        "s": FormantDefinition(
            target: FormantTarget(f1: 320, f2: 1_400, f3: 2_500),
            manner: .fricative, noiseFrequency: 6_000, noiseBandwidth: 1_800, amplitude: 0.5),
        "z": FormantDefinition(
            target: FormantTarget(f1: 300, f2: 1_400, f3: 2_500),
            manner: .voicedFricative, noiseFrequency: 6_000, noiseBandwidth: 1_800,
            amplitude: 0.45),
        "ʃ": FormantDefinition(
            target: FormantTarget(f1: 350, f2: 1_800, f3: 2_600),
            manner: .fricative, noiseFrequency: 3_000, noiseBandwidth: 1_400, amplitude: 0.85),
        "ʒ": FormantDefinition(
            target: FormantTarget(f1: 330, f2: 1_800, f3: 2_600),
            manner: .voicedFricative, noiseFrequency: 3_000, noiseBandwidth: 1_400,
            amplitude: 0.75),
        // /h/ is aspiration through whatever vowel follows; the neutral target
        // here is replaced by the coarticulation pass.
        "h": FormantDefinition(
            target: neutral,
            manner: .aspirate, noiseFrequency: 1_500, noiseBandwidth: 2_500, amplitude: 0.18),

        // MARK: Stops
        // The target is the formant locus the neighbouring vowel bends toward,
        // which is the main cue to place of articulation.
        "p": FormantDefinition(
            target: FormantTarget(f1: 300, f2: 1_000, f3: 2_300),
            manner: .stop, noiseFrequency: 1_200, noiseBandwidth: 1_500, amplitude: 0.7),
        "b": FormantDefinition(
            target: FormantTarget(f1: 300, f2: 1_000, f3: 2_300),
            manner: .voicedStop, noiseFrequency: 1_200, noiseBandwidth: 1_500, amplitude: 0.7),
        "t": FormantDefinition(
            target: FormantTarget(f1: 300, f2: 1_700, f3: 2_600),
            manner: .stop, noiseFrequency: 4_000, noiseBandwidth: 2_000, amplitude: 0.8),
        "d": FormantDefinition(
            target: FormantTarget(f1: 300, f2: 1_700, f3: 2_600),
            manner: .voicedStop, noiseFrequency: 4_000, noiseBandwidth: 2_000, amplitude: 0.8),
        "k": FormantDefinition(
            target: FormantTarget(f1: 300, f2: 1_800, f3: 2_400),
            manner: .stop, noiseFrequency: 2_200, noiseBandwidth: 1_200, amplitude: 0.8),
        "ɡ": FormantDefinition(
            target: FormantTarget(f1: 300, f2: 1_800, f3: 2_400),
            manner: .voicedStop, noiseFrequency: 2_200, noiseBandwidth: 1_200, amplitude: 0.8),

        // MARK: Affricates
        "tʃ": FormantDefinition(
            target: FormantTarget(f1: 350, f2: 1_800, f3: 2_600),
            manner: .affricate, noiseFrequency: 3_000, noiseBandwidth: 1_400, amplitude: 0.85),
        "dʒ": FormantDefinition(
            target: FormantTarget(f1: 330, f2: 1_800, f3: 2_600),
            manner: .voicedAffricate, noiseFrequency: 3_000, noiseBandwidth: 1_400,
            amplitude: 0.45),
    ]
}
