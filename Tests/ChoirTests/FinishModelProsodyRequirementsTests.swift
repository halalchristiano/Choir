import Foundation
import Testing
@testable import Choir

@Suite("Finish SRS voice-profile and prosody requirements")
struct FinishModelProsodyRequirementsTests {
    @Test("VOX-P-001: every profile stores pause style and articulation precision")
    func completeVoiceProfileParameterSet() {
        for voice in Voice.allCases {
            let profile = voice.profile
            #expect((0...1).contains(profile.articulationPrecision))
            #expect((0.5...2).contains(profile.pauseStyle.comma))
            #expect((0.5...2).contains(profile.pauseStyle.period))
            #expect((0.5...2).contains(profile.pauseStyle.paragraph))
        }
    }

    @Test("VOX-P-001: child villains retain deliberately precise articulation")
    func childVillainArticulation() {
        for villain in Voice.villains where villain.ageBand == .child {
            let peerMaximum = Voice.voices(ageBand: .child, gender: villain.gender)
                .filter { !$0.isVillain }
                .map(\.profile.articulationPrecision)
                .max() ?? 0
            #expect(villain.profile.articulationPrecision > peerMaximum)
        }
    }

    @Test("VOX-P-001: pause style changes structural timing")
    func pauseStyleAffectsTiming() {
        let transcript = PhoneticTranscription(
            phonemes: [Phoneme("a"), Phoneme("b")],
            originalText: "a b",
            wordBoundaries: [0, 1],
            wordTexts: ["a", "b"],
            phraseBoundaries: [0: .major])
        var short = [100.0, 100.0]
        var long = short

        ProsodyPredictor.applyBoundaryPauses(
            to: &short,
            transcript: transcript,
            rate: 1,
            pauseStyle: VoicePauseStyle(comma: 0.5, period: 0.5, paragraph: 0.5))
        ProsodyPredictor.applyBoundaryPauses(
            to: &long,
            transcript: transcript,
            rate: 1,
            pauseStyle: VoicePauseStyle(comma: 2, period: 2, paragraph: 2))

        #expect(long[0] > short[0])
    }

    @Test("PRO-001: semitone shift is a frequency ratio")
    func semitonePitchRatio() {
        let profile = VoiceProfile(
            identifier: "test.voice",
            displayName: "TEST",
            ageBand: .youngAdult,
            gender: .male,
            isVillain: false,
            characterDescription: "Test profile",
            recommendedUse: [.ui],
            medianF0: 100,
            f0Range: 50...300,
            formantScale: 1,
            spectralTilt: -8,
            spectralTiltDescription: "neutral",
            breathiness: 0,
            roughness: 0,
            tempo: 4,
            pitchDynamism: 2)
        let transcript = PhoneticTranscription(
            phonemes: [Phoneme("a", stress: 0)],
            originalText: "a",
            wordBoundaries: [0],
            wordTexts: ["a"])
        let predictor = ProsodyPredictor()
        let base = predictor.predictProsody(
            for: transcript,
            with: SynthesisParameters(pitchShift: 0, seed: 7),
            voiceProfile: profile)
        let shifted = predictor.predictProsody(
            for: transcript,
            with: SynthesisParameters(pitchShift: 6, seed: 7),
            voiceProfile: profile)

        let basePitch = base.pitchContour.points.first?.value ?? 0
        let shiftedPitch = shifted.pitchContour.points.first?.value ?? 0
        #expect(abs(shiftedPitch / basePitch - pow(2, 0.5)) < 0.001)
    }

