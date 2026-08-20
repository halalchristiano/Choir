import Testing
@testable import Choir

@Suite("Choir Package Tests")
struct ChoirTests {
    @Test("Package version is defined")
    func testPackageVersion() {
        #expect(!Choir.version.isEmpty)
    }

    @Test("All voices are accessible")
    func testVoiceEnumeration() {
        #expect(Voice.allCases.count == 32)

        for voice in Voice.allCases {
            #expect(!voice.displayName.isEmpty)
            #expect(voice.ageBand.ordinal >= 1 && voice.ageBand.ordinal <= 4)
        }
    }

    @Test("Villain voices are correctly identified")
    func testVillainVoices() {
        // SRS VOX-V-001 requires exactly eight villains, one per
        // (age band x gender) cell. This previously asserted six, which
        // matched the pre-SRS voice roster rather than the specification.
        let villainVoices = Voice.allCases.filter { $0.isVillain }
        #expect(villainVoices.count == 8)
    }

    @Test("Synthesis parameters are clamped correctly")
    func testSynthesisParameterClamping() {
        let params = SynthesisParameters(
            pitchShift: 100,
            rate: 0.1,
            emotionalIntensity: 2.0,
            breathiness: -1.0,
            ageShift: 10,
            genderShift: 2.0
        )

        #expect(params.pitchShift == 12)
        #expect(params.rate == 0.5)
        #expect(params.emotionalIntensity == 1.0)
        #expect(params.breathiness == 0.0)
        #expect(params.ageShift == 5)
        #expect(params.genderShift == 1.0)
    }

    @Test("Audio format can be created")
    func testAudioFormat() {
        let format = AudioFormat(sampleRate: 48000, channels: 1, bitDepth: 16)
        #expect(format.sampleRate == 48000)
        #expect(format.channels == 1)
        #expect(format.bitDepth == 16)
    }

    @Test("Audio buffer duration is calculated correctly")
    func testAudioBufferDuration() {
        let format = AudioFormat(sampleRate: 48000)
        let samples = Array(repeating: Int16(0), count: 48000)
        let buffer = AudioBuffer(samples: samples, format: format)

        #expect(buffer.duration == 1.0)
    }

    @Test("Choir engine can be created")
    func testEngineCreation() async {
        let engine = ChoirEngine()
        let state = await engine.getState()
        #expect(state == .uninitialized)
    }
}
