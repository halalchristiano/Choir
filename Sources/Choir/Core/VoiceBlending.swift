import Foundation

/// Voice interpolation and blending between different voice profiles.
public struct VoiceBlending: Sendable {
    /// A voice with its synthesis parameters.
    public struct VoiceProfile: Sendable {
        public let voice: Voice
        public let parameters: SynthesisParameters

        public init(voice: Voice, parameters: SynthesisParameters = SynthesisParameters()) {
            self.voice = voice
            self.parameters = parameters
        }
    }

    public init() {}

    /// Blends two voices by interpolating their parameters.
    ///
    /// - Parameters:
    ///   - profile1: First voice and its parameters.
    ///   - profile2: Second voice and its parameters.
    ///   - mix: Blend factor (0.0 = fully profile1, 1.0 = fully profile2).
    /// - Returns: Blended synthesis parameters.
    public func blend(
        _ profile1: VoiceProfile,
        with profile2: VoiceProfile,
        mix: Double
    ) -> SynthesisParameters {
        let m = max(0, min(1.0, mix))  // Clamp to [0, 1]

        let blended = SynthesisParameters(
            pitchShift: interpolate(profile1.parameters.pitchShift, profile2.parameters.pitchShift, mix: m),
            rate: interpolate(profile1.parameters.rate, profile2.parameters.rate, mix: m),
            emotionalIntensity: interpolate(profile1.parameters.emotionalIntensity, profile2.parameters.emotionalIntensity, mix: m),
            breathiness: interpolate(profile1.parameters.breathiness, profile2.parameters.breathiness, mix: m),
            ageShift: interpolate(profile1.parameters.ageShift, profile2.parameters.ageShift, mix: m),
            genderShift: interpolate(profile1.parameters.genderShift, profile2.parameters.genderShift, mix: m)
        )

        return blended
    }

    /// Interpolates between two values.
    private func interpolate(_ a: Double, _ b: Double, mix: Double) -> Double {
        a * (1.0 - mix) + b * mix
    }

    /// Creates a smooth gender transition (e.g., masculine to feminine).
    public func genderTransition(
        from: Voice,
        to: Voice,
        steps: Int = 5
    ) -> [SynthesisParameters] {
        var transitions: [SynthesisParameters] = []

        for step in 0...steps {
            let mix = Double(step) / Double(steps)
            let genderShift = -1.0 + mix * 2.0  // -1 (feminine) to +1 (masculine)

            let params = SynthesisParameters(genderShift: genderShift)
            transitions.append(params)
        }

        return transitions
    }

    /// Creates an age transition (e.g., young to old).
    public func ageTransition(
        from: Voice,
        to: Voice,
        steps: Int = 5
    ) -> [SynthesisParameters] {
        var transitions: [SynthesisParameters] = []

        let fromAge = from.ageBand.ordinal
        let toAge = to.ageBand.ordinal

        for step in 0...steps {
            let mix = Double(step) / Double(steps)
            let ageShift = Double(fromAge) + mix * Double(toAge - fromAge)

            let params = SynthesisParameters(ageShift: ageShift)
            transitions.append(params)
        }

        return transitions
    }
}

/// Speaking style presets with predefined parameter combinations.
public struct SpeakingStyle: Sendable {
    /// Style identifier and display name.
    public let id: String
    public let name: String

    /// Synthesis parameters for this style.
    public let parameters: SynthesisParameters

    /// Description of the style.
    public let description: String

    public init(
        id: String,
        name: String,
        parameters: SynthesisParameters,
        description: String = ""
    ) {
        self.id = id
        self.name = name
        self.parameters = parameters
        self.description = description
    }

    // MARK: - Predefined Styles

    /// Normal, natural speaking.
    public static let normal = SpeakingStyle(
        id: "normal",
        name: "Normal",
        parameters: SynthesisParameters(
            pitchShift: 0,
            rate: 1.0,
            emotionalIntensity: 0.5
        ),
        description: "Natural, neutral speaking voice"
    )

    /// Fast, energetic speaking.
    public static let fast = SpeakingStyle(
        id: "fast",
        name: "Fast",
        parameters: SynthesisParameters(
            pitchShift: 3,
            rate: 1.4,
            emotionalIntensity: 0.7
        ),
        description: "Fast-paced, energetic delivery"
    )

    /// Slow, deliberate speaking.
    public static let slow = SpeakingStyle(
        id: "slow",
        name: "Slow",
        parameters: SynthesisParameters(
            pitchShift: -2,
            rate: 0.7,
            emotionalIntensity: 0.3
        ),
        description: "Slow, careful, measured speech"
    )

    /// Whispered, intimate tone.
    public static let whisper = SpeakingStyle(
        id: "whisper",
        name: "Whisper",
        parameters: SynthesisParameters(
            pitchShift: -5,
            rate: 0.9,
            emotionalIntensity: 0.2,
            breathiness: 0.8
        ),
        description: "Soft, whispered voice"
    )

    /// Loud, emphatic speaking.
    public static let shout = SpeakingStyle(
        id: "shout",
        name: "Shout",
        parameters: SynthesisParameters(
            pitchShift: 5,
            rate: 1.2,
            emotionalIntensity: 1.0
        ),
        description: "Loud, forceful delivery"
    )

    /// Cheerful, enthusiastic.
    public static let happy = SpeakingStyle(
        id: "happy",
        name: "Happy",
        parameters: SynthesisParameters(
            pitchShift: 4,
            rate: 1.1,
            emotionalIntensity: 0.9
        ),
        description: "Cheerful, upbeat tone"
    )

    /// Sad, melancholic.
    public static let sad = SpeakingStyle(
        id: "sad",
        name: "Sad",
        parameters: SynthesisParameters(
            pitchShift: -3,
            rate: 0.85,
            emotionalIntensity: 0.4,
            breathiness: 0.2
        ),
        description: "Sad, sorrowful delivery"
    )

    /// Angry, aggressive.
    public static let angry = SpeakingStyle(
        id: "angry",
        name: "Angry",
        parameters: SynthesisParameters(
            pitchShift: 6,
            rate: 1.3,
            emotionalIntensity: 1.0,
            breathiness: 0.1
        ),
        description: "Angry, aggressive tone"
    )

    /// Calm, soothing.
    public static let calm = SpeakingStyle(
        id: "calm",
        name: "Calm",
        parameters: SynthesisParameters(
            pitchShift: -1,
            rate: 0.85,
            emotionalIntensity: 0.3,
            breathiness: 0.3
        ),
        description: "Calm, soothing, relaxing speech"
    )

    /// All predefined styles.
    public static let allStyles: [SpeakingStyle] = [
        .normal, .fast, .slow, .whisper, .shout,
        .happy, .sad, .angry, .calm
    ]
}
