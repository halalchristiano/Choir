import Foundation

/// Records validated parameter changes for a caller-managed stream controller.
///
/// The current synthesis pipeline does not consume these changes mid-sentence;
/// apply snapshots at request or sentence boundaries until STR-005 is complete.
public actor RealTimeController {
    /// Parameter change event.
    public struct ParameterChange: Sendable {
        public let timestamp: Date
        public let parameter: String
        public let oldValue: Double
        public let newValue: Double

        public init(parameter: String, oldValue: Double, newValue: Double) {
            self.timestamp = Date()
            self.parameter = parameter
            self.oldValue = oldValue
            self.newValue = newValue
        }
    }

    /// Current active parameters.
    private var currentParameters: SynthesisParameters

    /// Change history (for analysis and debugging).
    private var history: [ParameterChange] = []

    /// Maximum history size.
    private let maxHistory: Int = 1000

    public init(initialParameters: SynthesisParameters = SynthesisParameters()) {
        self.currentParameters = initialParameters
    }

    /// Gets current parameters.
    public func getParameters() -> SynthesisParameters {
        currentParameters
    }

    /// Sets a new pitch shift value.
    public func setPitchShift(_ value: Double) {
        let oldValue = currentParameters.pitchShift
        currentParameters.pitchShift = max(-6, min(6, value))

        if oldValue != currentParameters.pitchShift {
            recordChange(ParameterChange(parameter: "pitchShift", oldValue: oldValue, newValue: currentParameters.pitchShift))
        }
    }

    /// Sets a new rate value.
    public func setRate(_ value: Double) {
        let oldValue = currentParameters.rate
        currentParameters.rate = max(0.6, min(2.0, value))

        if oldValue != currentParameters.rate {
            recordChange(ParameterChange(parameter: "rate", oldValue: oldValue, newValue: currentParameters.rate))
        }
    }

    /// Sets emotional intensity.
    public func setEmotionalIntensity(_ value: Double) {
        let oldValue = currentParameters.emotionalIntensity
        currentParameters.emotionalIntensity = max(0, min(1.0, value))

        if oldValue != currentParameters.emotionalIntensity {
            recordChange(ParameterChange(parameter: "emotionalIntensity", oldValue: oldValue, newValue: currentParameters.emotionalIntensity))
        }
    }

    /// Sets breathiness.
    public func setBreathiness(_ value: Double) {
        let oldValue = currentParameters.breathiness
        currentParameters.breathiness = max(0, min(1.0, value))

        if oldValue != currentParameters.breathiness {
            recordChange(ParameterChange(parameter: "breathiness", oldValue: oldValue, newValue: currentParameters.breathiness))
        }
    }

    /// Sets age shift.
    public func setAgeShift(_ value: Double) {
        let oldValue = currentParameters.ageShift
        currentParameters.ageShift = max(-1, min(1, value))

        if oldValue != currentParameters.ageShift {
            recordChange(ParameterChange(parameter: "ageShift", oldValue: oldValue, newValue: currentParameters.ageShift))
        }
    }

    /// Sets gender shift.
    public func setGenderShift(_ value: Double) {
        let oldValue = currentParameters.genderShift
        currentParameters.genderShift = max(-1.0, min(1.0, value))

        if oldValue != currentParameters.genderShift {
            recordChange(ParameterChange(parameter: "genderShift", oldValue: oldValue, newValue: currentParameters.genderShift))
        }
    }

    /// Updates all parameters at once.
    public func updateParameters(_ parameters: SynthesisParameters) {
        setPitchShift(parameters.pitchShift)
        setRate(parameters.rate)
        setEmotionalIntensity(parameters.emotionalIntensity)
        setBreathiness(parameters.breathiness)
        setAgeShift(parameters.ageShift)
        setGenderShift(parameters.genderShift)
    }

    /// Returns change history.
    public func getHistory() -> [ParameterChange] {
        history
    }

    /// Clears change history.
    public func clearHistory() {
        history.removeAll()
    }

    /// Records a parameter change.
    private func recordChange(_ change: ParameterChange) {
        history.append(change)

        // Keep history size bounded
        if history.count > maxHistory {
            history.removeFirst()
        }
    }

    /// Returns statistics about parameter changes.
    public func getStatistics() -> ControllerStatistics {
        ControllerStatistics(
            changeCount: history.count,
            parametersChanged: Set(history.map { $0.parameter }).count,
            timeSpan: history.first.map { Date().timeIntervalSince($0.timestamp) } ?? 0
        )
    }
}

/// Statistics for real-time controller.
public struct ControllerStatistics: Sendable {
    public let changeCount: Int
    public let parametersChanged: Int
    public let timeSpan: TimeInterval
}

/// Smooth parameter ramping for gradual changes.
public struct ParameterRamp: Sendable {
    public enum CurveType: Sendable {
        case linear
        case easeIn
        case easeOut
        case easeInOut
    }

    public let parameter: String
    public let startValue: Double
    public let endValue: Double
    public let duration: TimeInterval
    public let curve: CurveType
    public let startTime: Date

    public init(
        parameter: String,
        from: Double,
        to: Double,
        duration: TimeInterval,
        curve: CurveType = .linear
    ) {
        self.parameter = parameter
        self.startValue = from
        self.endValue = to
        self.duration = duration
        self.curve = curve
        self.startTime = Date()
    }

    /// Evaluates the ramp at current time.
    public var currentValue: Double {
        let elapsed = Date().timeIntervalSince(startTime)
        let progress = min(1.0, max(0.0, elapsed / duration))

        let adjustedProgress: Double
        switch curve {
        case .linear:
            adjustedProgress = progress
        case .easeIn:
            adjustedProgress = progress * progress
        case .easeOut:
            adjustedProgress = 1.0 - (1.0 - progress) * (1.0 - progress)
        case .easeInOut:
            if progress < 0.5 {
                adjustedProgress = 2.0 * progress * progress
            } else {
                adjustedProgress = 1.0 - pow(-2.0 * progress + 2.0, 2.0) / 2.0
            }
        }

        return startValue + (endValue - startValue) * adjustedProgress
    }

    /// Whether the ramp has completed.
    public var isComplete: Bool {
        Date().timeIntervalSince(startTime) >= duration
    }
}
