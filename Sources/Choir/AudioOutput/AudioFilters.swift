import Foundation

/// Audio signal processing filters and effects.
public struct AudioFilters: Sendable {
    // MARK: - Filter Constants
    @usableFromInline static let defaultHighPassCutoff: Double = 80.0
    @usableFromInline static let defaultLowPassCutoff: Double = 8000.0
    @usableFromInline static let defaultNormalizationTarget: Double = -6.0
    @usableFromInline static let defaultSoftClipThreshold: Double = 0.9
    @usableFromInline static let defaultSibilantFrequency: Double = 6000.0
    @usableFromInline static let sibilantFilterRatio: Double = 0.8
    @usableFromInline static let deEsserDryMix: Double = 0.8
    @usableFromInline static let deEsserWetMix: Double = 0.2
    @usableFromInline static let defaultReverbDelay: Int = 50
    @usableFromInline static let defaultReverbWetLevel: Double = 0.3
    @usableFromInline static let pcmMaxValue: Double = 32767.0
    @usableFromInline static let pcmMinValue: Int16 = -32768
    @usableFromInline static let pcmMaxValueInt: Int16 = 32767

    public init() {}

    /// Applies high-pass filter to remove low-frequency noise.
    ///
    /// - Parameters:
    ///   - samples: PCM audio samples.
    ///   - cutoffFrequency: High-pass cutoff in Hz (default 80 Hz).
    ///   - sampleRate: Sample rate in Hz.
    /// - Returns: Filtered samples.
    public func highPassFilter(
        _ samples: [Int16],
        cutoffFrequency: Double = defaultHighPassCutoff,
        sampleRate: Int = 48000
    ) -> [Int16] {
        // Simple RC high-pass filter
        let rc = 1.0 / (2.0 * .pi * cutoffFrequency)
        let dt = 1.0 / Double(sampleRate)
        let alpha = rc / (rc + dt)

        var filtered: [Int16] = []
        var prevOutput = 0.0
        var prevInput = 0.0

        for sample in samples {
            let input = Double(sample)
            let output = alpha * (prevOutput + input - prevInput)

            filtered.append(Int16(max(Self.pcmMinValue, min(Self.pcmMaxValueInt, Int16(output)))))

            prevOutput = output
            prevInput = input
        }

        return filtered
    }

    /// Applies low-pass filter to smooth high frequencies.
    ///
    /// - Parameters:
    ///   - samples: PCM audio samples.
    ///   - cutoffFrequency: Low-pass cutoff in Hz (default 8000 Hz).
    ///   - sampleRate: Sample rate in Hz.
    /// - Returns: Filtered samples.
    public func lowPassFilter(
        _ samples: [Int16],
        cutoffFrequency: Double = defaultLowPassCutoff,
        sampleRate: Int = 48000
    ) -> [Int16] {
        // Simple RC low-pass filter
        let rc = 1.0 / (2.0 * .pi * cutoffFrequency)
        let dt = 1.0 / Double(sampleRate)
        let alpha = dt / (rc + dt)

        var filtered: [Int16] = []
        var prevOutput = 0.0

        for sample in samples {
            let input = Double(sample)
            let output = prevOutput + alpha * (input - prevOutput)

            filtered.append(Int16(max(Self.pcmMinValue, min(Self.pcmMaxValueInt, Int16(output)))))
            prevOutput = output
        }

        return filtered
    }

    /// Applies normalization to prevent clipping.
    ///
    /// - Parameters:
    ///   - samples: PCM audio samples.
    ///   - targetLevel: Target RMS level (-20 to 0 dB, default -6 dB).
    /// - Returns: Normalized samples.
    public func normalize(
        _ samples: [Int16],
        targetLevel: Double = defaultNormalizationTarget
    ) -> [Int16] {
        guard !samples.isEmpty else { return samples }

        // Calculate RMS
        let sumSquares = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = sqrt(sumSquares / Double(samples.count))

        guard rms > 0 else { return samples }

        // Calculate gain to reach target level
        let targetLinear = pow(10.0, targetLevel / 20.0)
        let gain = targetLinear / (rms / Self.pcmMaxValue)

        // Apply gain with clipping protection
        return samples.map { sample in
            let scaled = Double(sample) * gain
            return Int16(max(Self.pcmMinValue, min(Self.pcmMaxValueInt, Int16(scaled))))
        }
    }

