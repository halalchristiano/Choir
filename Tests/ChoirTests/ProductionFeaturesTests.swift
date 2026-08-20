import Testing
@testable import Choir

@Suite("Pronunciation Dictionary")
struct PronunciationDictionaryTests {
    @Test("Adds and retrieves entries")
    func testAddAndRetrieve() {
        var dict = PronunciationDictionary()
        let entry = PronunciationDictionary.Entry(
            word: "choir",
            phonemes: [Phoneme("k"), Phoneme("w"), Phoneme("aɪ")]
        )

        dict.add(entry)
        let retrieved = dict.lookup("choir")

        #expect(retrieved != nil)
        #expect(retrieved?.count == 3)
    }

    @Test("Case-insensitive lookup")
    func testCaseInsensitivity() {
        var dict = PronunciationDictionary()
        let entry = PronunciationDictionary.Entry(
            word: "CHOIR",
            phonemes: [Phoneme("k"), Phoneme("w"), Phoneme("aɪ")]
        )

        dict.add(entry)
        let retrieved = dict.lookup("choir")

        #expect(retrieved != nil)
    }

    @Test("Supports POS disambiguation")
    func testPOSDisambiguation() {
        var dict = PronunciationDictionary()

        dict.add(PronunciationDictionary.Entry(
            word: "read",
            phonemes: [Phoneme("r"), Phoneme("ɛ"), Phoneme("d")],
            partOfSpeech: "verb"
        ))

        dict.add(PronunciationDictionary.Entry(
            word: "read",
            phonemes: [Phoneme("r"), Phoneme("iː"), Phoneme("d")],
            partOfSpeech: "adjective"
        ))

        let verb = dict.lookup("read", partOfSpeech: "verb")
        let adj = dict.lookup("read", partOfSpeech: "adjective")

        #expect(verb != nil)
        #expect(adj != nil)
    }

    @Test("Standard dictionary loads")
    func testStandardDictionary() {
        let dict = PronunciationDictionary.standard

        #expect(dict.contains("iOS"))
        #expect(dict.contains("macOS"))
        #expect(dict.count > 0)
    }
}

@Suite("Audio Effect Chain")
struct AudioEffectChainTests {
    @Test("Chains effects in order")
    func testEffectChaining() {
        let chain = AudioEffectChain()
            .add(AudioEffect(name: "HiPass", kind: .highPass(cutoffHz: 80)))
            .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -6.0)))

        #expect(chain.description.contains("HiPass"))
        #expect(chain.description.contains("Normalize"))
    }

    @Test("Processes audio through chain")
    func testChainProcessing() {
        let samples = Array(repeating: Int16(5000), count: 1000)
        let chain = AudioEffectChain()
            .add(AudioEffect(name: "Normalize", kind: .normalize(targetLevel: -6.0)))

        let processed = chain.process(samples)

        #expect(processed.count == samples.count)
    }

    @Test("Preset chains are valid")
    func testPresetChains() {
        let chains = [
            AudioEffectChain.standardMastering,
            AudioEffectChain.podcast,
            AudioEffectChain.warmth,
            AudioEffectChain.clean,
            AudioEffectChain.voiceClarity
        ]

        for chain in chains {
            let samples = Array(repeating: Int16(1000), count: 1000)
            let processed = chain.process(samples)
            #expect(processed.count == samples.count)
        }
    }
}

@Suite("Synthesis Session")
struct SynthesisSessionTests {
    @Test("Creates session with configuration")
    func testSessionCreation() async {
        let session = SynthesisSession(voice: .lyra)

        let state = await session.getState()
        if case .idle = state {
            #expect(true)
        } else {
            #expect(false, "State should be idle")
        }
    }

    @Test("Caches audio")
    func testAudioCaching() async {
        let session = SynthesisSession()
        let audio = AudioBuffer(samples: Array(repeating: Int16(0), count: 100), format: AudioFormat())

        await session.cacheAudio(audio, for: "test")
        let retrieved = await session.getCachedAudio(for: "test")

        #expect(retrieved != nil)
    }

