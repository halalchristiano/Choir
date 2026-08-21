import Foundation

/// Prosodic features for a phoneme or segment.
public struct ProsodyFeatures: Sendable, Equatable, Codable {
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
        self.fundamentalFrequency = Self.bounded(fundamentalFrequency, 50...400, fallback: 120)
        self.duration = Self.bounded(duration, 10...500, fallback: 100)
        self.energy = Self.bounded(energy, -60...0, fallback: -20)
        self.voicing = Self.bounded(voicing, 0...1, fallback: 1)
        self.isVoiced = isVoiced
        self.accentType = Self.validAccents.contains(accentType) ? accentType : "none"
        self.boundaryTone = Self.validBoundaryTones.contains(boundaryTone) ? boundaryTone : "none"
    }

    private static let validAccents: Set<String> = ["H*", "L*", "L+H*", "H+L*", "none"]
    private static let validBoundaryTones: Set<String> = ["H%", "L%", "none"]

    private static func bounded(
        _ value: Double, _ range: ClosedRange<Double>, fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }
}

/// A phoneme with its prosodic annotation.
public struct AnnotatedPhoneme: Sendable, Equatable, Codable {
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
public struct TimingInfo: Sendable, Equatable, Codable {
    /// Absolute start time in milliseconds.
    public var startTime: Double = 0

    /// Absolute end time in milliseconds.
    public var endTime: Double = 100

    /// Duration in milliseconds.
    public var duration: Double {
        endTime - startTime
    }

    public var midpoint: Double { startTime + duration / 2 }

    public var isEmpty: Bool { duration == 0 }

    public init(startTime: Double = 0, endTime: Double = 100) {
        let safeStart = startTime.isFinite ? max(0, startTime) : 0
        self.startTime = safeStart
        self.endTime = endTime.isFinite ? max(safeStart, endTime) : safeStart
    }

    public func contains(_ time: Double) -> Bool {
        time.isFinite && time >= startTime && time < endTime
    }

    public func shifted(by milliseconds: Double) -> TimingInfo {
        guard milliseconds.isFinite else { return self }
        let effectiveShift = max(milliseconds, -startTime)
        return TimingInfo(
            startTime: startTime + effectiveShift,
            endTime: endTime + effectiveShift)
    }
}

/// Contour of a single prosodic parameter (pitch, energy, etc).
public struct ProsodyContour: Sendable {
    /// Contour points as (time, value) tuples.
    public let points: [(time: Double, value: Double)]

    /// Interpolation type: "linear", "spline", or "step".
    public let interpolation: String

    public init(points: [(time: Double, value: Double)], interpolation: String = "spline") {
        var normalized: [(time: Double, value: Double)] = []
        for point in points where point.time.isFinite && point.value.isFinite {
            if let existing = normalized.firstIndex(where: { $0.time == point.time }) {
                normalized[existing] = point
            } else {
                normalized.append(point)
            }
        }
        self.points = normalized.sorted { $0.time < $1.time }
        self.interpolation = ["linear", "spline", "step"].contains(interpolation.lowercased())
            ? interpolation.lowercased()
            : "linear"
    }

    public var isEmpty: Bool { points.isEmpty }
    public var startTime: Double? { points.first?.time }
    public var endTime: Double? { points.last?.time }
    public var duration: Double { max(0, (endTime ?? 0) - (startTime ?? 0)) }
    public var minimumValue: Double? { points.map { $0.value }.min() }
    public var maximumValue: Double? { points.map { $0.value }.max() }

    /// Evaluates the contour at a given time using interpolation.
    public func valueAt(_ time: Double) -> Double? {
        guard time.isFinite, !points.isEmpty else { return nil }

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

        if interpolation == "step" { return l.value }

        // Spline currently uses the stable linear fallback until neighboring
        // tangent estimation is added.
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
        phonemes.map(\.timing.endTime).max() ?? 0
    }

    public var isEmpty: Bool { phonemes.isEmpty }

    public var hasMatchingDurationCount: Bool { durations.count == phonemes.count }

    public var invalidDurationIndices: [Int] {
        durations.indices.filter { !durations[$0].isFinite || durations[$0] < 0 }
    }

    public var isStructurallyValid: Bool {
        hasMatchingDurationCount && invalidDurationIndices.isEmpty
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
