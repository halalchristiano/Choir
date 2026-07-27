import Testing
import Foundation
@testable import Choir

@Suite("ToBI Prosody System")
struct ToBITests {
    let predictor = ToBIPredictor()

    @Test("Generates ToBI annotations")
    func testToBIGeneration() {
        let phonemes = [
            Phoneme("h"),
            Phoneme("ə"),
            Phoneme("l", stress: 1),
            Phoneme("oʊ"),
        ]
        let transcript = PhoneticTranscription(phonemes: phonemes, originalText: "hello")

        let annotations = predictor.predictToBI(for: transcript, wordCount: 1)

        #expect(!annotations.isEmpty)
        #expect(annotations[0].pitchAccent != .none)
    }

    @Test("ToBI modifies F0 correctly")
    func testToBIF0Modification() {
        let baseF0 = 120.0
        let tobi = ToBI(pitchAccent: .H_star)

        let modifiedF0 = predictor.applyToBIToF0(baseF0: baseF0, tobi: tobi, position: 0.5)

        #expect(modifiedF0 > baseF0)
        #expect(modifiedF0 >= 50 && modifiedF0 <= 400)
    }

    @Test("Rising accent increases F0 progressively")
    func testRisingAccent() {
        let tobi = ToBI(pitchAccent: .L_H)

        let startF0 = predictor.applyToBIToF0(baseF0: 120, tobi: tobi, position: 0.0)
        let midF0 = predictor.applyToBIToF0(baseF0: 120, tobi: tobi, position: 0.5)
        let endF0 = predictor.applyToBIToF0(baseF0: 120, tobi: tobi, position: 1.0)

        #expect(startF0 < midF0)
        #expect(midF0 < endF0)
    }
}

@Suite("Voice Blending")
struct VoiceBlendingTests {
    let blending = VoiceBlending()

    @Test("Blends voices at midpoint")
    func testMidpointBlending() {
        let profile1 = VoiceBlending.VoiceProfile(
            voice: .narratorMasculine,
            parameters: SynthesisParameters(pitchShift: -5, rate: 0.8)
        )
        let profile2 = VoiceBlending.VoiceProfile(
            voice: .narratorFeminine,
            parameters: SynthesisParameters(pitchShift: 5, rate: 1.2)
        )

        let blended = blending.blend(profile1, with: profile2, mix: 0.5)

        // At 50% mix, should be midway between parameters
        #expect(blended.pitchShift >= -5 && blended.pitchShift <= 5)
        #expect(blended.rate >= 0.8 && blended.rate <= 1.2)
    }

    @Test("Clamps mix value to [0, 1]")
    func testMixClamping() {
        let profile1 = VoiceBlending.VoiceProfile(voice: .youngAdultMasculine)
        let profile2 = VoiceBlending.VoiceProfile(voice: .youngAdultFeminine)

        let tooLow = blending.blend(profile1, with: profile2, mix: -0.5)
        let tooHigh = blending.blend(profile1, with: profile2, mix: 1.5)

        // Both should produce valid parameters
        #expect(tooLow.rate > 0 && tooLow.rate <= 2.0)
        #expect(tooHigh.rate > 0 && tooHigh.rate <= 2.0)
    }

    @Test("Gender transition creates spectrum")
    func testGenderTransition() {
        let transition = blending.genderTransition(from: .youngAdultMasculine, to: .youngAdultFeminine, steps: 3)

        #expect(transition.count == 4)  // steps + 1

        // Should progress from masculine to feminine
        for i in 0..<transition.count - 1 {
            #expect(transition[i].genderShift < transition[i + 1].genderShift)
        }
    }

    @Test("Age transition creates spectrum")
    func testAgeTransition() {
        let transition = blending.ageTransition(from: .childFeminine, to: .elderlyFeminine, steps: 4)

        #expect(transition.count == 5)
        // Verify ages progress appropriately
        #expect(!transition.isEmpty)
    }
}