    @Test("Records synthesis completion")
    func testSynthesisRecording() async {
        let session = SynthesisSession()
        let audio = AudioBuffer(samples: Array(repeating: Int16(0), count: 100), format: AudioFormat())

        await session.recordSynthesis(text: "test", audio: audio)
        let state = await session.getState()

        if case .completed = state {
            #expect(true)
        } else {
            #expect(false, "State should be completed")
        }
    }

    @Test("Provides session statistics")
    func testSessionStatistics() async {
        let session = SynthesisSession()

        let stats = await session.getStatistics()

        #expect(stats.cacheSize >= 0)
        #expect(stats.cachedItemCount >= 0)
    }
}

@Suite("Session Manager")
struct SynthesisSessionManagerTests {
    @Test("Creates and retrieves sessions")
    func testSessionManagement() async {
        let manager = SynthesisSessionManager()

        let session = await manager.createSession(voice: .garrick)
        let retrieved = await manager.getSession(session.id)

        #expect(retrieved != nil)
    }

    @Test("Tracks active sessions")
    func testActiveSessions() async {
        let manager = SynthesisSessionManager()

        let s1 = await manager.createSession()
        let s2 = await manager.createSession()

        let active = await manager.getActiveSessions()

        #expect(active.count == 2)
    }
}

@Suite("Real-Time Controller")
struct RealTimeControllerTests {
    @Test("Updates parameters")
    func testParameterUpdates() async {
        let controller = RealTimeController()

        await controller.setPitchShift(5.0)
        await controller.setRate(1.5)

        let params = await controller.getParameters()

        #expect(params.pitchShift == 5.0)
        #expect(params.rate == 1.5)
    }

    @Test("Clamps values")
    func testValueClamping() async {
        let controller = RealTimeController()

        await controller.setPitchShift(100)  // Should clamp to 12
        await controller.setRate(5.0)  // Should clamp to 2.0

        let params = await controller.getParameters()

        #expect(params.pitchShift == 12)
        #expect(params.rate == 2.0)
    }

    @Test("Tracks parameter history")
    func testHistory() async {
        let controller = RealTimeController()

        await controller.setPitchShift(2.0)
        await controller.setPitchShift(4.0)

        let history = await controller.getHistory()

        #expect(history.count >= 2)
    }

    @Test("Parameter ramping")
    func testParameterRamp() {
        let ramp = ParameterRamp(
            parameter: "pitch",
            from: 0.0,
            to: 10.0,
            duration: 1.0,
            curve: .linear
        )

        let start = ramp.currentValue

        #expect(start >= 0.0 && start <= 10.0)
    }
}

@Suite("Voice Quality Metrics")
struct VoiceQualityTests {
    let analyzer = VoiceQualityAnalyzer()

    @Test("Analyzes audio quality")
    func testQualityAnalysis() {
        let samples = Array(repeating: Int16(5000), count: 48000)

        let metrics = analyzer.analyzeQuality(samples, sampleRate: 48000)

        #expect(metrics.peakLevel > 0)
        #expect(metrics.rmsLoudness < 0)
    }

    @Test("Rates quality")
    func testQualityRating() {
        let samples = Array(repeating: Int16(5000), count: 48000)
        let metrics = analyzer.analyzeQuality(samples, sampleRate: 48000)

        let rating = analyzer.rateQuality(metrics)

        #expect(rating >= 1.0 && rating <= 5.0)
    }

    @Test("Generates quality report")
    func testQualityReport() {
        let samples = Array(repeating: Int16(5000), count: 48000)
        let report = analyzer.generateReport(samples, sampleRate: 48000)

        #expect(!report.summary.isEmpty)
        #expect(report.ratingStars.count > 0)
    }

    @Test("Detects clipping")
    func testClippingDetection() {
        var samples: [Int16] = []
        for _ in 0..<100 {
            samples.append(32700)  // Near max
        }

        let metrics = analyzer.analyzeQuality(samples, sampleRate: 48000)

        #expect(metrics.clippingPercent > 0)
    }
}
