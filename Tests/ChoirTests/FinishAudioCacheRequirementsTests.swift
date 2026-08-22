import Foundation
import Testing
@testable import Choir

@Suite("Finish remaining audio and cache requirements")
struct FinishAudioCacheRequirementsTests {
    @Test("AUD-001 exposes native float PCM as samples and little-endian Data")
    func nativeFloatPCMForms() throws {
        let buffer = FloatAudioBuffer(samples: [0, 1, -1])
        try buffer.validateNativeFormat()
        #expect(buffer.isNativeFormat)
        #expect(buffer.frameCount == 3)
        #expect(buffer.interleavedData.count == 12)
        #expect(Array(buffer.interleavedData[4..<8]) == [0, 0, 128, 63])
        let integer = try buffer.int16PCM(dither: false)
        #expect(integer.samples == [0, .max, .min])
    }

    @Test("AUD-002 resamples to every required rate and converts to int16")
    func highQualitySampleConversion() throws {
        let samples = (0..<480).map { index in
            Float(sin(2 * Double.pi * 1_000 * Double(index) / 48_000) * 0.5)
        }
        let source = FloatAudioBuffer(samples: samples)
        let converter = AudioSampleConverter()
        for rate in AudioSampleConverter.requiredOutputSampleRates {
            let converted = try converter.resample(source, to: rate)
            #expect(converted.sampleRate == rate)
            #expect(abs(converted.duration - source.duration) < 1 / Double(rate))
            #expect(converted.samples.contains { abs($0) > 0.1 })
            #expect(try converted.int16PCM().format.bitDepth == 16)
        }
    }

