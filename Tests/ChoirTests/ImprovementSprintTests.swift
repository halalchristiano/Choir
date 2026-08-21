import Foundation
import Testing
@testable import Choir

private actor RecordingAcousticModel: AcousticModelProtocol {
    private var inputs: [AcousticModelInput] = []

    func predict(input: AcousticModelInput) async throws -> AcousticFeatures {
        try input.validate()
        inputs.append(input)
        return AcousticFeatures(features: [[-1, -1], [-1, -1]], frameRate: 50)
    }

    func lastVoiceID() -> Int? { inputs.last?.voiceID }
}

private func validAcousticInput(
    indices: [Int] = [0],
    durations: [Double] = [100],
    f0: [Double] = [120],
    energy: [Double] = [-20],
    stress: [Int] = [0],
    voicing: [Double] = [1],
    voiceID: Int = 0
) -> AcousticModelInput {
    AcousticModelInput(
        phonemeIndices: indices,
        durations: durations,
        fundamentalFrequency: f0,
        energy: energy,
        stress: stress,
        voicing: voicing,
        voiceID: voiceID)
}

@Suite("Improvement sprint: phoneme integrity")
struct PhonemeIntegritySprintTests {
    @Test("ASCII g canonicalizes to IPA script g")
    func asciiGCanonicalizes() {
        #expect(Phoneme("g").symbol == "ɡ")
    }

    @Test("Script g remains unchanged")
    func scriptGRemainsCanonical() {
        #expect(Phoneme("ɡ").symbol == "ɡ")
    }

    @Test("Canonical script g is in the public inventory")
    func scriptGIsInInventory() {
        #expect(PhonemeInventory.isValidIPA(Phoneme("g").symbol))
    }

    @Test("Encoder vocabulary is derived from the inventory")
    func encoderMatchesInventory() {
        #expect(PhonemeEncoder().vocabularySize == PhonemeInventory.all.count)
    }

    @Test("Every inventory phoneme round trips")
    func inventoryRoundTrips() throws {
        let encoder = PhonemeEncoder()
        let phonemes = PhonemeInventory.all.map { Phoneme($0.ipa) }
        let encoded = try encoder.encodeStrict(phonemes)
        #expect(try encoder.decodeStrict(encoded) == phonemes.map(\.symbol))
    }

