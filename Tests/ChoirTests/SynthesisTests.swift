import Testing
@testable import Choir

/// Helper actor for collecting chunks in tests.
actor ChunkCounter {
    private var chunks: [AudioChunk] = []

    func addChunk(_ chunk: AudioChunk) {
        chunks.append(chunk)
    }

    func getResults() -> [AudioChunk] {
        chunks
    }
}

@Suite("Prosody Prediction")
struct ProsodyPredictorTests {
    let predictor = ProsodyPredictor()

    @Test("Predicts durations for phonemes")
    func testDurationPrediction() {
        let phonemes = [
            Phoneme("h"),
            Phoneme("ə"),
            Phoneme("l"),
            Phoneme("oʊ", stress: 1),
        ]
        let transcript = PhoneticTranscription(phonemes: phonemes, originalText: "hello")
        let params = SynthesisParameters()

        let prosody = predictor.predictProsody(for: transcript, with: params)

        #expect(prosody.durations.count == phonemes.count)
        #expect(prosody.durations.allSatisfy { $0 > 0 })
        // Stressed vowel should be longer
        #expect(prosody.durations[3] > prosody.durations[2])
    }

    @Test("Predicts pitch contour")
    func testPitchContourPrediction() {
        let phonemes = [
            Phoneme("h"),
            Phoneme("ə"),
            Phoneme("l"),
            Phoneme("oʊ", stress: 1),
        ]
        let transcript = PhoneticTranscription(phonemes: phonemes, originalText: "hello")
        let params = SynthesisParameters()

        let prosody = predictor.predictProsody(for: transcript, with: params)

        #expect(!prosody.pitchContour.points.isEmpty)
        // Pitch should be within range
        for point in prosody.pitchContour.points {
            #expect(point.value >= 50 && point.value <= 400)
        }
    }

    @Test("Applies rate adjustment")
    func testRateAdjustment() {
        let phonemes = [
            Phoneme("h"),
            Phoneme("ə"),
            Phoneme("l"),
            Phoneme("oʊ"),
        ]
        let transcript = PhoneticTranscription(phonemes: phonemes, originalText: "hello")

        let slowParams = SynthesisParameters(rate: 0.8)
        let fastParams = SynthesisParameters(rate: 1.5)

        let slowProsody = predictor.predictProsody(for: transcript, with: slowParams)
        let fastProsody = predictor.predictProsody(for: transcript, with: fastParams)

        // Slow speech should have longer durations
        #expect(slowProsody.totalDuration > fastProsody.totalDuration)
    }

    @Test("Applies emotional intensity")
    func testEmotionalIntensity() {
        let phonemes = [
            Phoneme("h"),
            Phoneme("ə"),
            Phoneme("l"),
            Phoneme("oʊ"),
        ]
        let transcript = PhoneticTranscription(phonemes: phonemes, originalText: "hello")

        let neutralParams = SynthesisParameters(emotionalIntensity: 0.0)
        let intenseParams = SynthesisParameters(emotionalIntensity: 1.0)

        let neutralProsody = predictor.predictProsody(for: transcript, with: neutralParams)
        let intenseProsody = predictor.predictProsody(for: transcript, with: intenseParams)

        // Intense emotion should have higher pitch
        let neutralPitch = neutralProsody.pitchContour.points.first?.value ?? 0
        let intensePitch = intenseProsody.pitchContour.points.first?.value ?? 0
        #expect(intensePitch > neutralPitch)
    }
}

@Suite("Acoustic Model")
struct AcousticModelTests {
    @Test("PhonemeEncoder encodes and decodes")
    func testPhonemeEncoder() {
        let encoder = PhonemeEncoder()

        let phonemes = [Phoneme("h"), Phoneme("ə"), Phoneme("l")]
        let encoded = encoder.encode(phonemes)
        let decoded = encoder.decode(encoded)

        #expect(encoded.count == phonemes.count)
        #expect(decoded.count == phonemes.count)
        #expect(decoded[0] == "h")
        #expect(decoded[1] == "ə")
        #expect(decoded[2] == "l")
    }

    @Test("PhonemeEncoder has reasonable vocab size")
    func testPhonemeEncoderVocabSize() {
        let encoder = PhonemeEncoder()
        #expect(encoder.vocabularySize > 30)
    }