    /// Applies soft clipping to prevent harsh distortion.
    ///
    /// - Parameters:
    ///   - samples: PCM audio samples.
    ///   - threshold: Clipping threshold (0.0 to 1.0 of max).
    /// - Returns: Clipped samples.
    public func softClip(
        _ samples: [Int16],
        threshold: Double = defaultSoftClipThreshold
    ) -> [Int16] {
        let thresholdValue = Int16(Self.pcmMaxValue * threshold)

        return samples.map { sample in
            if abs(sample) <= thresholdValue {
                return sample
            }

            // Soft clipping using tanh approximation
            let normalized = Double(sample) / Self.pcmMaxValue
            let clipped = tanh(normalized)
            return Int16(clipped * Self.pcmMaxValue)
        }
    }

    /// Applies de-esser to reduce sibilance.
    ///
    /// - Parameters:
    ///   - samples: PCM audio samples.
    ///   - sibilantFrequency: Center frequency for sibilance (default 6000 Hz).
    ///   - sampleRate: Sample rate in Hz.
    /// - Returns: De-essed samples.
    public func deEsser(
        _ samples: [Int16],
        sibilantFrequency: Double = defaultSibilantFrequency,
        sampleRate: Int = 48000
    ) -> [Int16] {
        // Simplified de-esser: reduce energy in sibilant frequency range
        let filtered = lowPassFilter(samples, cutoffFrequency: sibilantFrequency, sampleRate: sampleRate)
        let highpassed = highPassFilter(filtered, cutoffFrequency: sibilantFrequency * Self.sibilantFilterRatio, sampleRate: sampleRate)

        // Mix: 80% original, 20% filtered (reduces sibilance)
        return zip(samples, highpassed).map { original, filtered in
            let mixed = Double(original) * Self.deEsserDryMix + Double(filtered) * Self.deEsserWetMix
            return Int16(max(Self.pcmMinValue, min(Self.pcmMaxValueInt, Int16(mixed))))
        }
    }

    /// Applies simple compression to control dynamic range.
    ///
    /// - Parameters:
    ///   - samples: PCM audio samples.
    ///   - threshold: Threshold in dB below which no compression.
    ///   - ratio: Compression ratio (e.g., 4:1).
    /// - Returns: Compressed samples.
    public func compress(
        _ samples: [Int16],
        threshold: Double = -20.0,
        ratio: Double = 4.0
    ) -> [Int16] {
        let thresholdLinear = pow(10.0, threshold / 20.0) * Self.pcmMaxValue

        return samples.map { sample in
            let absValue = Double(abs(sample))

            if absValue <= thresholdLinear {
                return sample
            }

            // Above threshold: reduce by ratio
            let overshoot = absValue - thresholdLinear
            let compressed = thresholdLinear + overshoot / ratio
            let sign = sample >= 0 ? 1 : -1

            return Int16(compressed * Double(sign))
        }
    }

    /// Applies reverb effect (simple implementation).
    ///
    /// - Parameters:
    ///   - samples: PCM audio samples.
    ///   - wetLevel: Mix level of reverb (0.0 to 1.0).
    ///   - sampleRate: Sample rate in Hz.
    /// - Returns: Reverb-processed samples.
    public func reverb(
        _ samples: [Int16],
        wetLevel: Double = defaultReverbWetLevel,
        sampleRate: Int = 48000
    ) -> [Int16] {
        let delaySamples = (Self.defaultReverbDelay * sampleRate) / 1000

        var output = Array(samples)

        // Simple delay line effect
        for i in delaySamples..<samples.count {
            let delayed = Double(samples[i - delaySamples])
            let current = Double(samples[i])
            let mixed = current * (1.0 - wetLevel) + delayed * wetLevel

            output[i] = Int16(max(Self.pcmMinValue, min(Self.pcmMaxValueInt, Int16(mixed))))
        }

        return output
    }
}