    @Test("Strict encoding rejects an unknown symbol")
    func strictEncodingRejectsUnknown() {
        do {
            _ = try PhonemeEncoder().encodeStrict([Phoneme("☃")])
            Issue.record("Expected strict encoding to throw")
        } catch let error as ChoirError {
            guard case .invalidParameter(let parameter, _) = error else {
                Issue.record("Wrong ChoirError case")
                return
            }
            #expect(parameter == "phonemes")
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("Unknown symbols are de-duplicated in first-seen order")
    func unknownSymbolsAreDeduplicated() {
        let unknown = PhonemeEncoder().unknownSymbols(
            in: [Phoneme("☃"), Phoneme("x"), Phoneme("☃")])
        #expect(unknown == ["☃", "x"])
    }

    @Test("Strict decoding rejects an unknown index")
    func strictDecodingRejectsUnknown() {
        do {
            _ = try PhonemeEncoder().decodeStrict([-1, 999])
            Issue.record("Expected strict decoding to throw")
        } catch let error as ChoirError {
            guard case .invalidParameter(let parameter, _) = error else {
                Issue.record("Wrong ChoirError case")
                return
            }
            #expect(parameter == "phonemeIndices")
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("Stress clamps below zero")
    func stressClampsLow() {
        #expect(Phoneme("ɑ", stress: -5).stress == 0)
    }

    @Test("Stress clamps above secondary")
    func stressClampsHigh() {
        #expect(Phoneme("ɑ", stress: 8).stress == 2)
    }
}

@Suite("Improvement sprint: voice conditioning")
struct VoiceConditioningSprintTests {
    @Test("All 32 voices have unique conditioning IDs")
    func IDsAreUnique() {
        #expect(Set(Voice.allCases.map(\.conditioningID)).count == 32)
    }

    @Test("Conditioning IDs fill a contiguous model range")
    func IDsAreContiguous() {
        #expect(Voice.allCases.map(\.conditioningID).sorted() == Array(0..<32))
    }

    @Test("First voice retains conditioning ID zero")
    func firstIDStable() {
        #expect(Voice.finch.conditioningID == 0)
    }

    @Test("Default voice has its own conditioning ID")
    func defaultVoiceIDStable() {
        #expect(Voice.isla.conditioningID == 13)
    }

    @Test("Last voice retains conditioning ID 31")
    func lastIDStable() {
        #expect(Voice.hespera.conditioningID == 31)
    }

    @Test("One explicit voice run overrides the request default")
    func singleVoiceRunOverridesDefault() async throws {
        let recorder = RecordingAcousticModel()
        let pipeline = SynthesisPipeline(
            acousticModel: recorder,
            vocoder: MockVocoder())

        _ = try await pipeline.synthesizeMultiVoice(
            text: "<voice id=\"choir.mid.male.garrick\">Hello.</voice>",
            defaultVoice: .isla,
            parameters: SynthesisParameters())

        #expect(await recorder.lastVoiceID() == Voice.garrick.conditioningID)
    }
}

@Suite("Improvement sprint: acoustic tensor validation")
struct AcousticTensorSprintTests {
    @Test("A valid acoustic input passes")
    func validInputPasses() throws {
        try validAcousticInput().validate()
    }

    @Test("Empty acoustic input fails")
    func emptyInputFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(
                indices: [], durations: [], f0: [], energy: [], stress: [], voicing: [])
                .validate()
        }
    }

    @Test("Mismatched tensor lengths fail")
    func mismatchedLengthsFail() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(indices: [0, 1]).validate()
        }
    }

    @Test("Negative phoneme indices fail")
    func negativeIndexFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(indices: [-1]).validate()
        }
    }

    @Test("Zero duration fails")
    func zeroDurationFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(durations: [0]).validate()
        }
    }

    @Test("Negative duration fails")
    func negativeDurationFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(durations: [-1]).validate()
        }
    }

    @Test("Infinite duration fails")
    func infiniteDurationFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(durations: [.infinity]).validate()
        }
    }

    @Test("Negative F0 fails")
    func negativeF0Fails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(f0: [-1]).validate()
        }
    }

    @Test("NaN F0 fails")
    func nanF0Fails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(f0: [.nan]).validate()
        }
    }

    @Test("NaN energy fails")
    func nanEnergyFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(energy: [.nan]).validate()
        }
    }

    @Test("Stress below zero fails")
    func lowStressFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(stress: [-1]).validate()
        }
    }

    @Test("Stress above two fails")
    func highStressFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(stress: [3]).validate()
        }
    }

    @Test("Voicing below zero fails")
    func lowVoicingFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(voicing: [-0.1]).validate()
        }
    }

    @Test("Voicing above one fails")
    func highVoicingFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(voicing: [1.1]).validate()
        }
    }

    @Test("NaN voicing fails")
    func nanVoicingFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(voicing: [.nan]).validate()
        }
    }

    @Test("Negative voice ID fails")
    func negativeVoiceIDFails() {
        #expect(throws: ChoirError.self) {
            try validAcousticInput(voiceID: -1).validate()
        }
    }

    @Test("Rectangular feature matrices report true")
    func rectangularFeatures() {
        #expect(AcousticFeatures(features: [[1, 2], [3, 4]]).isRectangular)
    }

    @Test("Ragged feature matrices report false")
    func raggedFeatures() {
        #expect(!AcousticFeatures(features: [[1], [2, 3]]).isRectangular)
    }

    @Test("Finite feature matrices report true")
    func finiteFeatures() {
        #expect(AcousticFeatures(features: [[1, 2]]).containsOnlyFiniteValues)
    }

    @Test("NaN feature matrices report false")
    func nonFiniteFeatures() {
        #expect(!AcousticFeatures(features: [[.nan]]).containsOnlyFiniteValues)
    }

    @Test("Zero frame rate has safe zero duration")
    func zeroFrameRateIsSafe() {
        #expect(AcousticFeatures(features: [[0]], frameRate: 0).duration == 0)
    }

    @Test("Mock acoustic output is deterministic")
    func mockIsDeterministic() async throws {
        let model = MockAcousticModel()
        let first = try await model.predict(input: validAcousticInput())
        let second = try await model.predict(input: validAcousticInput())
        #expect(first.features == second.features)
    }

    @Test("Mock acoustic configuration clamps invalid dimensions")
    func mockDimensionsClamp() async throws {
        let model = MockAcousticModel(frameRate: 0, frequencyBins: 0)
        let output = try await model.predict(input: validAcousticInput())
        #expect(output.frameRate == 1)
        #expect(output.frequencyBins == 1)
    }

    @Test("Missing Core ML model reports a model-load failure")
    func coreMLFailureIsTyped() async {
        do {
            _ = try await CoreMLAcousticModel().predict(input: validAcousticInput())
            Issue.record("Expected model loading to fail")
        } catch let error as ChoirError {
            guard case .modelLoadFailed = error else {
                Issue.record("Wrong ChoirError case")
                return
            }
        } catch {
            Issue.record("Wrong error type")
        }
    }
}