    @Test("MockAcousticModel generates features")
    func testMockAcousticModel() async throws {
        let model = MockAcousticModel()

        let input = AcousticModelInput(
            phonemeIndices: [0, 1, 2],
            durations: [50, 100, 50],
            fundamentalFrequency: [120, 130, 120],
            energy: [-20, -15, -20],
            stress: [0, 1, 0],
            voicing: [0, 1, 0]
        )

        let features = try await model.predict(input: input)

        #expect(features.frameCount > 0)
        #expect(features.frequencyBins > 0)
        #expect(features.duration > 0)
    }
}

@Suite("Vocoder")
struct VocoderTests {
    @Test("MockVocoder generates waveform")
    func testMockVocoder() async throws {
        let vocoder = MockVocoder()
        let features = AcousticFeatures(features: Array(repeating: Array(repeating: Float(0), count: 80), count: 100))

        let samples = try await vocoder.synthesize(features: features, sampleRate: 48000)

        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0 >= -32768 && $0 <= 32767 })
    }

    @Test("Vocoder produces realistic duration")
    func testVocoderDuration() async throws {
        let vocoder = MockVocoder()
        let featureCount = 100
        let frameRate = 50
        let expectedDuration = Double(featureCount) / Double(frameRate)

        let features = AcousticFeatures(
            features: Array(repeating: Array(repeating: Float(0), count: 80), count: featureCount),
            frameRate: frameRate
        )

        let samples = try await vocoder.synthesize(features: features, sampleRate: 48000)
        let actualDuration = Double(samples.count) / 48000.0

        #expect(abs(actualDuration - expectedDuration) < 0.1)
    }
}

@Suite("Synthesis Pipeline")
struct SynthesisPipelineTests {
    let pipeline = SynthesisPipeline()

    @Test("Pipeline orchestrates all stages")
    func testPipelineOrchestration() async throws {
        let audio = try await pipeline.synthesize(
            text: "Hello world",
            voice: .isla,
            parameters: SynthesisParameters()
        )

        #expect(!audio.samples.isEmpty)
        #expect(audio.samples.allSatisfy { $0 >= -32768 && $0 <= 32767 })
    }

    @Test("Pipeline handles SSML markup")
    func testPipelineSSML() async throws {
        let ssml = "Hello <prosody pitch=\"+5\">world</prosody>"
        let audio = try await pipeline.synthesize(
            text: ssml,
            voice: .orion,
            parameters: SynthesisParameters()
        )

        #expect(!audio.samples.isEmpty)
    }

    @Test("Pipeline respects synthesis parameters")
    func testPipelineParameters() async throws {
        let params = SynthesisParameters(
            pitchShift: 5,
            rate: 1.2,
            emotionalIntensity: 0.8
        )

        let audio = try await pipeline.synthesize(
            text: "Test",
            voice: .lyra,
            parameters: params
        )

        #expect(!audio.samples.isEmpty)
    }
}

@Suite("ChoirEngine Full Integration")
struct ChoirEngineIntegrationTests {
    @Test("Engine initializes and synthesizes")
    func testEngineFullPipeline() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let state = await engine.getState()
        #expect(state == .ready)

        let audio = try await engine.synthesize(
            text: "The quick brown fox",
            voice: .garrick,
            parameters: SynthesisParameters()
        )

        #expect(!audio.samples.isEmpty)
        #expect(audio.format.sampleRate == 48000)
    }

    @Test("Engine handles streaming synthesis")
    func testEngineStreaming() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let chunkCounter = ChunkCounter()

        try await engine.streamSynthesis(
            text: "Hello world",
            voice: .lyra,
            parameters: SynthesisParameters(),
            options: StreamingOptions(),
            onChunk: { chunk in
                await chunkCounter.addChunk(chunk)
            }
        )

        let results = await chunkCounter.getResults()
        #expect(results.count > 0)
        #expect(results.reduce(0) { $0 + $1.samples.count } > 0)
    }

    @Test("Engine rejects synthesis before initialization")
    func testEngineUninitialized() async throws {
        let engine = ChoirEngine()

        do {
            _ = try await engine.synthesize(
                text: "Test",
                voice: .isla
            )
            #expect(Bool(false), "Should reject uninitialized engine")
        } catch ChoirError.notInitialized {
            // Expected
        }
    }
}
