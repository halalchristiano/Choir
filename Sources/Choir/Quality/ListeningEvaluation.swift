import Foundation

/// Frozen listening-test protocol for QUA-001 and TST-010.
public struct MOSProtocolDefinition: Sendable, Equatable, Codable {
    public let identifier: String
    public let passagesPerVoice: Int
    public let scoreRange: ClosedRange<Int>
    public let isBlinded: Bool
    public let maximumSessionMinutes: Int

    public init(
        identifier: String,
        passagesPerVoice: Int,
        scoreRange: ClosedRange<Int> = 1...5,
        isBlinded: Bool = true,
        maximumSessionMinutes: Int = 30
    ) {
        self.identifier = identifier
        self.passagesPerVoice = max(1, passagesPerVoice)
        self.scoreRange = scoreRange
        self.isBlinded = isBlinded
        self.maximumSessionMinutes = max(1, maximumSessionMinutes)
    }

    /// The v1 protocol is intentionally versioned and immutable so results can
    /// be compared between releases without changing the scoring method.
    public static let choirV1 = MOSProtocolDefinition(
        identifier: "choir.mos.v1",
        passagesPerVoice: 20,
        scoreRange: 1...5,
        isBlinded: true,
        maximumSessionMinutes: 30)
}

/// One blinded listener score for a voice/passage sample.
public struct MOSObservation: Sendable, Equatable, Codable {
    public let voice: Voice
    public let passageID: String
    public let blindSampleID: String
    public let naturalness: Int
    public let cleanliness: Int

    public init(
        voice: Voice,
        passageID: String,
        blindSampleID: String,
        naturalness: Int,
        cleanliness: Int,
        using definition: MOSProtocolDefinition = .choirV1
    ) throws {
        guard !passageID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !blindSampleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "MOS sample", reason: "Passage and blinded sample IDs are required")
        }
        guard definition.scoreRange.contains(naturalness),
              definition.scoreRange.contains(cleanliness) else {
            throw ChoirError.invalidParameter(
                parameter: "MOS score",
                reason: "Naturalness and cleanliness must be within \(definition.scoreRange)")
        }
        self.voice = voice
        self.passageID = passageID
        self.blindSampleID = blindSampleID
        self.naturalness = naturalness
        self.cleanliness = cleanliness
    }
}

/// Release-gate summary for the structured MOS corpus (QUA-001).
public struct MOSReport: Sendable, Equatable, Codable {
    public let protocolDefinition: MOSProtocolDefinition
    public let observations: [MOSObservation]

    public init(
        protocolDefinition: MOSProtocolDefinition = .choirV1,
        observations: [MOSObservation]
    ) {
        self.protocolDefinition = protocolDefinition
        self.observations = observations
    }

    public var naturalnessMean: Double? {
        mean(observations.map(\.naturalness))
    }

    public var cleanlinessMean: Double? {
        mean(observations.map(\.cleanliness))
    }

    /// Every voice must cover the required number of distinct passages.
    public var hasCompleteCorpus: Bool {
        Voice.allCases.allSatisfy { voice in
            Set(observations.filter { $0.voice == voice }.map(\.passageID)).count
                >= protocolDefinition.passagesPerVoice
        }
    }

    public var meetsQUA001: Bool {
        hasCompleteCorpus
            && (naturalnessMean ?? 0) >= 4.2
            && (cleanlinessMean ?? 0) >= 4.5
    }

    private func mean(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}

/// One blind voice-identification trial for VOX-G-003.
public struct VoiceIdentificationTrial: Sendable, Equatable, Codable {
    public let expected: Voice
    public let selected: Voice
    public let passageDurationSeconds: Double

    public init(expected: Voice, selected: Voice, passageDurationSeconds: Double) {
        self.expected = expected
        self.selected = selected
        self.passageDurationSeconds = passageDurationSeconds.isFinite
            ? max(0, passageDurationSeconds) : 0
    }

    public var isCorrect: Bool { expected == selected }
    public var usesRequiredDuration: Bool { passageDurationSeconds >= 10 }
}

/// ABX-style distinctness report covering all 32 voices.
public struct VoiceDistinctnessReport: Sendable, Equatable, Codable {
    public let trials: [VoiceIdentificationTrial]

    public init(trials: [VoiceIdentificationTrial]) {
        self.trials = trials
    }

    public var accuracy: Double {
        guard !trials.isEmpty else { return 0 }
        return Double(trials.filter(\.isCorrect).count) / Double(trials.count)
    }

    public var coversEveryVoice: Bool {
        Set(trials.map(\.expected)) == Set(Voice.allCases)
    }

    public var meetsVOXG003: Bool {
        coversEveryVoice && trials.allSatisfy(\.usesRequiredDuration) && accuracy >= 0.9
    }
}

/// Structured 30-minute narration fatigue observation (QUA-007).
public struct ListenerFatigueObservation: Sendable, Equatable, Codable {
    public let voice: Voice
    public let minutesListened: Int
    public let harshSibilance: Bool
    public let pumping: Bool
    public let monotony: Bool
    public let notes: String

    public init(
        voice: Voice,
        minutesListened: Int,
        harshSibilance: Bool,
        pumping: Bool,
        monotony: Bool,
        notes: String = ""
    ) {
        self.voice = voice
        self.minutesListened = max(0, minutesListened)
        self.harshSibilance = harshSibilance
        self.pumping = pumping
        self.monotony = monotony
        self.notes = notes
    }

    public var passes: Bool {
        minutesListened >= 30 && !harshSibilance && !pumping && !monotony
    }
}

/// First/last-five-minute comparison for the QUA-005 long-form gate.
public struct LongFormStabilityReport: Sendable, Equatable, Codable {
    public let renderedMinutes: Double
    public let firstLUFS: Double
    public let lastLUFS: Double
    public let firstTempo: Double
    public let lastTempo: Double
    public let firstSpectralCentroid: Double
    public let lastSpectralCentroid: Double

    public init(
        renderedMinutes: Double,
        firstLUFS: Double,
        lastLUFS: Double,
        firstTempo: Double,
        lastTempo: Double,
        firstSpectralCentroid: Double,
        lastSpectralCentroid: Double
    ) {
        self.renderedMinutes = renderedMinutes
        self.firstLUFS = firstLUFS
        self.lastLUFS = lastLUFS
        self.firstTempo = firstTempo
        self.lastTempo = lastTempo
        self.firstSpectralCentroid = firstSpectralCentroid
        self.lastSpectralCentroid = lastSpectralCentroid
    }

    public var loudnessDriftLU: Double { abs(lastLUFS - firstLUFS) }
    public var tempoDriftPercent: Double {
        Self.percentChange(from: firstTempo, to: lastTempo)
    }
    public var timbreDriftPercent: Double {
        Self.percentChange(from: firstSpectralCentroid, to: lastSpectralCentroid)
    }

    public var meetsQUA005: Bool {
        let values = [
            renderedMinutes, firstLUFS, lastLUFS, firstTempo, lastTempo,
            firstSpectralCentroid, lastSpectralCentroid,
        ]
        return values.allSatisfy(\.isFinite)
            && renderedMinutes >= 60
            && firstTempo > 0
            && firstSpectralCentroid > 0
            && loudnessDriftLU <= 0.5
            && tempoDriftPercent <= 3
            && timbreDriftPercent <= 5
    }

    private static func percentChange(from baseline: Double, to value: Double) -> Double {
        guard baseline.isFinite, value.isFinite, baseline != 0 else { return .infinity }
        return abs(value - baseline) / abs(baseline) * 100
    }
}