    @Test("AUD-002 48-to-16 kHz conversion rejects the alias band by at least 100 dB")
    func resamplerStopbandRejection() throws {
        let inputRate = 48_000
        let outputRate = 16_000
        let toneFrequency = 8_500.0
        let inputSamples = (0..<6_000).map { index in
            Float(sin(
                2 * Double.pi * toneFrequency * Double(index) / Double(inputRate)))
        }
        let output = try AudioSampleConverter().resample(
            FloatAudioBuffer(samples: inputSamples, sampleRate: inputRate),
            to: outputRate)

        // Ignore both filter transients. At 48-to-16 kHz, 100 output frames
        // cover more than the 192-input-frame kernel radius on each edge.
        let trimCount = 100
        #expect(output.samples.count > trimCount * 2)
        let settledSamples = Array(
            output.samples[trimCount..<(output.samples.count - trimCount)])
        let inputEnergy = inputSamples.reduce(0.0) { sum, sample in
            sum + Double(sample) * Double(sample)
        }
        let outputEnergy = settledSamples.reduce(0.0) { sum, sample in
            sum + Double(sample) * Double(sample)
        }
        let inputRMS = sqrt(inputEnergy / Double(inputSamples.count))
        let outputRMS = sqrt(outputEnergy / Double(settledSamples.count))
        let attenuationDB = 20 * log10(
            max(outputRMS / inputRMS, Double.leastNonzeroMagnitude))

        #expect(
            attenuationDB <= -100,
            "Stopband attenuation was \(attenuationDB) dB")
    }

    @Test("AUD-002 resampling rejects oversized expansion before allocation")
    func resamplerChecksOutputAllocationBounds() {
        let source = FloatAudioBuffer(
            samples: Array(repeating: 0, count: 700_000), sampleRate: 8_000)
        #expect(throws: ChoirError.outOfMemory) {
            try AudioSampleConverter().resample(source, to: 384_000)
        }
    }

    @Test("AUD-020/021 mastering removes DC, fades edges, and respects true peak")
    func loudnessAndClicklessMastering() throws {
        let samples = (0..<48_000).map { index -> Float in
            Float((index.isMultiple(of: 2) ? 0.05 : -0.05) + 0.01)
        }
        let result = try AudioMasterer().master(FloatAudioBuffer(samples: samples))
        #expect(result.audio.samples.first == 0)
        #expect(result.audio.samples.last == 0)
        #expect(result.report.outputDCOffsetDBFS <= -60 || !result.report.outputDCOffsetDBFS.isFinite)
        #expect(result.report.outputTruePeakDBTP <= -0.95)
        #expect(abs(result.report.outputIntegratedLUFS - (-16)) <= 0.6)
    }

    @Test("AUD-022 broadcast chain is opt-in and contains the required stages")
    func broadcastMasteringPreset() throws {
        let chain = AudioEffectChain.broadcast
        try chain.validate()
        #expect(chain.effectNames == [
            "DC Block", "40 Hz High Pass", "De-esser", "Soft-knee Limiter", "Clickless Edges",
        ])
        let output = chain.process(Array(repeating: Int16(1_000), count: 480))
        #expect(output.first == 0)
        #expect(output.last == 0)
    }

    @Test("AUD-022 broadcast mastering is an opt-in production export preset")
    func broadcastMasteringExportPreset() async throws {
        let audio = AudioBuffer(
            samples: Array(repeating: 1_000, count: 480),
            format: AudioFormat(sampleRate: 8_000))
        let engine = ChoirEngine(audioFormat: audio.format)
        guard case .wav(let unprocessed) = try await engine.exportAudio(
            audio, format: .wav),
              case .wav(let broadcast) = try await engine.exportAudio(
                audio, format: .wav, preset: .broadcast) else {
            Issue.record("Expected WAV output")
            return
        }

        #expect(readInt16LE(unprocessed, offset: AudioEncoder.wavHeaderSize) == 1_000)
        #expect(readInt16LE(broadcast, offset: AudioEncoder.wavHeaderSize) == 0)
        #expect(readInt16LE(broadcast, offset: broadcast.count - 2) == 0)
        #expect(unprocessed != broadcast)
    }

    @Test("AUD-011 WAV exports tags, chapters, and a correct RIFF size")
    func wavMetadataAndChapters() throws {
        let audio = AudioBuffer(
            samples: Array(repeating: 0, count: 8_000),
            format: AudioFormat(sampleRate: 8_000))
        let metadata = AudioFileMetadata(
            title: "Opening",
            artist: "Choir",
            voice: "Maeve",
            chapters: [AudioChapterMark(title: "Part II", startTimeSeconds: 0.5)])
        let data = try AudioEncoder().encodeWAV(audio, metadata: metadata)
        #expect(data.range(of: Data("INAM".utf8)) != nil)
        #expect(data.range(of: Data("IART".utf8)) != nil)
        #expect(data.range(of: Data("cue ".utf8)) != nil)
        #expect(data.range(of: Data("Part II".utf8)) != nil)
        #expect(Int(readUInt32LE(data, offset: 4)) + 8 == data.count)
        #expect(try AudioEncoder().estimatedWAVByteCount(for: audio, metadata: metadata) == data.count)
    }

    @Test("AUD-040 exports per-line WAV, JSON, SRT, and WebVTT")
    func timelineArtifacts() throws {
        let line = TimelineAudioLine(
            fileName: "line-001",
            audio: AudioBuffer(
                samples: Array(repeating: 0, count: 1_600),
                format: AudioFormat(sampleRate: 8_000)),
            words: [TimedSpan(content: "In", startMs: 25, endMs: 65),
                    TimedSpan(content: "principio", startMs: 65, endMs: 125)])
        let bundle = try TimelineAudioExporter().export([line])
        #expect(bundle.audioFiles.map(\.name) == ["line-001.wav"])
        #expect(bundle.srt.contains("00:00:00,025 --> 00:00:00,125"))
        #expect(!bundle.srt.contains("00:00:00,000 --> 00:00:00,200"))
        #expect(bundle.srt.contains("In principio"))
        #expect(bundle.webVTT.hasPrefix("WEBVTT"))
        let decoded = try JSONDecoder().decode([TimelineSidecarEntry].self, from: bundle.timingJSON)
        #expect(decoded.first?.file == "line-001.wav")
        #expect(decoded.first?.wordTimings.count == 2)
    }

    @Test("AUD-040 rejects malformed or overlapping decoded word timings")
    func timelineRejectsInvalidWordTimings() throws {
        let audio = AudioBuffer(
            samples: Array(repeating: 0, count: 800),
            format: AudioFormat(sampleRate: 8_000))
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN")
        let malformed = try [
            #"{"content":"negative","startMs":-1,"endMs":20}"#,
            #"{"content":"reversed","startMs":40,"endMs":20}"#,
            #"{"content":"nonfinite","startMs":"NaN","endMs":20}"#,
        ].map { json in
            try decoder.decode(TimedSpan.self, from: Data(json.utf8))
        }
        let invalidTimelines = malformed.map { [$0] } + [[
            TimedSpan(content: "first", startMs: 0, endMs: 60),
            TimedSpan(content: "overlap", startMs: 50, endMs: 100),
        ]]

        for words in invalidTimelines {
            #expect(throws: ChoirError.self) {
                try TimelineAudioExporter().export([
                    TimelineAudioLine(fileName: "invalid", audio: audio, words: words),
                ])
            }
        }
    }

    @Test("CCH-002 memory cache pinning protects app-critical keys from LRU")
    func inMemoryPinningAndLimitChanges() async throws {
        let cache = AssetCache(maxCacheSize: 128)
        let transcript = PhoneticTranscription(
            phonemes: [Phoneme("a")], originalText: "a")
        await cache.cacheTranscription(transcript, for: "pinned")
        #expect(await cache.pin("pinned"))
        await cache.cacheTranscription(transcript, for: "old")
        await cache.cacheTranscription(transcript, for: "new")
        #expect(await cache.getTranscription(for: "pinned") != nil)
        #expect(await cache.getTranscription(for: "old") == nil)
        #expect(await cache.getTranscription(for: "new") != nil)
        #expect(await cache.getStatistics().pinnedKeyCount == 1)

        do {
            try await cache.setMaximumCacheSize(63)
            Issue.record("Expected a limit below pinned data to fail")
        } catch let error as ChoirError {
            guard case .invalidParameter = error else {
                Issue.record("Unexpected cache-limit error: \(error)")
                return
            }
        }
    }

    @Test("CCH-001 keys are deterministic and include every synthesis input")
    func contentAddressedKeys() {
        let first = SynthesisCacheKey(
            text: "In the beginning", voice: .maeve,
            parameters: SynthesisParameters(seed: 7), engineVersion: 3)
        let repeated = SynthesisCacheKey(
            text: "In the beginning", voice: .maeve,
            parameters: SynthesisParameters(seed: 7), engineVersion: 3)
        let changedVersion = SynthesisCacheKey(
            text: "In the beginning", voice: .maeve,
            parameters: SynthesisParameters(seed: 7), engineVersion: 4)
        #expect(first == repeated)
        #expect(first != changedVersion)
        #expect(first.digest == "57f0d5ccddf90537eb734957c5c2da554f63ada90f50cb75e1bcd795e874fd83")
        #expect(SynthesisCacheKey(digest: first.digest.uppercased()) == first)
        #expect(SynthesisCacheKey(digest: "not-a-digest") == nil)

        let plain = SynthesisCacheKey(
            input: .plainText("<break/>"), voice: .maeve,
            parameters: .init(seed: 7), engineVersion: 3)
        let markup = SynthesisCacheKey(
            input: .markup("<break/>"), voice: .maeve,
            parameters: .init(seed: 7), engineVersion: 3)
        let stereo = SynthesisCacheKey(
            text: "In the beginning", voice: .maeve,
            parameters: .init(seed: 7),
            audioFormat: AudioFormat(channels: 2), engineVersion: 3)
        #expect(plain != markup)
        #expect(stereo != first)

        let unseededA = SynthesisCacheKey(
            text: "vary", voice: .maeve, parameters: .init(), engineVersion: 3)
        let unseededB = SynthesisCacheKey(
            text: "vary", voice: .maeve, parameters: .init(), engineVersion: 3)
        #expect(unseededA != unseededB)

        let phonemes = Array(repeating: Phoneme("ə"), count: 513)
        let formerlyCollidingA = PhonemeProsodySequence(
            phonemes: phonemes,
            wordBoundaries: [0],
            wordTexts: [String(repeating: "\0", count: 16)])
        let formerlyCollidingB = PhonemeProsodySequence(
            phonemes: phonemes,
            wordBoundaries: [0, 16],
            wordTexts: ["", ""])
        #expect(SynthesisCacheKey(
            phonemeProsody: formerlyCollidingA,
            voice: .maeve,
            parameters: .init(seed: 7)
        ) != SynthesisCacheKey(
            phonemeProsody: formerlyCollidingB,
            voice: .maeve,
            parameters: .init(seed: 7)))
    }

    @Test("CCH-001/002/003 rendered audio persists, pins, inspects, and purges")
    func persistentRenderedAudioCache() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("choir-cache-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = SynthesisAudioCacheConfiguration(
            maximumSizeBytes: 60,
            cacheDirectory: root.appendingPathComponent("cache"),
            applicationSupportDirectory: root.appendingPathComponent("support"))
        let cache = try SynthesisAudioCache(configuration: configuration)
        let audio = AudioBuffer(samples: [1], format: AudioFormat(sampleRate: 8_000))
        let first = SynthesisCacheKey(
            text: "first", voice: .maeve, parameters: .init(seed: 1), engineVersion: 1)
        let second = SynthesisCacheKey(
            text: "second", voice: .maeve, parameters: .init(seed: 1), engineVersion: 1)
        let third = SynthesisCacheKey(
            text: "third", voice: .maeve, parameters: .init(seed: 1), engineVersion: 1)

        try await cache.store(audio, for: first)
        try await cache.store(audio, for: second)
        let firstHit = try await cache.audio(for: first)
        #expect(firstHit == audio)
        try await cache.store(audio, for: third)
        #expect(!(await cache.contains(second)))
        #expect(await cache.contains(first))
        #expect(await cache.contains(third))
        let pinned = try await cache.setPinned(true, for: first)
        #expect(pinned)

        let reopened = try SynthesisAudioCache(configuration: configuration)
        let reopenedHit = try await reopened.audio(for: first)
        #expect(reopenedHit == audio)
        #expect(await reopened.statistics().pinnedItemCount == 1)
        let ordinaryRemoved = try await reopened.removeAll(includingPinned: false)
        #expect(ordinaryRemoved == 1)
        #expect(await reopened.contains(first))
        let pinnedRemoved = try await reopened.removeAll()
        #expect(pinnedRemoved == 1)
    }

    @Test("CCH-002 cache actors share one coherent capacity and LRU view")
    func persistentCacheCoordinatesMultipleActors() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("choir-shared-cache-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = SynthesisAudioCacheConfiguration(
            maximumSizeBytes: 60,
            cacheDirectory: root.appendingPathComponent("cache"),
            applicationSupportDirectory: root.appendingPathComponent("support"))
        let firstActor = try SynthesisAudioCache(configuration: configuration)
        let secondActor = try SynthesisAudioCache(configuration: configuration)
        let audio = AudioBuffer(samples: [1], format: AudioFormat(sampleRate: 8_000))
        let first = SynthesisCacheKey(
            text: "shared-first", voice: .maeve,
            parameters: .init(seed: 1), engineVersion: 1)
        let second = SynthesisCacheKey(
            text: "shared-second", voice: .maeve,
            parameters: .init(seed: 1), engineVersion: 1)
        let third = SynthesisCacheKey(
            text: "shared-third", voice: .maeve,
            parameters: .init(seed: 1), engineVersion: 1)

        try await firstActor.store(audio, for: first)
        #expect(await secondActor.contains(first))
        try await secondActor.store(audio, for: second)
        _ = try await secondActor.audio(for: first)

        // The first actor must rescan before selecting an aggregate LRU victim.
        try await firstActor.store(audio, for: third)
        #expect(await secondActor.contains(first))
        #expect(!(await secondActor.contains(second)))
        #expect(await secondActor.contains(third))
        #expect(await firstActor.statistics().itemCount == 2)
        #expect(await firstActor.statistics().currentSizeBytes == 60)

        #expect(try await secondActor.setPinned(true, for: first))
        #expect(await firstActor.statistics().pinnedItemCount == 1)
        #expect(try await firstActor.removeAll(includingPinned: false) == 1)
        #expect(await secondActor.cachedDigests == [first.digest])
    }

    @Test("CCH-002 coordinated scans reclaim unaddressable cache orphans")
    func persistentCacheReclaimsOrphans() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("choir-orphan-cache-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheBase = root.appendingPathComponent("cache")
        let synthesisDirectory = cacheBase
            .appendingPathComponent("Choir", isDirectory: true)
            .appendingPathComponent("Synthesis", isDirectory: true)
        try FileManager.default.createDirectory(
            at: synthesisDirectory, withIntermediateDirectories: true)
        let orphan = synthesisDirectory.appendingPathComponent(
            String(repeating: "a", count: 64) + ".choirpcm")
        try Data([0, 1, 2]).write(to: orphan)

        let cache = try SynthesisAudioCache(configuration: .init(
            maximumSizeBytes: 60,
            cacheDirectory: cacheBase,
            applicationSupportDirectory: root.appendingPathComponent("support")))

        #expect(!FileManager.default.fileExists(atPath: orphan.path))
        #expect(await cache.statistics().itemCount == 0)
    }

    @Test("CCH-011 lazy assets coalesce, unload, and reload")
    func lazyAssetLifecycle() async throws {
        let probe = AssetLoaderProbe()
        let store = LazyAssetStore<Int, String> { key in
            await probe.load(key)
        }
        let first = try await store.asset(for: 7)
        let cached = try await store.asset(for: 7)
        #expect(first == cached)
        #expect(await probe.count == 1)
        #expect(await store.handleMemoryPressure() == 1)
        let reloaded = try await store.asset(for: 7)
        #expect(reloaded != first)
        #expect(await probe.count == 2)
        #expect(await store.statistics().unloadCount == 1)
    }

    @Test("CCH-011 an obsolete load cannot remove its replacement")
    func obsoleteLoadCannotEvictNewInFlightLoad() async throws {
        let loader = SuspendedAssetLoader()
        let store = LazyAssetStore<Int, String> { key in
            await loader.load(key)
        }

        let obsolete = Task { try await store.asset(for: 7) }
        while await loader.count < 1 { await Task.yield() }
        _ = await store.unloadAll()

        let replacement = Task { try await store.asset(for: 7) }
        while await loader.count < 2 { await Task.yield() }
        await loader.resume(call: 1, value: "obsolete")
        #expect(try await obsolete.value == "obsolete")
        #expect(await store.statistics().loadingCount == 1)

        let coalesced = Task { try await store.asset(for: 7) }
        for _ in 0..<10 { await Task.yield() }
        #expect(await loader.count == 2)
        await loader.resume(call: 2, value: "replacement")
        #expect(try await replacement.value == "replacement")
        #expect(try await coalesced.value == "replacement")
        #expect(await store.isLoaded(7))
    }

    private func readUInt32LE(_ data: Data, offset: Int) -> UInt32 {
        let bytes = [UInt8](data)
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    private func readInt16LE(_ data: Data, offset: Int) -> Int16 {
        let bytes = [UInt8](data)
        let bits = UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
        return Int16(bitPattern: bits)
    }
}

private actor AssetLoaderProbe {
    private(set) var count = 0

    func load(_ key: Int) -> String {
        count += 1
        return "\(key)-\(count)"
    }
}

private actor SuspendedAssetLoader {
    private(set) var count = 0
    private var pending: [Int: CheckedContinuation<String, Never>] = [:]

    func load(_ key: Int) async -> String {
        count += 1
        let call = count
        return await withCheckedContinuation { continuation in
            pending[call] = continuation
        }
    }

    func resume(call: Int, value: String) {
        pending.removeValue(forKey: call)?.resume(returning: value)
    }
}