@Suite("Improvement sprint: audio and streaming validation")
struct AudioAndStreamingSprintTests {
    private let mono = AudioBuffer(
        samples: [0, 1, -1, Int16.max, Int16.min],
        format: AudioFormat())

    @Test("Default audio format validates")
    func defaultFormatValidates() throws {
        try AudioFormat().validate()
    }

    @Test("Low sample rate is rejected")
    func lowSampleRateRejected() {
        #expect(throws: ChoirError.self) { try AudioFormat(sampleRate: 7_999).validate() }
    }

    @Test("Excessive sample rate is rejected")
    func highSampleRateRejected() {
        #expect(throws: ChoirError.self) { try AudioFormat(sampleRate: 384_001).validate() }
    }

    @Test("Zero channels are rejected")
    func zeroChannelsRejected() {
        #expect(throws: ChoirError.self) { try AudioFormat(channels: 0).validate() }
    }

    @Test("More than eight channels are rejected")
    func excessiveChannelsRejected() {
        #expect(throws: ChoirError.self) { try AudioFormat(channels: 9).validate() }
    }

    @Test("Unsupported bit depth is rejected")
    func unsupportedBitDepthRejected() {
        #expect(throws: ChoirError.self) { try AudioFormat(bitDepth: 24).validate() }
    }

    @Test("Invalid audio format produces a safe zero duration")
    func invalidDurationIsSafe() {
        let buffer = AudioBuffer(samples: [1], format: AudioFormat(sampleRate: 0))
        #expect(buffer.duration == 0)
    }

    @Test("Stereo frame count uses interleaved channels")
    func stereoFrameCount() {
        let buffer = AudioBuffer(
            samples: [1, 2, 3, 4],
            format: AudioFormat(channels: 2))
        #expect(buffer.frameCount == 2)
    }

    @Test("WAV export returns the WAV output case")
    func engineExportsWAV() async throws {
        let output = try await ChoirEngine().exportAudio(mono, format: .wav)
        guard case .wav(let data) = output else {
            Issue.record("Expected WAV output")
            return
        }
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
    }

    @Test("WAV rejects incomplete interleaved frames")
    func wavRejectsIncompleteFrames() {
        let buffer = AudioBuffer(samples: [1, 2, 3], format: AudioFormat(channels: 2))
        #expect(throws: ChoirError.self) { try AudioEncoder().encodeWAV(buffer) }
    }

    @Test("MP3 fails explicitly instead of returning empty data")
    func mp3FailsExplicitly() {
        #expect(throws: ChoirError.self) { try AudioEncoder().encodeMP3(mono) }
    }

