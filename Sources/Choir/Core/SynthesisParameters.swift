import Foundation

/// Parameters for controlling synthesis output, including prosody and expression.
public struct SynthesisParameters: Sendable, Equatable, Hashable, Codable {
    /// Pitch shift in semitones (-12 to +12). Default is 0.
    public var pitchShift: Double = 0

    /// Speech rate multiplier (0.5 to 2.0). Default is 1.0.
    public var rate: Double = 1.0

    /// Emotional intensity (0.0 to 1.0). Default is 0.5.
    public var emotionalIntensity: Double = 0.5

    /// Breathiness amount (0.0 to 1.0). Default is 0.0.
    public var breathiness: Double = 0.0

    /// Age shift: negative values sound younger, positive values sound older (-5 to +5). Default is 0.
    public var ageShift: Double = 0

    /// Gender shift: negative values shift feminine, positive values shift masculine (-1.0 to +1.0). Default is 0.
    public var genderShift: Double = 0

    /// Seed for reproducible synthesis (SRS SYN-002).
    ///
    /// With a seed, identical text, voice, parameters and package version
    /// produce bit-identical audio, which is what makes audiobook and video
    /// builds reproducible. Without one, controlled prosodic variation is
    /// applied so that a repeated line does not sound mechanically identical
    /// (SYN-003).
    public var seed: UInt64?

    public init(
        pitchShift: Double = 0,
        rate: Double = 1.0,
        emotionalIntensity: Double = 0.5,
        breathiness: Double = 0.0,
        ageShift: Double = 0,
        genderShift: Double = 0,
        seed: UInt64? = nil
    ) {
        self.seed = seed
        self.pitchShift = max(-12, min(12, pitchShift))
        self.rate = max(0.5, min(2.0, rate))
        self.emotionalIntensity = max(0, min(1.0, emotionalIntensity))
        self.breathiness = max(0, min(1.0, breathiness))
        self.ageShift = max(-5, min(5, ageShift))
        self.genderShift = max(-1.0, min(1.0, genderShift))

        self.clampings = Self.clampings(
            pitchShift: pitchShift, rate: rate,
            emotionalIntensity: emotionalIntensity, breathiness: breathiness,
            ageShift: ageShift, genderShift: genderShift)
    }

    // MARK: - Envelope clamping (API-004, PRO-030)

    /// One parameter that was clamped into its documented envelope.
    public struct Clamping: Sendable, Equatable, Hashable, Codable {
        public let parameter: String
        public let requested: Double
        public let applied: Double

        public var description: String {
            "\(parameter) \(requested) clamped to \(applied)"
        }
    }

    /// Parameters that were clamped when this value was constructed.
    ///
    /// API-004 requires validation that *reports* envelope clamping. Silently
    /// clamping is the failure mode this exists to prevent: a caller asking for
    /// a pitch shift of 24 semitones and receiving 12 with no indication will
    /// conclude the parameter does nothing.
    public let clampings: [Clamping]

    /// Whether any parameter was clamped.
    public var wasClamped: Bool { !clampings.isEmpty }

    private static func clampings(
        pitchShift: Double, rate: Double, emotionalIntensity: Double,
        breathiness: Double, ageShift: Double, genderShift: Double
    ) -> [Clamping] {
        var result: [Clamping] = []
        func check(_ name: String, _ requested: Double, _ low: Double, _ high: Double) {
            let applied = max(low, min(high, requested))
            if applied != requested {
                result.append(Clamping(parameter: name, requested: requested, applied: applied))
            }
        }
        check("pitchShift", pitchShift, -12, 12)
        check("rate", rate, 0.5, 2.0)
        check("emotionalIntensity", emotionalIntensity, 0, 1)
        check("breathiness", breathiness, 0, 1)
        check("ageShift", ageShift, -5, 5)
        check("genderShift", genderShift, -1, 1)
        return result
    }

    // MARK: - Builder-style modification (API-004)

    /// Returns a copy with `pitchShift` replaced.
    public func pitch(_ semitones: Double) -> SynthesisParameters {
        modified { $0.pitchShift = semitones }
    }

    /// Returns a copy with `rate` replaced.
    public func speed(_ multiplier: Double) -> SynthesisParameters {
        modified { $0.rate = multiplier }
    }

    /// Returns a copy with `emotionalIntensity` replaced.
    public func emotion(_ intensity: Double) -> SynthesisParameters {
        modified { $0.emotionalIntensity = intensity }
    }

    /// Returns a copy with `breathiness` replaced.
    public func breath(_ amount: Double) -> SynthesisParameters {
        modified { $0.breathiness = amount }
    }

    /// Returns a copy with `ageShift` replaced.
    public func age(_ shift: Double) -> SynthesisParameters {
        modified { $0.ageShift = shift }
    }

    /// Returns a copy with `genderShift` replaced.
    public func gender(_ shift: Double) -> SynthesisParameters {
        modified { $0.genderShift = shift }
    }

    /// Returns a copy with `seed` replaced (SYN-002).
    public func seeded(_ seed: UInt64?) -> SynthesisParameters {
        var copy = self
        copy.seed = seed
        return copy
    }

    /// Re-runs the initializer so clamping and its report stay correct.
    ///
    /// Mutating a stored property directly would leave `clampings` describing
    /// a value that no longer exists.
    private func modified(_ change: (inout SynthesisParameters) -> Void) -> SynthesisParameters {
        var draft = self
        change(&draft)
        var rebuilt = SynthesisParameters(
            pitchShift: draft.pitchShift,
            rate: draft.rate,
            emotionalIntensity: draft.emotionalIntensity,
            breathiness: draft.breathiness,
            ageShift: draft.ageShift,
            genderShift: draft.genderShift)
        rebuilt.seed = draft.seed
        return rebuilt
    }
}

/// Audio format specification for synthesis output.
public struct AudioFormat: Sendable {
    /// Sample rate in Hz. Default is 48000.
    public let sampleRate: Int

    /// Number of audio channels. Default is 1 (mono).
    public let channels: Int

    /// Bit depth. Default is 16 (PCM 16-bit).
    public let bitDepth: Int

    public init(sampleRate: Int = 48000, channels: Int = 1, bitDepth: Int = 16) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
    }

    /// Validates the PCM format supported by the current engine path.
    public func validate() throws {
        guard 8_000...384_000 ~= sampleRate else {
            throw ChoirError.invalidParameter(
                parameter: "sampleRate", reason: "Sample rate must be within 8,000...384,000 Hz")
        }
        guard 1...8 ~= channels else {
            throw ChoirError.invalidParameter(
                parameter: "channels", reason: "Channel count must be within 1...8")
        }
        guard bitDepth == 16 else {
            throw ChoirError.invalidParameter(
                parameter: "bitDepth", reason: "The current PCM path supports 16-bit samples")
        }
    }
}

/// Streaming options for real-time synthesis.
public struct StreamingOptions: Sendable {
    /// Target buffer size for streaming chunks in samples. Default is 2400 (50ms at 48kHz).
    public var chunkSize: Int = 2400

    /// Whether to preload the acoustic model. Default is true.
    public var preloadModel: Bool = true

    public init(chunkSize: Int = 2400, preloadModel: Bool = true) {
        self.chunkSize = chunkSize
        self.preloadModel = preloadModel
    }

    /// Validates options before a streaming request starts.
    public func validate() throws {
        guard chunkSize > 0 else {
            throw ChoirError.invalidParameter(
                parameter: "chunkSize", reason: "Chunk size must be greater than zero")
        }
    }
}