    @Test("PRO-001: paragraph resets preserve the requested interval")
    func paragraphResetPreservesPitchRatio() {
        let profile = VoiceProfile(
            identifier: "test.reset.voice",
            displayName: "RESET",
            ageBand: .youngAdult,
            gender: .female,
            isVillain: false,
            characterDescription: "Test profile",
            recommendedUse: [.ui],
            medianF0: 120,
            f0Range: 40...500,
            formantScale: 1,
            spectralTilt: -8,
            spectralTiltDescription: "neutral",
            breathiness: 0,
            roughness: 0,
            tempo: 4,
            pitchDynamism: 2)
        let transcript = PhoneticTranscription(
            phonemes: [Phoneme("a"), Phoneme("a")],
            originalText: "a\n\na",
            wordBoundaries: [0, 1],
            wordTexts: ["a", "a"],
            phraseBoundaries: [0: .paragraph])
        let predictor = ProsodyPredictor()
        let base = predictor.predictProsody(
            for: transcript,
            with: SynthesisParameters(pitchShift: 0, seed: 77),
            voiceProfile: profile)
        let shifted = predictor.predictProsody(
            for: transcript,
            with: SynthesisParameters(pitchShift: 6, seed: 77),
            voiceProfile: profile)

        #expect(base.pitchContour.points.count == shifted.pitchContour.points.count)
        for (unshifted, transposed) in zip(
            base.pitchContour.points, shifted.pitchContour.points
        ) {
            #expect(abs(transposed.value / unshifted.value - pow(2, 0.5)) < 0.001)
        }
    }

