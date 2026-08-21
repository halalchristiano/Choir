import Foundation

#if canImport(AVFAudio)
import AVFAudio
#endif

/// Interleaved IEEE-754 float PCM.
///
/// CHOIR's native representation is 48 kHz mono float32 PCM (AUD-001). The
/// type can also represent converted sample rates so callers do not have to
/// leave the package merely to prepare 44.1, 24, or 16 kHz output.
public struct FloatAudioBuffer: Sendable, Equatable {
    public static let nativeSampleRate = 48_000

    /// Interleaved, normalized samples. Values outside `-1...1` are allowed
    /// while processing, but conversion to integer PCM clamps them safely.
    public let samples: [Float]

    public let sampleRate: Int
    public let channels: Int

    public init(samples: [Float], sampleRate: Int = nativeSampleRate, channels: Int = 1) {
        self.samples = samples.map { $0.isFinite ? $0 : 0 }
        self.sampleRate = sampleRate
        self.channels = channels
    }

    /// Converts the package's legacy int16 buffer into normalized float PCM.
    public init(_ buffer: AudioBuffer) {
        self.samples = buffer.samples.map { sample in
            sample == Int16.min ? -1 : Float(sample) / Float(Int16.max)
        }
        self.sampleRate = buffer.format.sampleRate
        self.channels = buffer.format.channels
    }

    public var frameCount: Int {
        guard channels > 0 else { return 0 }
        return samples.count / channels
    }

    public var duration: Double {
        guard sampleRate > 0 else { return 0 }
        return Double(frameCount) / Double(sampleRate)
    }

    public var isFrameAligned: Bool {
        channels > 0 && samples.count.isMultiple(of: channels)
    }

    public var isNativeFormat: Bool {
        sampleRate == Self.nativeSampleRate && channels == 1 && isFrameAligned
    }

    /// Validates finite format metadata and complete interleaved frames.
    public func validate() throws {
        guard 8_000...384_000 ~= sampleRate else {
            throw ChoirError.invalidParameter(
                parameter: "sampleRate",
                reason: "Float PCM sample rate must be within 8,000...384,000 Hz")
        }
        guard 1...8 ~= channels else {
            throw ChoirError.invalidParameter(
                parameter: "channels", reason: "Channel count must be within 1...8")
        }
        guard samples.count.isMultiple(of: channels) else {
            throw ChoirError.invalidParameter(
                parameter: "samples",
                reason: "Interleaved sample count must be divisible by the channel count")
        }
    }

    /// Enforces the native 48 kHz, mono contract from AUD-001.
    public func validateNativeFormat() throws {
        try validate()
        guard isNativeFormat else {
            throw ChoirError.invalidParameter(
                parameter: "format", reason: "Native CHOIR PCM must be 48 kHz mono float32")
        }
    }

    /// Interleaved float32 bytes in explicit little-endian order.
    public var interleavedData: Data {
        var data = Data()
        data.reserveCapacity(samples.count * MemoryLayout<UInt32>.size)
        for sample in samples {
            data.append(sample.bitPattern.littleEndianData)
        }
        return data
    }

    /// Gives DSP code direct read-only access to the array's storage without
    /// introducing another sample-array copy.
    public func withUnsafeSamples<Result>(
        _ body: (UnsafeBufferPointer<Float>) throws -> Result
    ) rethrows -> Result {
        try samples.withUnsafeBufferPointer(body)
    }

    /// Converts to interleaved int16 PCM with deterministic TPDF dither.
    public func int16PCM(dither: Bool = true, seed: UInt64 = 0x4348_4F49_52) throws -> AudioBuffer {
        try validate()
        var generator = AudioDitherGenerator(seed: seed)
        let converted = samples.map { sample -> Int16 in
            let bounded = max(-1, min(1, Double(sample)))
            if bounded <= -1 { return Int16.min }
            if bounded >= 1 { return Int16.max }
            let noise = dither ? generator.nextTPDF() : 0
            let scaled = (bounded * Double(Int16.max) + noise).rounded()
            return Int16(max(Double(Int16.min), min(Double(Int16.max), scaled)))
        }
        return AudioBuffer(
            samples: converted,
            format: AudioFormat(sampleRate: sampleRate, channels: channels, bitDepth: 16))
    }

#if canImport(AVFAudio)
    /// Creates an AVFoundation PCM buffer. AVFoundation owns its storage, so
    /// this accessor necessarily copies once; `[Float]` and unsafe-buffer
    /// access remain available when a copy is not required.
    public func makeAVAudioPCMBuffer() throws -> AVAudioPCMBuffer {
        try validate()
        guard UInt64(frameCount) <= UInt64(UInt32.max),
              let format = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: AVAudioChannelCount(channels),
                interleaved: false),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)),
              let channelData = buffer.floatChannelData else {
            throw ChoirError.audioEncodingFailed(
                reason: "AVFoundation could not allocate a float PCM buffer")
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        for channel in 0..<channels {
            for frame in 0..<frameCount {
                channelData[channel][frame] = samples[frame * channels + channel]
            }
        }
        return buffer
    }
#endif
}