    @Test("AAC fails explicitly instead of returning empty data")
    func aacFailsExplicitly() {
        #expect(throws: ChoirError.self) { try AudioEncoder().encodeAAC(mono) }
    }

    @Test("FLAC fails explicitly instead of returning empty data")
    func flacFailsExplicitly() {
        #expect(throws: ChoirError.self) { try AudioEncoder().encodeFLAC(mono) }
    }

    @Test("Codec bitrate below range is rejected")
    func lowBitrateRejected() {
        #expect(throws: ChoirError.self) { try AudioEncoder().encodeMP3(mono, quality: 7) }
    }

    @Test("Codec bitrate above range is rejected")
    func highBitrateRejected() {
        #expect(throws: ChoirError.self) { try AudioEncoder().encodeAAC(mono, quality: 321) }
    }

    @Test("Default streaming options validate")
    func defaultStreamingOptionsValidate() throws {
        try StreamingOptions().validate()
    }

    @Test("Zero streaming chunk size is rejected")
    func zeroChunkRejected() {
        #expect(throws: ChoirError.self) { try StreamingOptions(chunkSize: 0).validate() }
    }

    @Test("Negative streaming chunk size is rejected")
    func negativeChunkRejected() {
        #expect(throws: ChoirError.self) { try StreamingOptions(chunkSize: -1).validate() }
    }
}

@Suite("Improvement sprint: cache correctness")
struct CacheCorrectnessSprintTests {
    private func transcription(_ count: Int = 1) -> PhoneticTranscription {
        PhoneticTranscription(
            phonemes: Array(repeating: Phoneme("ɑ"), count: count),
            originalText: "test")
    }

    private func prosody(_ count: Int = 1) -> ProsodyDescription {
        ProsodyDescription(
            phonemes: Array(repeating: AnnotatedPhoneme(phoneme: Phoneme("ɑ")), count: count),
            pitchContour: ProsodyContour(points: []),
            energyContour: ProsodyContour(points: []),
            durations: Array(repeating: 100, count: count))
    }

    @Test("Replacing features does not double-count size")
    func featureReplacementAccounting() async {
        let cache = AssetCache(maxCacheSize: 1_000)
        await cache.cacheAcousticFeatures(
            AcousticFeatures(features: [[0, 0], [0, 0]]), for: "same")
        await cache.cacheAcousticFeatures(
            AcousticFeatures(features: [[0]]), for: "same")
        #expect(await cache.getStatistics().currentSizeBytes == 4)
    }

    @Test("Replacing transcription does not double-count size")
    func transcriptionReplacementAccounting() async {
        let cache = AssetCache(maxCacheSize: 1_000)
        await cache.cacheTranscription(transcription(3), for: "same")
        await cache.cacheTranscription(transcription(1), for: "same")
        #expect(await cache.getStatistics().currentSizeBytes == 64)
    }

    @Test("Replacing prosody does not double-count size")
    func prosodyReplacementAccounting() async {
        let cache = AssetCache(maxCacheSize: 1_000)
        await cache.cacheProsody(prosody(3), for: "same")
        await cache.cacheProsody(prosody(1), for: "same")
        #expect(await cache.getStatistics().currentSizeBytes == 128)
    }

    @Test("Transcription-only cache can evict")
    func transcriptionOnlyEvicts() async {
        let cache = AssetCache(maxCacheSize: 64)
        await cache.cacheTranscription(transcription(), for: "first")
        await cache.cacheTranscription(transcription(), for: "second")
        let stats = await cache.getStatistics()
        #expect(stats.transcriptionCount == 1)
        #expect(stats.currentSizeBytes == 64)
    }

    @Test("Prosody-only cache can evict")
    func prosodyOnlyEvicts() async {
        let cache = AssetCache(maxCacheSize: 128)
        await cache.cacheProsody(prosody(), for: "first")
        await cache.cacheProsody(prosody(), for: "second")
        let stats = await cache.getStatistics()
        #expect(stats.prosodyCount == 1)
        #expect(stats.currentSizeBytes == 128)
    }

