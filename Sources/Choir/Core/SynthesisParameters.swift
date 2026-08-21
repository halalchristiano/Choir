import Foundation

/// Scheduling intent for synthesis work (SRS CON-004).
///
/// Choir never changes the caller's task priority. Instead, potentially
/// expensive front-end, model, and vocoder work is placed in a structured
/// child task with the requested priority. `.automatic` inherits the priority
/// of the calling task.
public enum SynthesisExecutionPriority: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// Inherit the priority of the calling task.
    case automatic

    /// Latency-sensitive playback, UI, and game dialogue work.
    case interactive

    /// Ordinary foreground batch work.
    case standard

    /// User-visible work that may run in the background.
    case utility

    /// Deferrable pre-rendering and maintenance work.
    case background

    /// The Swift structured-concurrency priority used by the internal
    /// scheduler. `nil` means inherit from the caller.
    var taskPriority: TaskPriority? {
        switch self {
        case .automatic: return nil
        case .interactive: return .high
        case .standard: return .medium
        case .utility: return .low
        case .background: return .background
        }
    }
}

/// Parameters for controlling synthesis output, including prosody and expression.
public struct SynthesisParameters: Sendable, Equatable, Hashable, Codable {
    /// Pitch shift in semitones (-6 to +6). Default is 0 (PRO-001).
    public var pitchShift: Double = 0

    /// Speech rate multiplier (0.6 to 2.0). Default is 1.0 (PRO-002).
    public var rate: Double = 1.0

    /// Emotional intensity (0.0 to 1.0). Default is 0.5.
    public var emotionalIntensity: Double = 0.5

    /// Breathiness amount (0.0 to 1.0). Default is 0.0.
    public var breathiness: Double = 0.0

    /// Normalized age shift: younger to older (-1 to +1). Default is 0 (VOX-P-007).
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
        self.pitchShift = Self.bounded(pitchShift, low: -6, high: 6, fallback: 0)
        self.rate = Self.bounded(rate, low: 0.6, high: 2.0, fallback: 1)
        self.emotionalIntensity = Self.bounded(emotionalIntensity, low: 0, high: 1, fallback: 0.5)
        self.breathiness = Self.bounded(breathiness, low: 0, high: 1, fallback: 0)
        self.ageShift = Self.bounded(ageShift, low: -1, high: 1, fallback: 0)
        self.genderShift = Self.bounded(genderShift, low: -1, high: 1, fallback: 0)

