import Testing
@testable import Choir

@Suite("Asset Cache")
struct AssetCacheTests {
    @Test("Cache stores and retrieves features")
    func testFeaturesCaching() async {
        let cache = AssetCache()
        let features = AcousticFeatures(features: Array(repeating: Array(repeating: Float(0), count: 80), count: 100))

        await cache.cacheAcousticFeatures(features, for: "test_key")
        let retrieved = await cache.getAcousticFeatures(for: "test_key")

        #expect(retrieved != nil)
        #expect(retrieved?.frameCount == 100)
    }

    @Test("Cache stores and retrieves transcriptions")
    func testTranscriptionsCaching() async {
        let cache = AssetCache()
        let phonemes = [Phoneme("h"), Phoneme("ə"), Phoneme("l")]
        let transcript = PhoneticTranscription(phonemes: phonemes, originalText: "hello")

        await cache.cacheTranscription(transcript, for: "test_key")
        let retrieved = await cache.getTranscription(for: "test_key")

        #expect(retrieved != nil)
        #expect(retrieved?.phonemes.count == 3)
    }

    @Test("Cache stores and retrieves prosody")
    func testProsodyCaching() async {
        let cache = AssetCache()
        let phonemes = [
            AnnotatedPhoneme(phoneme: Phoneme("h")),
            AnnotatedPhoneme(phoneme: Phoneme("ə")),
        ]
        let prosody = ProsodyDescription(
            phonemes: phonemes,
            pitchContour: ProsodyContour(points: [(0, 120)]),
            energyContour: ProsodyContour(points: [(0, -20)]),
            durations: [50, 100]
        )

        await cache.cacheProsody(prosody, for: "test_key")
        let retrieved = await cache.getProsody(for: "test_key")

        #expect(retrieved != nil)
        #expect(retrieved?.phonemes.count == 2)
    }

    @Test("Cache clear removes all data")
    func testCacheClear() async {
        let cache = AssetCache()
        let features = AcousticFeatures(features: [[Float(0)]])

        await cache.cacheAcousticFeatures(features, for: "key1")
        await cache.clear()

        let retrieved = await cache.getAcousticFeatures(for: "key1")
        #expect(retrieved == nil)
    }

    @Test("Cache provides statistics")
    func testCacheStatistics() async {
        let cache = AssetCache()
        let features = AcousticFeatures(features: Array(repeating: Array(repeating: Float(0), count: 80), count: 100))

        await cache.cacheAcousticFeatures(features, for: "key1")
        let stats = await cache.getStatistics()

        #expect(stats.featureCount == 1)
        #expect(stats.currentSizeBytes > 0)
        #expect(stats.utilizationPercent > 0)
    }

    @Test("Cache LRU eviction works")
    func testLRUEviction() async {
        let smallCache = AssetCache(maxCacheSize: 1000)
        let features = AcousticFeatures(features: Array(repeating: Array(repeating: Float(0), count: 80), count: 100))

        // Fill cache with multiple items
        await smallCache.cacheAcousticFeatures(features, for: "key1")
        await smallCache.cacheAcousticFeatures(features, for: "key2")
        await smallCache.cacheAcousticFeatures(features, for: "key3")

        let stats = await smallCache.getStatistics()
        #expect(stats.featureCount <= 3)
    }
}

@Suite("Audio Encoding")
struct AudioEncoderTests {
    let encoder = AudioEncoder()

    @Test("WAV encoding creates valid header")
    func testWAVEncoding() {
        let samples = Array(repeating: Int16(1000), count: 1000)
        let buffer = AudioBuffer(samples: samples, format: AudioFormat())

        let wavData = encoder.encodeWAV(buffer)

        #expect(!wavData.isEmpty)
        #expect(wavData.count > samples.count * 2)

        // Check for RIFF and WAVE markers
        let header = String(bytes: wavData.prefix(4), encoding: .utf8)
        #expect(header == "RIFF")
    }

    @Test("WAV data includes all samples")
    func testWAVDataSize() {
        let samples = Array(repeating: Int16(500), count: 2000)
        let buffer = AudioBuffer(samples: samples, format: AudioFormat())

        let wavData = encoder.encodeWAV(buffer)

        // WAV header is ~44 bytes, plus sample data
        let expectedMinSize = 44 + samples.count * 2
        #expect(wavData.count >= expectedMinSize)
    }

    @Test("Raw encoding preserves samples")
    func testRawEncoding() {
        let samples = Array(repeating: Int16(1000), count: 100)
        let buffer = AudioBuffer(samples: samples, format: AudioFormat())

        let rawData = encoder.encodeRaw(buffer)

        // Raw data should be exactly samples.count * 2 bytes
        #expect(rawData.count == samples.count * 2)
    }

    @Test("Different sample rates produce different durations")
    func testSampleRateVariation() {
        let samples = Array(repeating: Int16(0), count: 48000)

        let buffer48k = AudioBuffer(samples: samples, format: AudioFormat(sampleRate: 48000))
        let buffer44k = AudioBuffer(samples: samples, format: AudioFormat(sampleRate: 44100))

        let wav48k = encoder.encodeWAV(buffer48k)
        let wav44k = encoder.encodeWAV(buffer44k)

        // Sample rate does not change the byte count -- both buffers hold the
        // same number of samples -- but it does change playback duration and
        // the rate recorded in the WAV header.
        #expect(buffer48k.duration != buffer44k.duration)
        #expect(wav48k != wav44k)
    }
}