public extension AudioBuffer {
    /// Normalized float32 view of legacy int16 synthesis output.
    var float32PCM: FloatAudioBuffer { FloatAudioBuffer(self) }

    /// Convenience `[Float]` accessor required by AUD-001.
    var floatSamples: [Float] { float32PCM.samples }

    /// Convenience interleaved float32 `Data` accessor required by AUD-001.
    var floatInterleavedData: Data { float32PCM.interleavedData }
}

/// High-quality sample-rate and bit-depth conversion for PCM output.
public struct AudioSampleConverter: Sendable {
    public static let requiredOutputSampleRates: Set<Int> = [44_100, 24_000, 16_000]

    /// A 385-tap Kaiser-windowed sinc. The kernel and guard band keep the
    /// complete 8...24 kHz alias band below -100 dB when converting 48 kHz to
    /// 16 kHz, rather than relying on the Kaiser beta's theoretical attenuation
    /// without allowing enough transition bandwidth.
    private static let kernelRadius = 192
    private static let kaiserBeta = 11.5
    private static let antiAliasCutoffFraction = 0.92

    /// Keep one conversion from attempting an allocation that is incompatible
    /// with CHOIR's platform memory budgets. Callers rendering longer material
    /// can convert it in bounded chunks.
    private static let maximumOutputSampleCount = 32 * 1_024 * 1_024

    public init() {}

    public func resample(_ input: FloatAudioBuffer, to targetSampleRate: Int) throws -> FloatAudioBuffer {
        try input.validate()
        guard 8_000...384_000 ~= targetSampleRate else {
            throw ChoirError.invalidParameter(
                parameter: "targetSampleRate",
                reason: "Target sample rate must be within 8,000...384,000 Hz")
        }
        guard targetSampleRate != input.sampleRate else { return input }
        guard input.frameCount > 0 else {
            return FloatAudioBuffer(
                samples: [], sampleRate: targetSampleRate, channels: input.channels)
        }

        let ratio = Double(targetSampleRate) / Double(input.sampleRate)
        let roundedOutputFrameCount = max(
            1, (Double(input.frameCount) * ratio).rounded())
        let maximumOutputFrameCount = Self.maximumOutputSampleCount / input.channels
        guard roundedOutputFrameCount.isFinite,
              roundedOutputFrameCount <= Double(maximumOutputFrameCount) else {
            throw ChoirError.outOfMemory
        }
        let outputFrameCount = Int(roundedOutputFrameCount)
        let outputSampleCount = outputFrameCount.multipliedReportingOverflow(
            by: input.channels)
        guard !outputSampleCount.overflow,
              outputSampleCount.partialValue <= Self.maximumOutputSampleCount else {
            throw ChoirError.outOfMemory
        }

        let cutoff = min(1, ratio) * Self.antiAliasCutoffFraction
        let denominator = Self.modifiedBesselI0(Self.kaiserBeta)
        var output = [Float](
            repeating: 0, count: outputSampleCount.partialValue)

        for outputFrame in 0..<outputFrameCount {
            let sourcePosition = Double(outputFrame) / ratio
            let center = Int(floor(sourcePosition))
            let lower = max(0, center - Self.kernelRadius)
            let upper = min(input.frameCount - 1, center + Self.kernelRadius)

            for channel in 0..<input.channels {
                var weightedSample = 0.0
                var weightSum = 0.0
                if lower <= upper {
                    for inputFrame in lower...upper {
                        let distance = sourcePosition - Double(inputFrame)
                        let normalizedDistance = abs(distance) / Double(Self.kernelRadius)
                        guard normalizedDistance <= 1 else { continue }
                        let window = Self.modifiedBesselI0(
                            Self.kaiserBeta * sqrt(max(0, 1 - normalizedDistance * normalizedDistance)))
                            / denominator
                        let weight = cutoff * Self.sinc(distance * cutoff) * window
                        weightedSample += Double(
                            input.samples[inputFrame * input.channels + channel]) * weight
                        weightSum += weight
                    }
                }
                let value = weightSum == 0 ? 0 : weightedSample / weightSum
                output[outputFrame * input.channels + channel] = Float(value)
            }
        }

        return FloatAudioBuffer(
            samples: output, sampleRate: targetSampleRate, channels: input.channels)
    }

    /// Resamples and converts to int16 in one call.
    public func convertToInt16(
        _ input: FloatAudioBuffer,
        sampleRate: Int,
        dither: Bool = true,
        seed: UInt64 = 0x4348_4F49_52
    ) throws -> AudioBuffer {
        try resample(input, to: sampleRate).int16PCM(dither: dither, seed: seed)
    }

    private static func sinc(_ x: Double) -> Double {
        guard abs(x) > 1e-12 else { return 1 }
        let angle = Double.pi * x
        return sin(angle) / angle
    }

    private static func modifiedBesselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let quarterSquare = x * x / 4
        for index in 1...32 {
            term *= quarterSquare / Double(index * index)
            sum += term
            if term < sum * 1e-16 { break }
        }
        return sum
    }
}

private struct AudioDitherGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func nextTPDF() -> Double {
        uniform() - uniform()
    }

    private mutating func uniform() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let value = state &* 0x2545_F491_4F6C_DD1D
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }
}
