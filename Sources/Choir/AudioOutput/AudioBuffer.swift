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

    /// Samples for one channel, extracted from interleaved PCM.
    public func samples(forChannel channel: Int) -> [Int16]? {
        guard format.channels > 0, 0..<format.channels ~= channel else { return nil }
        return stride(from: channel, to: samples.count, by: format.channels).map { samples[$0] }
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
}
