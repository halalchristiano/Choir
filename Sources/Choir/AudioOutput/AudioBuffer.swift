import Foundation

/// Raw PCM audio buffer containing synthesized audio data.
public struct AudioBuffer: Sendable {
    /// Raw PCM audio samples as 16-bit signed integers.
    public let samples: [Int16]

    /// The audio format of this buffer.
    public let format: AudioFormat

    /// Duration of the audio in seconds.
    public var duration: Double {
        Double(samples.count) / Double(format.sampleRate * format.channels)
    }

    /// Creates an audio buffer with PCM samples.
    public init(samples: [Int16], format: AudioFormat) {
        self.samples = samples
        self.format = format
    }
}

/// Represents synthesized audio output in various formats.
public enum AudioOutput: Sendable {
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
}

/// A chunk of audio streaming output.
public struct AudioChunk: Sendable {
    /// The PCM audio samples.
    public let samples: [Int16]

    /// Whether this is the final chunk.
    public let isFinal: Bool

    /// Optional timestamp in seconds.
    public let timestamp: Double?

    public init(samples: [Int16], isFinal: Bool = false, timestamp: Double? = nil) {
        self.samples = samples
        self.isFinal = isFinal
        self.timestamp = timestamp
    }
}