    @Test("VOX-P-007: age and gender controls move the continuous pitch realization")
    func ageAndGenderConditioningAffectsProsody() {
        let transcript = PhoneticTranscription(
            phonemes: [Phoneme("a")], originalText: "a",
            wordBoundaries: [0], wordTexts: ["a"])
        let predictor = ProsodyPredictor()
        let youngerFeminine = predictor.predictProsody(
            for: transcript,
            with: SynthesisParameters(ageShift: -1, genderShift: -1, seed: 1),
            voiceProfile: Voice.isla.profile)
        let olderMasculine = predictor.predictProsody(
            for: transcript,
            with: SynthesisParameters(ageShift: 1, genderShift: 1, seed: 1),
            voiceProfile: Voice.isla.profile)
        #expect(
            (youngerFeminine.pitchContour.points.first?.value ?? 0)
                > (olderMasculine.pitchContour.points.first?.value ?? 0))
    }

    @Test("Codable revalidates parameters and defaults new voice-profile fields")
    func backwardCompatibleValidatedDecoding() throws {
        let unsafe = Data(#"{"pitchShift":100,"rate":0,"ageShift":9}"#.utf8)
        let decoded = try JSONDecoder().decode(SynthesisParameters.self, from: unsafe)
        #expect(decoded.pitchShift == 6)
        #expect(decoded.rate == 0.6)
        #expect(decoded.ageShift == 1)
        #expect(decoded.wasClamped)

        let originallyClamped = SynthesisParameters(pitchShift: 100, rate: 0)
        let roundTrip = try JSONDecoder().decode(
            SynthesisParameters.self,
            from: JSONEncoder().encode(originallyClamped))
        #expect(roundTrip == originallyClamped)

        let encodedProfile = try JSONEncoder().encode(Voice.maeve.profile)
        var object = try #require(
            JSONSerialization.jsonObject(with: encodedProfile) as? [String: Any])
        object.removeValue(forKey: "pauseStyle")
        object.removeValue(forKey: "articulationPrecision")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let profile = try JSONDecoder().decode(VoiceProfile.self, from: legacy)
        #expect((0.5...2).contains(profile.pauseStyle.period))
        #expect((0...1).contains(profile.articulationPrecision))
    }

    @Test("Prosody spline uses neighboring control points")
    func splineIsNotLinearFallback() {
        let points = [
            (time: 0.0, value: 0.0),
            (time: 1.0, value: 10.0),
            (time: 2.0, value: 0.0),
            (time: 3.0, value: 0.0),
        ]
        let linear = ProsodyContour(points: points, interpolation: "linear")
        let spline = ProsodyContour(points: points, interpolation: "spline")

        #expect(linear.valueAt(1.5) == 5)
        #expect(spline.valueAt(1.5) != linear.valueAt(1.5))
        #expect((0...10).contains(spline.valueAt(1.5) ?? -1))
    }

    @Test("SYN-002: phase-reconstruction fallback is deterministic")
    func deterministicVocoderFallback() async throws {
        let features = AcousticFeatures(
            features: [
                [0.1, 0.3, 0.2, 0.05],
                [0.2, 0.4, 0.1, 0.02],
                [0.3, 0.2, 0.15, 0.01],
            ],
            frameRate: 50)
        let vocoder = NeuralVocoder(frequencyBins: 4, referenceRate: 8_000)

        let first = try await vocoder.synthesize(features: features, sampleRate: 8_000)
        let second = try await vocoder.synthesize(features: features, sampleRate: 8_000)

        #expect(!first.isEmpty)
        #expect(first == second)
        #expect(first.count == 480) // 3 frames / 50 Hz * 8,000 samples/s
    }

    @Test("Vocoder rejects malformed acoustic tensors")
    func vocoderValidation() async {
        let malformed = AcousticFeatures(features: [[0.1, 0.2], [0.3]], frameRate: 50)
        do {
            _ = try await NeuralVocoder(frequencyBins: 2).synthesize(
                features: malformed, sampleRate: 48_000)
            Issue.record("Expected malformed acoustic features to be rejected")
        } catch {
            #expect(error is ChoirError)
        }
    }

    @Test("SYN-008: adversarial vocoder sizes fail without integer overflow")
    func vocoderBoundsAreTyped() async {
        let feature = AcousticFeatures(features: [[0.1, 0.2]], frameRate: 50)
        do {
            _ = try await NeuralVocoder(
                frequencyBins: .max,
                referenceRate: .max
            ).synthesize(features: feature, sampleRate: 48_000)
            Issue.record("Expected bounded frequency-bin validation")
        } catch {
            #expect(error is ChoirError)
        }

        let invalidRate = AcousticFeatures(features: [[0.1, 0.2]], frameRate: .max)
        do {
            _ = try await MockVocoder().synthesize(
                features: invalidRate, sampleRate: 48_000)
            Issue.record("Expected bounded frame-rate validation")
        } catch {
            #expect(error is ChoirError)
        }

        let count = 60
        let largeInput = AcousticModelInput(
            phonemeIndices: Array(repeating: 1, count: count),
            durations: Array(repeating: 10_000, count: count),
            fundamentalFrequency: Array(repeating: 120, count: count),
            energy: Array(repeating: -20, count: count),
            stress: Array(repeating: 0, count: count),
            voicing: Array(repeating: 1, count: count))
        do {
            _ = try await MockAcousticModel(
                frameRate: .max, frequencyBins: .max
            ).predict(input: largeInput)
            Issue.record("Expected bounded mock-model allocation")
        } catch {
            #expect(error is ChoirError)
        }
    }

    @Test("ML-C-001: generated Core ML inference can be injected and validated")
    func coreMLAcousticAdapter() async throws {
        let model = CoreMLAcousticModel { input in
            #expect(input.voiceID == Voice.maeve.conditioningID)
            return AcousticFeatures(features: [[0.1, 0.2], [0.3, 0.4]], frameRate: 50)
        }
        let input = AcousticModelInput(
            phonemeIndices: [1],
            durations: [100],
            fundamentalFrequency: [180],
            energy: [-20],
            stress: [0],
            voicing: [1],
            voiceID: Voice.maeve.conditioningID)

        let result = try await model.predict(input: input)
        #expect(result.frameCount == 2)
        #expect(result.frequencyBins == 2)
    }

    @Test("ML-C-001: generated Core ML vocoder inference can be injected")
    func coreMLVocoderAdapter() async throws {
        let vocoder = CoreMLVocoder { features, sampleRate in
            #expect(features.frameCount == 1)
            #expect(sampleRate == 48_000)
            return [0, 1, -1, 0]
        }
        let result = try await vocoder.synthesize(
            features: AcousticFeatures(features: [[0.1, 0.2]], frameRate: 50),
            sampleRate: 48_000)
        #expect(result == [0, 1, -1, 0])
    }
}