        self.clampings = Self.clampings(
            pitchShift: pitchShift, rate: rate,
            emotionalIntensity: emotionalIntensity, breathiness: breathiness,
            ageShift: ageShift, genderShift: genderShift)
    }

    private enum CodingKeys: String, CodingKey {
        case pitchShift, rate, emotionalIntensity, breathiness
        case ageShift, genderShift, seed, clampings
    }

    /// Decoding always re-enters the canonical initializer. This prevents a
    /// serialized value from bypassing envelopes or supplying a stale derived
    /// clamping report.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rebuilt = SynthesisParameters(
            pitchShift: try container.decodeIfPresent(Double.self, forKey: .pitchShift) ?? 0,
            rate: try container.decodeIfPresent(Double.self, forKey: .rate) ?? 1,
            emotionalIntensity: try container.decodeIfPresent(
                Double.self, forKey: .emotionalIntensity) ?? 0.5,
            breathiness: try container.decodeIfPresent(Double.self, forKey: .breathiness) ?? 0,
            ageShift: try container.decodeIfPresent(Double.self, forKey: .ageShift) ?? 0,
            genderShift: try container.decodeIfPresent(Double.self, forKey: .genderShift) ?? 0,
            seed: try container.decodeIfPresent(UInt64.self, forKey: .seed))
        let recorded = try container.decodeIfPresent(
            [Clamping].self, forKey: .clampings) ?? []
        self = rebuilt.mergingActiveClampings(recorded)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pitchShift, forKey: .pitchShift)
        try container.encode(rate, forKey: .rate)
        try container.encode(emotionalIntensity, forKey: .emotionalIntensity)
        try container.encode(breathiness, forKey: .breathiness)
        try container.encode(ageShift, forKey: .ageShift)
        try container.encode(genderShift, forKey: .genderShift)
        try container.encodeIfPresent(seed, forKey: .seed)
        try container.encode(clampings, forKey: .clampings)
    }

    // MARK: - Envelope clamping (API-004, PRO-030)

    /// One parameter that was clamped into its documented envelope.
    public struct Clamping: Sendable, Equatable, Hashable, Codable {
        public let parameter: String
        public let requested: Double
        public let applied: Double
        public let reason: String?

        public init(parameter: String, requested: Double, applied: Double, reason: String? = nil) {
            self.parameter = parameter
            self.requested = requested
            self.applied = applied
            self.reason = reason
        }

        public var description: String {
            if let reason { return "\(parameter): \(reason); applied \(applied)" }
            return "\(parameter) \(requested) clamped to \(applied)"
        }
    }

    /// Parameters that were clamped when this value was constructed.
    ///
    /// API-004 requires validation that *reports* envelope clamping. Silently
    /// clamping is the failure mode this exists to prevent: a caller asking for
    /// a pitch shift of 24 semitones and receiving 6 with no indication will
    /// conclude the parameter does nothing.
    public let clampings: [Clamping]

    /// Whether any parameter was clamped.
    public var wasClamped: Bool { !clampings.isEmpty }

    private static func clampings(
        pitchShift: Double, rate: Double, emotionalIntensity: Double,
        breathiness: Double, ageShift: Double, genderShift: Double
    ) -> [Clamping] {
        var result: [Clamping] = []
        func check(
            _ name: String, _ requested: Double, _ low: Double, _ high: Double,
            fallback: Double
        ) {
            guard requested.isFinite else {
                result.append(Clamping(
                    parameter: name, requested: fallback, applied: fallback,
                    reason: "non-finite value replaced with the default"))
                return
            }
            let applied = max(low, min(high, requested))
            if applied != requested {
                result.append(Clamping(parameter: name, requested: requested, applied: applied))
            }
        }
        check("pitchShift", pitchShift, -6, 6, fallback: 0)
        check("rate", rate, 0.6, 2.0, fallback: 1)
        check("emotionalIntensity", emotionalIntensity, 0, 1, fallback: 0.5)
        check("breathiness", breathiness, 0, 1, fallback: 0)
        check("ageShift", ageShift, -1, 1, fallback: 0)
        check("genderShift", genderShift, -1, 1, fallback: 0)
        return result
    }

    private static func bounded(
        _ value: Double, low: Double, high: Double, fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return max(low, min(high, value))
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
        return draft.validated()
    }

    /// Revalidates a value after direct mutation of its public properties.
    public func validated() -> SynthesisParameters {
        let rebuilt = SynthesisParameters(
            pitchShift: pitchShift,
            rate: rate,
            emotionalIntensity: emotionalIntensity,
            breathiness: breathiness,
            ageShift: ageShift,
            genderShift: genderShift,
            seed: seed)
        return rebuilt.mergingActiveClampings(clampings)
    }

    /// Preserves a prior report only while the associated public value still
    /// equals the applied value. A direct mutation invalidates that old report;
    /// reconstruction contributes a fresh one when the mutation itself needs
    /// clamping.
    private func mergingActiveClampings(_ prior: [Clamping]) -> SynthesisParameters {
        let newlyClamped = Set(clampings.map(\.parameter))
        let activePrior = prior.filter { clamping in
            guard !newlyClamped.contains(clamping.parameter),
                  let currentValue = value(for: clamping.parameter) else {
                return false
            }
            return currentValue == clamping.applied
        }
        guard !activePrior.isEmpty else { return self }
        return SynthesisParameters(
            applied: self,
            clampings: activePrior + clampings)
    }

    private init(applied: SynthesisParameters, clampings: [Clamping]) {
        self.pitchShift = applied.pitchShift
        self.rate = applied.rate
        self.emotionalIntensity = applied.emotionalIntensity
        self.breathiness = applied.breathiness
        self.ageShift = applied.ageShift
        self.genderShift = applied.genderShift
        self.seed = applied.seed
        self.clampings = clampings
    }

    private func value(for parameter: String) -> Double? {
        switch parameter {
        case "pitchShift": return pitchShift
        case "rate": return rate
        case "emotionalIntensity": return emotionalIntensity
        case "breathiness": return breathiness
        case "ageShift": return ageShift
        case "genderShift": return genderShift
        default: return nil
        }
    }
}

/// Audio format specification for synthesis output.
public struct AudioFormat: Sendable, Equatable, Hashable, Codable {
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

/// Options for phrase-progressive chunk delivery.
public struct StreamingOptions: Sendable, Equatable, Hashable, Codable {
    /// Target buffer size for streaming chunks in samples. Default is 2400 (50ms at 48kHz).
    public var chunkSize: Int = 2400

    /// Whether to preload the acoustic model. Default is true.
    public var preloadModel: Bool = true

    /// Scheduling priority for this stream. Interactive is the streaming
    /// default because callers are commonly feeding live playback.
    public var priority: SynthesisExecutionPriority = .interactive

    public init(
        chunkSize: Int = 2400,
        preloadModel: Bool = true,
        priority: SynthesisExecutionPriority = .interactive
    ) {
        self.chunkSize = chunkSize
        self.preloadModel = preloadModel
        self.priority = priority
    }

    private enum CodingKeys: String, CodingKey {
        case chunkSize
        case preloadModel
        case priority
    }

    /// Decodes options written before execution priority was introduced by
    /// assigning the streaming default, preserving API-006 compatibility.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            chunkSize: try container.decodeIfPresent(Int.self, forKey: .chunkSize) ?? 2400,
            preloadModel: try container.decodeIfPresent(Bool.self, forKey: .preloadModel) ?? true,
            priority: try container.decodeIfPresent(
                SynthesisExecutionPriority.self,
                forKey: .priority) ?? .interactive)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chunkSize, forKey: .chunkSize)
        try container.encode(preloadModel, forKey: .preloadModel)
        try container.encode(priority, forKey: .priority)
    }

    /// Validates options before a streaming request starts.
    public func validate() throws {
        guard chunkSize > 0 else {
            throw ChoirError.invalidParameter(
                parameter: "chunkSize", reason: "Chunk size must be greater than zero")
        }
    }
}
