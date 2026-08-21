import Foundation

/// Raw PCM audio buffer containing synthesized audio data.
public struct AudioBuffer: Sendable, Equatable {
    /// Raw PCM audio samples as 16-bit signed integers.
    public let samples: [Int16]

    /// The audio format of this buffer.
    public let format: AudioFormat

    /// Duration of the audio in seconds.
    public var duration: Double {
        guard format.sampleRate > 0, format.channels > 0 else { return 0 }
        return Double(samples.count) / (Double(format.sampleRate) * Double(format.channels))
    }

    /// Interleaved sample frames per channel.
    public var frameCount: Int {
        guard format.channels > 0 else { return 0 }
        return samples.count / format.channels
    }

    /// Whether every interleaved frame contains one sample for each channel.
    public var isFrameAligned: Bool {
        guard format.channels > 0 else { return false }
        return samples.count.isMultiple(of: format.channels)
    }

    /// Samples left after the final complete interleaved frame.
    public var trailingSampleCount: Int {
        guard format.channels > 0 else { return samples.count }
        return samples.count % format.channels
    }

    /// PCM payload size, excluding any container header.
    public var byteCount: Int { samples.count * MemoryLayout<Int16>.size }

    public var isEmpty: Bool { samples.isEmpty }

    /// Largest absolute sample, normalized to 0...1.
    public var peakAmplitude: Double {
        guard let peak = samples.map({ abs(Int32($0)) }).max() else { return 0 }
        return min(1, Double(peak) / 32768)
    }

    /// Root-mean-square amplitude, normalized to 0...1.
    public var rmsAmplitude: Double {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(0.0) { partial, sample in
            let normalized = Double(sample) / 32768
            return partial + normalized * normalized
        } / Double(samples.count)
        return sqrt(meanSquare)
    }

    /// Signed arithmetic mean, normalized to -1...1, useful for detecting DC offset.
    public var dcOffset: Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0.0) { $0 + Double($1) / 32768 } / Double(samples.count)
    }

    /// Mean absolute sample magnitude, normalized to 0...1.
    public var averageAbsoluteAmplitude: Double {
        guard !samples.isEmpty else { return 0 }
        let total = samples.reduce(0.0) { $0 + Double(abs(Int32($1))) / 32768 }
        return min(1, total / Double(samples.count))
    }

    /// Samples for one channel, extracted from interleaved PCM.
    public func samples(forChannel channel: Int) -> [Int16]? {
        guard format.channels > 0, 0..<format.channels ~= channel else { return nil }
        return stride(from: channel, to: samples.count, by: format.channels).map { samples[$0] }
    }

    /// Returns one interleaved sample without exposing index arithmetic to callers.
    public func sample(atFrame frame: Int, channel: Int) -> Int16? {
        guard format.channels > 0,
              frame >= 0,
              channel >= 0,
              channel < format.channels else { return nil }
        let (frameOffset, frameOverflow) = frame.multipliedReportingOverflow(by: format.channels)
        guard !frameOverflow else { return nil }
        let (index, indexOverflow) = frameOffset.addingReportingOverflow(channel)
        guard !indexOverflow, samples.indices.contains(index) else { return nil }
        return samples[index]
    }

    /// Returns all channel samples for a complete interleaved frame.
    public func frame(at index: Int) -> [Int16]? {
        guard format.channels > 0, index >= 0, index < frameCount else { return nil }
        let start = index * format.channels
        return Array(samples[start..<(start + format.channels)])
    }

    /// Peak normalized amplitude for one channel of interleaved PCM.
    public func peakAmplitude(forChannel channel: Int) -> Double? {
        guard let channelSamples = samples(forChannel: channel) else { return nil }
        guard let peak = channelSamples.map({ abs(Int32($0)) }).max() else { return 0 }
        return min(1, Double(peak) / 32768)
    }

    /// Fraction of samples whose magnitude is at or below a normalized threshold.
    public func silenceRatio(threshold: Double = 0) -> Double {
        guard !samples.isEmpty else { return 1 }
        let boundedThreshold = threshold.isFinite ? max(0, min(1, threshold)) : 0
        let limit = boundedThreshold * 32768
        let silentCount = samples.reduce(into: 0) { count, sample in
            if Double(abs(Int32(sample))) <= limit { count += 1 }
        }
        return Double(silentCount) / Double(samples.count)
    }

    /// Removes silent complete frames from the beginning and end of a buffer.
    public func trimmingSilence(threshold: Double = 0) -> AudioBuffer {
        guard format.channels > 0, isFrameAligned, !samples.isEmpty else { return self }
        let boundedThreshold = threshold.isFinite ? max(0, min(1, threshold)) : 0
        let limit = boundedThreshold * 32768

        func isSilentFrame(_ frame: Int) -> Bool {
            let start = frame * format.channels
            return samples[start..<(start + format.channels)].allSatisfy {
                Double(abs(Int32($0))) <= limit
            }
        }

        var first = 0
        while first < frameCount, isSilentFrame(first) { first += 1 }
        guard first < frameCount else { return AudioBuffer(samples: [], format: format) }

        var last = frameCount
        while last > first, isSilentFrame(last - 1) { last -= 1 }
        return slice(frames: first..<last) ?? self
    }

    /// Returns a frame-aligned sub-buffer, or `nil` when the range is invalid.
    public func slice(frames range: Range<Int>) -> AudioBuffer? {
        guard format.channels > 0,
              range.lowerBound >= 0,
              range.upperBound >= range.lowerBound,
              range.upperBound <= frameCount else { return nil }
        let lower = range.lowerBound * format.channels
        let upper = range.upperBound * format.channels
        return AudioBuffer(samples: Array(samples[lower..<upper]), format: format)
    }

    /// Splits a valid buffer into frame-aligned pieces no larger than the requested size.
    public func split(maximumFrames: Int) throws -> [AudioBuffer] {
        guard maximumFrames > 0 else {
            throw ChoirError.invalidParameter(
                parameter: "maximumFrames", reason: "Maximum frames must be greater than zero")
        }
        try validate()
        guard frameCount > 0 else { return [] }

        var chunks: [AudioBuffer] = []
        let chunkCount = frameCount / maximumFrames
            + (frameCount.isMultiple(of: maximumFrames) ? 0 : 1)
        chunks.reserveCapacity(chunkCount)
        var lower = 0
        while lower < frameCount {
            let (candidateUpper, overflow) = lower.addingReportingOverflow(maximumFrames)
            let upper = overflow ? frameCount : min(frameCount, candidateUpper)
            if let chunk = slice(frames: lower..<upper) { chunks.append(chunk) }
            lower = upper
        }
        return chunks
    }

    /// Concatenates buffers only when their PCM formats and frame alignment match.
    public func appending(_ other: AudioBuffer) throws -> AudioBuffer {
        try validate()
        try other.validate()
        guard format == other.format else {
            throw ChoirError.invalidParameter(
                parameter: "other", reason: "Audio buffers must use the same format")
        }
        let (combinedCount, overflow) = samples.count.addingReportingOverflow(other.samples.count)
        guard !overflow else {
            throw ChoirError.invalidParameter(
                parameter: "other", reason: "Combined sample count exceeds platform limits")
        }
        var combined: [Int16] = []
        combined.reserveCapacity(combinedCount)
        combined.append(contentsOf: samples)
        combined.append(contentsOf: other.samples)
        return AudioBuffer(samples: combined, format: format)
    }

    /// Validates the format and interleaved frame alignment.
    public func validate() throws {
        try format.validate()
        guard samples.count.isMultiple(of: format.channels) else {
            throw ChoirError.invalidParameter(
                parameter: "samples",
                reason: "Interleaved sample count must be divisible by the channel count")
        }
    }

    /// Creates an audio buffer with PCM samples.
    public init(samples: [Int16], format: AudioFormat) {
        self.samples = samples
        self.format = format
    }
}

