import Foundation
import Testing
@testable import Choir

@Suite("Fourth improvement sprint: safe audio utilities")
struct ImprovementSprintFourAudioTests {
    private let stereo = AudioFormat(sampleRate: 8_000, channels: 2)

    @Test("Buffers report frame alignment and trailing samples")
    func bufferAlignmentMetrics() {
        let aligned = AudioBuffer(samples: [1, 2, 3, 4], format: stereo)
        let partial = AudioBuffer(samples: [1, 2, 3], format: stereo)
        #expect(aligned.isFrameAligned)
        #expect(aligned.trailingSampleCount == 0)
        #expect(!partial.isFrameAligned)
        #expect(partial.trailingSampleCount == 1)
    }

    @Test("Interleaved sample lookup validates frame and channel")
    func interleavedSampleLookup() {
        let buffer = AudioBuffer(samples: [1, 10, 2, 20], format: stereo)
        #expect(buffer.sample(atFrame: 1, channel: 0) == 2)
        #expect(buffer.sample(atFrame: 1, channel: 1) == 20)
        #expect(buffer.sample(atFrame: -1, channel: 0) == nil)
        #expect(buffer.sample(atFrame: 0, channel: 2) == nil)
        #expect(buffer.sample(atFrame: .max, channel: 0) == nil)
    }

    @Test("Frame lookup returns complete frames only")
    func frameLookup() {
        let buffer = AudioBuffer(samples: [1, 10, 2, 20, 3], format: stereo)
        #expect(buffer.frame(at: 0) == [1, 10])
        #expect(buffer.frame(at: 1) == [2, 20])
        #expect(buffer.frame(at: 2) == nil)
    }

    @Test("Channel peaks are isolated and normalized")
    func channelPeak() {
        let buffer = AudioBuffer(
            samples: [Int16.max, 1, 0, Int16.min], format: stereo)
        #expect(buffer.peakAmplitude(forChannel: 0)! < 1)
        #expect(buffer.peakAmplitude(forChannel: 1) == 1)
        #expect(buffer.peakAmplitude(forChannel: 2) == nil)
    }

    @Test("Buffer level statistics expose DC and mean absolute amplitude")
    func levelStatistics() {
        let buffer = AudioBuffer(samples: [16_384, 16_384], format: AudioFormat())
        #expect(buffer.dcOffset == 0.5)
        #expect(buffer.averageAbsoluteAmplitude == 0.5)
        #expect(AudioBuffer(samples: [], format: AudioFormat()).dcOffset == 0)
    }

    @Test("Silence ratio clamps thresholds and handles empty input")
    func silenceRatio() {
        let buffer = AudioBuffer(samples: [0, 100, 20_000], format: AudioFormat())
        #expect(buffer.silenceRatio() == 1.0 / 3.0)
        #expect(buffer.silenceRatio(threshold: 0.01) == 2.0 / 3.0)
        #expect(buffer.silenceRatio(threshold: .infinity) == 1.0 / 3.0)
        #expect(AudioBuffer(samples: [], format: AudioFormat()).silenceRatio() == 1)
    }

    @Test("Silence trimming preserves complete multichannel frames")
    func trimmingSilence() {
        let buffer = AudioBuffer(samples: [0, 0, 5, 6, 7, 8, 0, 0], format: stereo)
        let trimmed = buffer.trimmingSilence()
        #expect(trimmed.samples == [5, 6, 7, 8])
        #expect(trimmed.format == stereo)
    }

    @Test("Frame slices preserve format and reject invalid ranges")
    func frameSlice() {
        let buffer = AudioBuffer(samples: [1, 10, 2, 20, 3, 30], format: stereo)
        #expect(buffer.slice(frames: 1..<3)?.samples == [2, 20, 3, 30])
        #expect(buffer.slice(frames: -1..<1) == nil)
        #expect(buffer.slice(frames: 0..<4) == nil)
    }

    @Test("Buffer splitting keeps chunks frame aligned")
    func bufferSplitting() throws {
        let buffer = AudioBuffer(samples: [1, 10, 2, 20, 3, 30], format: stereo)
        let pieces = try buffer.split(maximumFrames: 2)
        #expect(pieces.map(\.samples) == [[1, 10, 2, 20], [3, 30]])
        #expect(pieces.allSatisfy(\.isFrameAligned))
    }

    @Test("Buffer splitting rejects invalid limits and partial frames")
    func invalidBufferSplitting() {
        let valid = AudioBuffer(samples: [1, 2], format: stereo)
        let partial = AudioBuffer(samples: [1], format: stereo)
        #expect(throws: ChoirError.self) { try valid.split(maximumFrames: 0) }
        #expect(throws: ChoirError.self) { try partial.split(maximumFrames: 1) }
    }

    @Test("Compatible audio buffers append without losing metadata")
    func bufferAppending() throws {
        let first = AudioBuffer(samples: [1, 2], format: stereo)
        let second = AudioBuffer(samples: [3, 4], format: stereo)
        let combined = try first.appending(second)
        #expect(combined.samples == [1, 2, 3, 4])
        #expect(combined.format == stereo)
    }

    @Test("Audio buffer append rejects format mismatches")
    func mismatchedBufferAppending() {
        let mono = AudioBuffer(samples: [1], format: AudioFormat(sampleRate: 8_000))
        let twoChannel = AudioBuffer(samples: [1, 2], format: stereo)
        #expect(throws: ChoirError.self) { try mono.appending(twoChannel) }
    }

    @Test("Audio outputs expose their representation and payload safely")
    func outputIntrospection() {
        let buffer = AudioBuffer(samples: [1], format: AudioFormat())
        let pcm = AudioOutput.pcm(buffer)
        let wav = AudioOutput.wav(Data([1, 2]))
        #expect(pcm.kind == .pcm)
        #expect(pcm.pcmBuffer == buffer)
        #expect(pcm.encodedData == nil)
        #expect(wav.kind == .wav)
        #expect(wav.pcmBuffer == nil)
        #expect(wav.encodedData == Data([1, 2]))
    }

