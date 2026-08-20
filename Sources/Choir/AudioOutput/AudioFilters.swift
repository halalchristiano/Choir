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

    /// Clamps a sample to the representable PCM range before narrowing to `Int16`.
    ///
    /// Converting first and clamping afterwards traps at runtime, because the
    /// `Int16(_:)` initializer requires the value to already be in range.
    @usableFromInline
    static func clampToPCM(_ value: Double) -> Int16 {
        // NaN compares false against everything, so it would fall past both
        // bounds and trap in `Int16(_:)`. Silence is the safe reading.
        guard !value.isNaN else { return 0 }
        if value <= Double(pcmMinValue) { return pcmMinValue }
        if value >= Double(pcmMaxValueInt) { return pcmMaxValueInt }
        return Int16(value)
    }

    /// Magnitude of a PCM sample, widened so the asymmetric minimum survives.
    ///
    /// `abs(Int16.min)` traps: the magnitude of -32768 is 32768, which is not
    /// representable as an `Int16`. -32768 is an ordinary full-scale sample,
    /// so every magnitude comparison has to widen before negating.
    @usableFromInline
    static func magnitude(_ sample: Int16) -> Int {
        abs(Int(sample))
    }

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
        // A zero cutoff makes the RC constant infinite and alpha NaN, which
        // would poison every sample in the buffer. Nothing to filter, so pass through.
        guard cutoffFrequency > 0, sampleRate > 0 else { return samples }

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

            filtered.append(Self.clampToPCM(output))

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
        // See `highPassFilter`: a non-positive cutoff or rate yields a NaN alpha.
        guard cutoffFrequency > 0, sampleRate > 0 else { return samples }

        // Simple RC low-pass filter
        let rc = 1.0 / (2.0 * .pi * cutoffFrequency)
        let dt = 1.0 / Double(sampleRate)
        let alpha = dt / (rc + dt)

        var filtered: [Int16] = []
        var prevOutput = 0.0

        for sample in samples {
            let input = Double(sample)
            let output = prevOutput + alpha * (input - prevOutput)

            filtered.append(Self.clampToPCM(output))
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
            return Self.clampToPCM(scaled)
        }
    }

    /// Applies soft clipping to prevent harsh distortion.
    ///
    /// Samples below the threshold pass through untouched; above it the
    /// overshoot is bent through `tanh` so the curve leaves the knee at the
    /// same value and the same slope, and approaches full scale without ever
    /// reaching it. Shaping the whole sample rather than the overshoot puts a
    /// step at the knee — at the default threshold a sample one LSB above it
    /// dropped by roughly 6,000 — which is the harsh distortion this is
    /// supposed to avoid.
    ///
    /// - Parameters:
    ///   - samples: PCM audio samples.
    ///   - threshold: Clipping threshold (0.0 to 1.0 of max). Values outside
    ///     that range are clamped; a threshold of 1.0 leaves the buffer alone.
    /// - Returns: Clipped samples.
    public func softClip(
        _ samples: [Int16],
        threshold: Double = defaultSoftClipThreshold
    ) -> [Int16] {
        // `Int16(32767 * threshold)` trapped for any threshold above 1.0, and
        // this is public API reachable through AudioEffectChain.
        let knee = threshold.isNaN ? Self.defaultSoftClipThreshold : min(max(threshold, 0.0), 1.0)
        let headroom = 1.0 - knee
        guard headroom > 0 else { return samples }

        return samples.map { sample in
            // Normalize first: `abs` on a Double cannot overflow, while
            // `abs(Int16.min)` traps.
            let normalized = Double(sample) / Self.pcmMaxValue
            let level = abs(normalized)
            guard level > knee else { return sample }

            let shaped = knee + headroom * tanh((level - knee) / headroom)
            return Self.clampToPCM(copysign(shaped, normalized) * Self.pcmMaxValue)
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
            return Self.clampToPCM(mixed)
        }
    }

    /// Applies simple compression to control dynamic range.
    ///
    /// - Parameters:
    ///   - samples: PCM audio samples.
    ///   - threshold: Threshold in dB below which no compression.
    ///   - ratio: Compression ratio (e.g., 4:1). Ratios below 1:1 expand rather
    ///     than compress and are treated as 1:1.
    /// - Returns: Compressed samples.
    public func compress(
        _ samples: [Int16],
        threshold: Double = -20.0,
        ratio: Double = 4.0
    ) -> [Int16] {
        // A ratio of 0 divided by zero and anything below 1:1 pushed the
        // overshoot past full scale, trapping in the unclamped `Int16(_:)` below.
        let safeRatio = (ratio.isNaN || ratio < 1.0) ? 1.0 : ratio
        let thresholdLinear = pow(10.0, threshold / 20.0) * Self.pcmMaxValue

        return samples.map { sample in
            // Take the magnitude in Double: `abs(Int16.min)` traps.
            let value = Double(sample)
            let absValue = abs(value)

            if absValue <= thresholdLinear {
                return sample
            }

            // Above threshold: reduce by ratio
            let overshoot = absValue - thresholdLinear
            let compressed = thresholdLinear + overshoot / safeRatio

            return Self.clampToPCM(copysign(compressed, value))
        }
    }

    /// Applies reverb effect (simple implementation).
    ///
    /// - Parameters:
    ///   - samples: PCM audio samples.
    ///   - wetLevel: Mix level of reverb (0.0 to 1.0). Values outside that
    ///     range are clamped.
    ///   - sampleRate: Sample rate in Hz.
    /// - Returns: Reverb-processed samples.
    public func reverb(
        _ samples: [Int16],
        wetLevel: Double = defaultReverbWetLevel,
        sampleRate: Int = 48000
    ) -> [Int16] {
        var output = Array(samples)

        // A negative rate gives a negative delay, which reads past the end of
        // the buffer instead of behind the write position.
        guard sampleRate > 0 else { return output }

        let wet = wetLevel.isNaN ? Self.defaultReverbWetLevel : min(max(wetLevel, 0.0), 1.0)
        let delaySamples = (Self.defaultReverbDelay * sampleRate) / 1000

        // Buffers shorter than the delay line have nothing to reflect yet.
        guard delaySamples < samples.count else { return output }

        // Simple delay line effect
        for i in delaySamples..<samples.count {
            let delayed = Double(samples[i - delaySamples])
            let current = Double(samples[i])
            let mixed = current * (1.0 - wet) + delayed * wet

            output[i] = Self.clampToPCM(mixed)
        }

        return output
    }
}
