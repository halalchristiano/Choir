import Foundation

/// Parameters for controlling synthesis output, including prosody and expression.
public struct SynthesisParameters: Sendable {
    /// Pitch shift in semitones (-12 to +12). Default is 0.
    public var pitchShift: Double = 0

    /// Speech rate multiplier (0.5 to 2.0). Default is 1.0.
    public var rate: Double = 1.0

    /// Emotional intensity (0.0 to 1.0). Default is 0.5.
    public var emotionalIntensity: Double = 0.5

    /// Breathiness amount (0.0 to 1.0). Default is 0.0.
    public var breathiness: Double = 0.0

    /// Age shift: negative values sound younger, positive values sound older (-5 to +5). Default is 0.
    public var ageShift: Double = 0

    /// Gender shift: negative values shift feminine, positive values shift masculine (-1.0 to +1.0). Default is 0.
    public var genderShift: Double = 0

    public init(
        pitchShift: Double = 0,
        rate: Double = 1.0,
        emotionalIntensity: Double = 0.5,
        breathiness: Double = 0.0,
        ageShift: Double = 0,
        genderShift: Double = 0
    ) {
        self.pitchShift = max(-12, min(12, pitchShift))
        self.rate = max(0.5, min(2.0, rate))
        self.emotionalIntensity = max(0, min(1.0, emotionalIntensity))
        self.breathiness = max(0, min(1.0, breathiness))
        self.ageShift = max(-5, min(5, ageShift))
        self.genderShift = max(-1.0, min(1.0, genderShift))
    }
}

/// Audio format specification for synthesis output.
public struct AudioFormat: Sendable {
    /// Sample rate in Hz. Default is 48000.
    public let sampleRate: Int

    /// Number of audio channels. Default is 1 (mono).
    public let channels: Int

    /// Bit depth. Default is 16 (PCM 16-bit).
    public let bitDepth: Int

    public init(sampleRate: Int = 48000, channels: Int = 1, bitDepth: Int = 16) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
    }
}

/// Streaming options for real-time synthesis.
public struct StreamingOptions: Sendable {
    /// Target buffer size for streaming chunks in samples. Default is 2400 (50ms at 48kHz).
    public var chunkSize: Int = 2400

    /// Whether to preload the acoustic model. Default is true.
    public var preloadModel: Bool = true

    public init(chunkSize: Int = 2400, preloadModel: Bool = true) {
        self.chunkSize = chunkSize
        self.preloadModel = preloadModel
    }
}