    @Test("Audio chunks validate interleaved frame alignment")
    func chunkValidation() throws {
        try AudioChunk(samples: [1, 2]).validate(format: stereo)
        #expect(throws: ChoirError.self) {
            try AudioChunk(samples: [1]).validate(format: stereo)
        }
    }

    @Test("Audio chunks calculate finite end timestamps")
    func chunkEndTimestamp() {
        let chunk = AudioChunk(samples: [1, 2, 3, 4], timestamp: 2)
        #expect(chunk.endTimestamp(format: AudioFormat(sampleRate: 8_000)) == 2.0005)
        #expect(AudioChunk(samples: []).endTimestamp(format: stereo) == nil)
    }

    @Test("WAV byte estimates match actual encoding")
    func wavSizing() throws {
        let buffer = AudioBuffer(samples: [1, 2, 3, 4], format: stereo)
        let encoder = AudioEncoder()
        let data = try encoder.encodeWAV(buffer)
        #expect(AudioEncoder.wavHeaderSize == 44)
        #expect(try encoder.estimatedWAVByteCount(for: buffer) == data.count)
    }

    @Test("Validated raw encoding preserves little-endian samples")
    func validatedRawEncoding() throws {
        let buffer = AudioBuffer(samples: [0x0102, -2], format: stereo)
        let bytes = [UInt8](try AudioEncoder().encodeRawValidated(buffer))
        #expect(bytes == [0x02, 0x01, 0xfe, 0xff])
    }

    @Test("Validated raw encoding rejects incomplete frames")
    func invalidRawEncoding() {
        let buffer = AudioBuffer(samples: [1], format: stereo)
        #expect(throws: ChoirError.self) {
            try AudioEncoder().encodeRawValidated(buffer)
        }
    }

    @Test("Streaming chunks concatenate into one WAV payload")
    func chunkWAVEncoding() throws {
        let chunks = [
            AudioChunk(samples: [1, 2], timestamp: 0),
            AudioChunk(samples: [3, 4], isFinal: true, timestamp: 0.000125),
        ]
        let encoded = try AudioEncoder().encodeWAV(chunks: chunks, format: stereo)
        #expect(encoded.count == AudioEncoder.wavHeaderSize + 8)
        #expect(Array(encoded.suffix(8)) == [1, 0, 2, 0, 3, 0, 4, 0])
    }

    @Test("Streaming WAV encoding rejects an early final marker")
    func earlyFinalChunkRejected() {
        let chunks = [
            AudioChunk(samples: [1, 2], isFinal: true),
            AudioChunk(samples: [3, 4]),
        ]
        #expect(throws: ChoirError.self) {
            try AudioEncoder().encodeWAV(chunks: chunks, format: stereo)
        }
    }

    @Test("Streaming WAV encoding rejects overlapping timestamps")
    func overlappingChunkTimestampRejected() {
        let chunks = [
            AudioChunk(samples: [1, 2], timestamp: 1),
            AudioChunk(samples: [3, 4], timestamp: 0.5),
        ]
        #expect(throws: ChoirError.self) {
            try AudioEncoder().encodeWAV(chunks: chunks, format: stereo)
        }
    }

    @Test("Frequency effects validate against Nyquist")
    func effectFrequencyValidation() throws {
        try AudioEffect.Kind.highPass(cutoffHz: 100).validate(sampleRate: 8_000)
        #expect(throws: ChoirError.self) {
            try AudioEffect.Kind.lowPass(cutoffHz: 4_000).validate(sampleRate: 8_000)
        }
        #expect(throws: ChoirError.self) {
            try AudioEffect.Kind.deEsser(centerHz: .nan).validate(sampleRate: 48_000)
        }
    }

    @Test("Level effects reject unsafe parameter envelopes")
    func effectLevelValidation() throws {
        try AudioEffect.Kind.normalize(targetLevel: -6).validate(sampleRate: 48_000)
        try AudioEffect.Kind.compress(threshold: -20, ratio: 4).validate(sampleRate: 48_000)
        #expect(throws: ChoirError.self) {
            try AudioEffect.Kind.softClip(threshold: 0).validate(sampleRate: 48_000)
        }
        #expect(throws: ChoirError.self) {
            try AudioEffect.Kind.reverb(wetLevel: 2).validate(sampleRate: 48_000)
        }
    }

    @Test("Effect and chain validation reject bad configuration")
    func effectChainValidation() throws {
        let valid = AudioEffectChain(sampleRate: 8_000)
            .add(AudioEffect(name: "Filter", kind: .highPass(cutoffHz: 100)))
        try valid.validate()
        let blank = AudioEffect(name: "  ", kind: .reverb(wetLevel: 0.2))
        #expect(throws: ChoirError.self) { try blank.validate(sampleRate: 8_000) }
        #expect(throws: ChoirError.self) { try AudioEffectChain(sampleRate: 0).validate() }
    }

    @Test("Effect-chain buffer processing preserves valid PCM metadata")
    func effectChainBufferProcessing() throws {
        let buffer = AudioBuffer(samples: [0, 100, 0, -100], format: stereo)
        let chain = AudioEffectChain(sampleRate: 8_000)
            .add(AudioEffect(name: "Dry", kind: .reverb(wetLevel: 0)))
        let output = try chain.process(buffer)
        #expect(output.samples == buffer.samples)
        #expect(output.format == stereo)
        #expect(throws: ChoirError.self) {
            try AudioEffectChain(sampleRate: 48_000).process(buffer)
        }
    }
}