/// Represents synthesized audio output in various formats.
public enum AudioOutput: Sendable, Equatable {
    /// Raw PCM samples.
    case pcm(AudioBuffer)

    /// WAV encoded audio data.
    case wav(Data)

    /// MP3 encoded audio data.
    case mp3(Data)

    /// AAC encoded audio data.
    case aac(Data)

    /// Storage representation used by an output value.
    public enum Kind: String, Sendable, Equatable, Hashable, Codable {
        case pcm
        case wav
        case mp3
        case aac
    }

    public var kind: Kind {
        switch self {
        case .pcm: .pcm
        case .wav: .wav
        case .mp3: .mp3
        case .aac: .aac
        }
    }

    /// The byte size of this audio output.
    public var byteSize: Int {
        switch self {
        case .pcm(let buffer):
            return buffer.samples.count * 2
        case .wav(let data), .mp3(let data), .aac(let data):
            return data.count
        }
    }

    public var isEmpty: Bool { byteSize == 0 }

    /// Encoded bytes, or `nil` when this value contains raw PCM.
    public var encodedData: Data? {
        switch self {
        case .pcm: nil
        case .wav(let data), .mp3(let data), .aac(let data): data
        }
    }

    /// Raw PCM, or `nil` when this value contains encoded bytes.
    public var pcmBuffer: AudioBuffer? {
        guard case .pcm(let buffer) = self else { return nil }
        return buffer
    }
}

/// A chunk of audio streaming output.
public struct AudioChunk: Sendable, Equatable {
    /// The PCM audio samples.
    public let samples: [Int16]

    /// Whether this is the final chunk.
    public let isFinal: Bool

    /// Optional timestamp in seconds.
    public let timestamp: Double?

    public init(samples: [Int16], isFinal: Bool = false, timestamp: Double? = nil) {
        self.samples = samples
        self.isFinal = isFinal
        if let timestamp, timestamp.isFinite, timestamp >= 0 {
            self.timestamp = timestamp
        } else {
            self.timestamp = nil
        }
    }

    public var sampleCount: Int { samples.count }
    public var byteCount: Int { samples.count * MemoryLayout<Int16>.size }
    public var isEmpty: Bool { samples.isEmpty }

    /// Duration when interpreted using an interleaved PCM format.
    public func duration(format: AudioFormat) -> Double {
        guard format.sampleRate > 0, format.channels > 0 else { return 0 }
        return Double(samples.count) / (Double(format.sampleRate) * Double(format.channels))
    }

    /// Validates the associated PCM format and interleaved frame alignment.
    public func validate(format: AudioFormat) throws {
        try format.validate()
        guard samples.count.isMultiple(of: format.channels) else {
            throw ChoirError.invalidParameter(
                parameter: "samples",
                reason: "Chunk sample count must be divisible by the channel count")
        }
    }

    /// Timestamp immediately after this chunk, when a start timestamp is available.
    public func endTimestamp(format: AudioFormat) -> Double? {
        guard let timestamp else { return nil }
        let end = timestamp + duration(format: format)
        return end.isFinite ? end : nil
    }
}