    @Test("Oversized features are not cached")
    func oversizedFeaturesRejected() async {
        let cache = AssetCache(maxCacheSize: 4)
        await cache.cacheAcousticFeatures(
            AcousticFeatures(features: [[0, 0], [0, 0]]), for: "large")
        #expect(await cache.getStatistics().isEmpty)
    }

    @Test("Oversized transcription is not cached")
    func oversizedTranscriptionRejected() async {
        let cache = AssetCache(maxCacheSize: 63)
        await cache.cacheTranscription(transcription(), for: "large")
        #expect(await cache.getStatistics().isEmpty)
    }

    @Test("Oversized prosody is not cached")
    func oversizedProsodyRejected() async {
        let cache = AssetCache(maxCacheSize: 127)
        await cache.cacheProsody(prosody(), for: "large")
        #expect(await cache.getStatistics().isEmpty)
    }

    @Test("Negative capacity clamps to zero")
    func negativeCapacityClamps() async {
        let cache = AssetCache(maxCacheSize: -1)
        await cache.cacheTranscription(transcription(), for: "entry")
        let stats = await cache.getStatistics()
        #expect(stats.maxSizeBytes == 0)
        #expect(stats.isEmpty)
    }

    @Test("Remaining capacity is reported")
    func remainingCapacityReported() async {
        let cache = AssetCache(maxCacheSize: 100)
        await cache.cacheTranscription(transcription(), for: "entry")
        #expect(await cache.getStatistics().remainingCapacityBytes == 36)
    }

    @Test("Utilization is bounded at zero for zero capacity")
    func zeroCapacityUtilization() async {
        let stats = await AssetCache(maxCacheSize: 0).getStatistics()
        #expect(stats.utilizationPercent == 0)
    }

    @Test("Clear resets counts, bytes, and emptiness")
    func clearResetsEverything() async {
        let cache = AssetCache(maxCacheSize: 1_000)
        await cache.cacheTranscription(transcription(), for: "entry")
        await cache.clear()
        let stats = await cache.getStatistics()
        #expect(stats.isEmpty)
        #expect(stats.currentSizeBytes == 0)
        #expect(stats.remainingCapacityBytes == 1_000)
    }
}

@Suite("Improvement sprint: engine lifecycle and errors")
struct EngineLifecycleSprintTests {
    @Test("Clear cache releases the initialized pipeline")
    func clearCacheUninitializes() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()
        await engine.clearCache()
        #expect(await engine.getState() == .uninitialized)
    }

    @Test("Engine can initialize again after clearing")
    func reinitializeAfterClear() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()
        await engine.clearCache()
        try await engine.initialize()
        #expect(await engine.getState() == .ready)
    }

    @Test("Invalid format puts initialization into a typed error state")
    func invalidFormatFailsInitialization() async {
        let engine = ChoirEngine(audioFormat: AudioFormat(sampleRate: 0))
        do {
            try await engine.initialize()
            Issue.record("Expected initialization to fail")
        } catch let error as ChoirError {
            guard case .invalidParameter = error else {
                Issue.record("Wrong ChoirError case")
                return
            }
            #expect(await engine.getState() == .error(error))
        } catch {
            Issue.record("Wrong error type")
        }
    }

    @Test("Busy error has a stable code")
    func busyCodeStable() {
        #expect(ChoirError.engineBusy.code == "CHOIR-1010")
    }

    @Test("Busy error is retryable")
    func busyIsRetryable() {
        #expect(ChoirError.engineBusy.isRetryable)
    }

    @Test("Busy error has actionable recovery guidance")
    func busyHasRecoverySuggestion() {
        #expect(!(ChoirError.engineBusy.recoverySuggestion ?? "").isEmpty)
    }

    @Test("Busy error description is distinct from not initialized")
    func busyDescriptionDistinct() {
        #expect(ChoirError.engineBusy.errorDescription != ChoirError.notInitialized.errorDescription)
    }
}
