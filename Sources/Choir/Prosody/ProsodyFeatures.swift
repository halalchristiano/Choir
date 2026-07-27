import Foundation

/// Prosodic features for a phoneme or segment.
public struct ProsodyFeatures: Sendable {
    /// Fundamental frequency (F0) in Hz.
    public var fundamentalFrequency: Double

    /// Duration of this phoneme/segment in milliseconds.
    public var duration: Double

    /// Energy/loudness in LUFS (ITU-R BS.1770-4).
    public var energy: Double

    /// Voicing probability (0.0 to 1.0).
    public var voicing: Double

    /// Whether this segment is voiced or unvoiced.
    public var isVoiced: Bool

    /// Pitch accent type: "H*", "L*", "L+H*", "H+L*", or "none".
    public var accentType: String

    /// Boundary tone: "H%", "L%", or "none".
    public var boundaryTone: String

    public init(
        fundamentalFrequency: Double = 120.0,
        duration: Double = 100.0,
        energy: Double = -20.0,
        voicing: Double = 1.0,
        isVoiced: Bool = true,
        accentType: String = "none",
        boundaryTone: String = "none"
    ) {
        self.fundamentalFrequency = max(50, min(400, fundamentalFrequency))
        self.duration = max(10, min(500, duration))
        self.energy = max(-60, min(0, energy))
        self.voicing = max(0, min(1.0, voicing))
        self.isVoiced = isVoiced
        self.accentType = accentType
        self.boundaryTone = boundaryTone
    }
}

/// A phoneme with its prosodic annotation.
public struct AnnotatedPhoneme: Sendable {
    /// The phoneme itself.
    public let phoneme: Phoneme

    /// Prosodic features for this phoneme.
    public var prosody: ProsodyFeatures

    /// Timing information.
    public let timing: TimingInfo

    public init(phoneme: Phoneme, prosody: ProsodyFeatures = ProsodyFeatures(), timing: TimingInfo = TimingInfo()) {
        self.phoneme = phoneme
        self.prosody = prosody
        self.timing = timing
    }
}

/// Timing information for a phoneme.
public struct TimingInfo: Sendable {
    /// Absolute start time in milliseconds.
    public var startTime: Double = 0

    /// Absolute end time in milliseconds.
    public var endTime: Double = 100

    /// Duration in milliseconds.
    public var duration: Double {
        endTime - startTime
    }

    public init(startTime: Double = 0, endTime: Double = 100) {
        self.startTime = startTime
        self.endTime = endTime
    }
}

/// Contour of a single prosodic parameter (pitch, energy, etc).
public struct ProsodyContour: Sendable {
    /// Contour points as (time, value) tuples.
    public let points: [(time: Double, value: Double)]

    /// Interpolation type: "linear", "spline", or "step".
    public let interpolation: String

    public init(points: [(time: Double, value: Double)], interpolation: String = "spline") {
        self.points = points
        self.interpolation = interpolation
    }

    /// Evaluates the contour at a given time using interpolation.
    public func valueAt(_ time: Double) -> Double? {
        guard !points.isEmpty else { return nil }

        // Clamp to range
        if time < points.first!.time { return points.first!.value }
        if time > points.last!.time { return points.last!.value }

        // Find surrounding points
        var lower: (time: Double, value: Double)? = nil
        var upper: (time: Double, value: Double)? = nil

        for point in points {
            if point.time <= time {
                lower = point
            }
            if point.time >= time && upper == nil {
                upper = point
            }
        }

        guard let l = lower, let u = upper else { return nil }

        // Linear interpolation (simplified; spline would be more sophisticated)
        if l.time == u.time { return l.value }
        let ratio = (time - l.time) / (u.time - l.time)
        return l.value + ratio * (u.value - l.value)
    }
}

/// Complete prosodic description of an utterance.
public struct ProsodyDescription: Sendable {
    /// Annotated phonemes with prosody.
    public let phonemes: [AnnotatedPhoneme]

    /// Pitch contour over the utterance.
    public let pitchContour: ProsodyContour

    /// Energy contour.
    public let energyContour: ProsodyContour

    /// Duration per phoneme.
    public let durations: [Double]

    /// Total duration in milliseconds.
    public var totalDuration: Double {
        phonemes.last?.timing.endTime ?? 0
    }

    public init(
        phonemes: [AnnotatedPhoneme],
        pitchContour: ProsodyContour,
        energyContour: ProsodyContour,
        durations: [Double]
    ) {
        self.phonemes = phonemes
        self.pitchContour = pitchContour
        self.energyContour = energyContour
        self.durations = durations
    }
}