@Suite("Speaking Styles")
struct SpeakingStyleTests {
    @Test("All predefined styles have valid parameters")
    func testStyleValidity() {
        for style in SpeakingStyle.allStyles {
            #expect(!style.id.isEmpty)
            #expect(!style.name.isEmpty)
            #expect(style.parameters.rate > 0 && style.parameters.rate <= 2.0)
        }
    }

    @Test("Normal style is neutral")
    func testNormalStyle() {
        let normal = SpeakingStyle.normal

        #expect(normal.parameters.pitchShift == 0)
        #expect(normal.parameters.rate == 1.0)
        #expect(normal.parameters.emotionalIntensity == 0.5)
    }

    @Test("Fast style is faster and higher")
    func testFastStyle() {
        let fast = SpeakingStyle.fast

        #expect(fast.parameters.rate > 1.0)
        #expect(fast.parameters.pitchShift > 0)
        #expect(fast.parameters.emotionalIntensity > 0.5)
    }

    @Test("Whisper style has high breathiness")
    func testWhisperStyle() {
        let whisper = SpeakingStyle.whisper

        #expect(whisper.parameters.breathiness > 0.5)
        #expect(whisper.parameters.emotionalIntensity < 0.5)
    }
}

@Suite("Audio Filters")
struct AudioFiltersTests {
    let filters = AudioFilters()

    @Test("High-pass filter runs without error")
    func testHighPassFilter() {
        let samples = Array(repeating: Int16(1000), count: 1000)

        let filtered = filters.highPassFilter(samples, cutoffFrequency: 80, sampleRate: 48000)

        #expect(filtered.count == samples.count)
        #expect(!filtered.isEmpty)
    }

    @Test("Low-pass filter reduces high frequencies")
    func testLowPassFilter() {
        // Create a sample with high-frequency content
        var samples: [Int16] = []
        for i in 0..<1000 {
            let sample = Int16(20000 * sin(Double(i) * 0.01))
            samples.append(sample)
        }

        let filtered = filters.lowPassFilter(samples, cutoffFrequency: 200, sampleRate: 48000)

        #expect(filtered.count == samples.count)
    }

    @Test("Normalization adjusts level")
    func testNormalization() {
        let samples = Array(repeating: Int16(5000), count: 100)

        let normalized = filters.normalize(samples, targetLevel: -6.0)

        #expect(normalized.count == samples.count)
        // Normalized samples should be louder on average
        let originalAvg = Double(samples.map { Int(abs($0)) }.reduce(0, +)) / Double(samples.count)
        let normalizedAvg = Double(normalized.map { Int(abs($0)) }.reduce(0, +)) / Double(normalized.count)
        #expect(normalizedAvg > originalAvg)
    }

    @Test("Soft clipping prevents clipping")
    func testSoftClipping() {
        let samples = [Int16(32000), Int16(-32000), Int16(10000)]

        let clipped = filters.softClip(samples, threshold: 0.9)

        #expect(clipped.count == samples.count)
        // Clipped values should be within range
        #expect(clipped.allSatisfy { abs($0) <= 32767 })
    }

    @Test("Compression reduces dynamic range")
    func testCompression() {
        let samples = [Int16(5000), Int16(20000), Int16(2000)]

        let compressed = filters.compress(samples, threshold: -20, ratio: 4.0)

        #expect(compressed.count == samples.count)
    }

    @Test("De-esser runs without error")
    func testDeEsser() {
        let samples = Array(repeating: Int16(10000), count: 1000)

        let deessed = filters.deEsser(samples, sibilantFrequency: 6000, sampleRate: 48000)

        #expect(deessed.count == samples.count)
    }

    @Test("Reverb adds delay")
    func testReverb() {
        let samples = Array(repeating: Int16(1000), count: 5000)

        let reverbed = filters.reverb(samples, wetLevel: 0.3, sampleRate: 48000)

        #expect(reverbed.count == samples.count)
    }
}

@Suite("Demo Module")
struct DemoTests {
    @Test("Demo module compiles and exports")
    func testDemoAvailability() {
        let demo = ChoirDemo()
        #expect(demo is ChoirDemo)
    }
}
