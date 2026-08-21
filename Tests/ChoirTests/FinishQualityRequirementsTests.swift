import Testing
@testable import Choir

@Suite("Structured listening release gates")
struct FinishQualityRequirementsTests {
    @Test("TST-010: MOS protocol is frozen and blinded")
    func frozenMOSProtocol() {
        let definition = MOSProtocolDefinition.choirV1
        #expect(definition.identifier == "choir.mos.v1")
        #expect(definition.passagesPerVoice == 20)
        #expect(definition.scoreRange == 1...5)
        #expect(definition.isBlinded)
        #expect(definition.maximumSessionMinutes == 30)
    }

    @Test("QUA-001: an incomplete corpus can never pass")
    func incompleteMOSCorpusFails() throws {
        let observation = try MOSObservation(
            voice: .maeve,
            passageID: "p01",
            blindSampleID: "sample-a",
            naturalness: 5,
            cleanliness: 5)
        let report = MOSReport(observations: [observation])
        #expect(!report.hasCompleteCorpus)
        #expect(!report.meetsQUA001)
    }

    @Test("VOX-G-003: incomplete identification coverage cannot pass")
    func incompleteDistinctnessFails() {
        let report = VoiceDistinctnessReport(trials: [
            VoiceIdentificationTrial(
                expected: .maeve, selected: .maeve, passageDurationSeconds: 10),
        ])
        #expect(report.accuracy == 1)
        #expect(!report.coversEveryVoice)
        #expect(!report.meetsVOXG003)
    }

    @Test("VOX-G-003: full correct coverage passes")
    func completeDistinctnessPasses() {
        let report = VoiceDistinctnessReport(trials: Voice.allCases.map {
            VoiceIdentificationTrial(expected: $0, selected: $0, passageDurationSeconds: 10)
        })
        #expect(report.coversEveryVoice)
        #expect(report.accuracy == 1)
        #expect(report.meetsVOXG003)
    }

    @Test("QUA-007: fatigue checklist enforces duration and all three symptoms")
    func fatigueChecklist() {
        #expect(ListenerFatigueObservation(
            voice: .maeve,
            minutesListened: 30,
            harshSibilance: false,
            pumping: false,
            monotony: false).passes)
        #expect(!ListenerFatigueObservation(
            voice: .maeve,
            minutesListened: 29,
            harshSibilance: false,
            pumping: false,
            monotony: false).passes)
    }

    @Test("QUA-005: long-form stability applies all stated thresholds")
    func longFormStability() {
        let passing = LongFormStabilityReport(
            renderedMinutes: 60,
            firstLUFS: -16,
            lastLUFS: -15.6,
            firstTempo: 100,
            lastTempo: 102.9,
            firstSpectralCentroid: 1_000,
            lastSpectralCentroid: 1_049)
        #expect(passing.meetsQUA005)

        let failing = LongFormStabilityReport(
            renderedMinutes: 60,
            firstLUFS: -16,
            lastLUFS: -15.4,
            firstTempo: 100,
            lastTempo: 100,
            firstSpectralCentroid: 1_000,
            lastSpectralCentroid: 1_000)
        #expect(!failing.meetsQUA005)
    }
}
