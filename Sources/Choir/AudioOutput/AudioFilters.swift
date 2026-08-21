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
        guard value.isFinite else { return 0 }
        if value <= Double(pcmMinValue) { return pcmMinValue }
        if value >= Double(pcmMaxValueInt) { return pcmMaxValueInt }
        return Int16(value)
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
        guard !samples.isEmpty,
              sampleRate > 0,
              cutoffFrequency.isFinite,
              cutoffFrequency > 0 else { return samples }
        let effectiveCutoff = min(cutoffFrequency, Double(sampleRate) * 0.499)
        // Simple RC high-pass filter
        let rc = 1.0 / (2.0 * .pi * effectiveCutoff)
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
        guard !samples.isEmpty,
              sampleRate > 0,
              cutoffFrequency.isFinite,
              cutoffFrequency > 0 else { return samples }
        let effectiveCutoff = min(cutoffFrequency, Double(sampleRate) * 0.499)
        // Simple RC low-pass filter
        let rc = 1.0 / (2.0 * .pi * effectiveCutoff)
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
        let effectiveTarget = targetLevel.isFinite
            ? max(-20, min(0, targetLevel))
            : Self.defaultNormalizationTarget
        let targetLinear = pow(10.0, effectiveTarget / 20.0)
        let gain = targetLinear / (rms / Self.pcmMaxValue)

        // Apply gain with clipping protection
        return samples.map { sample in
            let scaled = Double(sample) * gain
            return Self.clampToPCM(scaled)
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
        let effectiveThreshold = threshold.isFinite
            ? max(0, min(1, threshold))
            : Self.defaultSoftClipThreshold
        let thresholdValue = Int16(Self.pcmMaxValue * effectiveThreshold)

        return samples.map { sample in
            if sample.magnitude <= thresholdValue.magnitude {
                return sample
            }

            // Soft clipping using tanh approximation
            let normalized = Double(sample) / Self.pcmMaxValue
            let clipped = tanh(normalized)
            return Self.clampToPCM(clipped * Self.pcmMaxValue)
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
        guard !samples.isEmpty,
              sampleRate > 0,
              sibilantFrequency.isFinite,
              sibilantFrequency > 0 else { return samples }
        // Simplified de-esser: reduce energy in sibilant frequency range
        let filtered = lowPassFilter(samples, cutoffFrequency: sibilantFrequency, sampleRate: sampleRate)
        let highpassed = highPassFilter(filtered, cutoffFrequency: sibilantFrequency * Self.sibilantFilterRatio, sampleRate: sampleRate)

        // Subtract the detected band. Adding it back to a quieter dry signal
        // increases relative sibilance, which is the opposite of de-essing.
        return zip(samples, highpassed).map { original, sibilantBand in
            let mixed = Double(original) - Double(sibilantBand) * Self.deEsserWetMix
            return Self.clampToPCM(mixed)
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
        let effectiveThreshold = threshold.isFinite ? max(-120, min(0, threshold)) : -20
        let effectiveRatio = ratio.isFinite ? max(1, ratio) : 1
        let thresholdLinear = pow(10.0, effectiveThreshold / 20.0) * Self.pcmMaxValue

        return samples.map { sample in
            let absValue = abs(Double(sample))

            if absValue <= thresholdLinear {
                return sample
            }

            // Above threshold: reduce by ratio
            let overshoot = absValue - thresholdLinear
            let compressed = thresholdLinear + overshoot / effectiveRatio
            let sign = sample >= 0 ? 1 : -1

            return Self.clampToPCM(compressed * Double(sign))
        }
    }

    /// Removes per-channel DC bias from interleaved PCM.
    public func removeDCOffset(_ samples: [Int16], channels: Int = 1) -> [Int16] {
        guard channels > 0,
              samples.count.isMultiple(of: channels),
              !samples.isEmpty else { return samples }
        let frames = samples.count / channels
        var means = [Double](repeating: 0, count: channels)
        for frame in 0..<frames {
            for channel in 0..<channels {
                means[channel] += Double(samples[frame * channels + channel])
            }
        }
        means = means.map { $0 / Double(frames) }
        return samples.enumerated().map { index, sample in
            Self.clampToPCM(Double(sample) - means[index % channels])
        }
    }

    /// Applies a linear click-prevention fade to both utterance edges.
    /// Durations are bounded to the AUD-021 maximum of five milliseconds.
    public func fadeEdges(
        _ samples: [Int16],
        durationMilliseconds: Double = 5,
        sampleRate: Int = 48_000,
        channels: Int = 1
    ) -> [Int16] {
        guard sampleRate > 0,
              channels > 0,
              samples.count.isMultiple(of: channels),
              durationMilliseconds.isFinite,
              durationMilliseconds > 0,
              !samples.isEmpty else { return samples }
        let frameCount = samples.count / channels
        let boundedDuration = min(5, durationMilliseconds)
        let requestedFrames = Int(
            (boundedDuration / 1_000 * Double(sampleRate)).rounded(.up))
        let fadeFrames = min(requestedFrames, max(1, frameCount / 2))
        var output = samples
        for frame in 0..<fadeFrames {
            let gain = Double(frame) / Double(max(1, fadeFrames - 1))
            let endFrame = frameCount - 1 - frame
            for channel in 0..<channels {
                output[frame * channels + channel] = Self.clampToPCM(
                    Double(output[frame * channels + channel]) * gain)
                output[endFrame * channels + channel] = Self.clampToPCM(
                    Double(output[endFrame * channels + channel]) * gain)
            }
        }
        return output
    }

    /// A soft-knee, infinite-ratio limiter for gentle broadcast mastering.
    public func softKneeLimiter(
        _ samples: [Int16],
        ceilingDB: Double = -1,
        kneeWidthDB: Double = 3
    ) -> [Int16] {
        let ceiling = ceilingDB.isFinite ? min(0, max(-24, ceilingDB)) : -1
        let knee = kneeWidthDB.isFinite ? min(24, max(0, kneeWidthDB)) : 3
        let kneeStart = ceiling - knee / 2
        let kneeEnd = ceiling + knee / 2

        return samples.map { sample in
            let magnitude = abs(Double(sample)) / Self.pcmMaxValue
            guard magnitude > 0 else { return 0 }
            let inputDB = 20 * log10(magnitude)
            let outputDB: Double
            if knee == 0 {
                outputDB = min(inputDB, ceiling)
            } else if inputDB <= kneeStart {
                outputDB = inputDB
            } else if inputDB < kneeEnd {
                let distance = inputDB - kneeStart
                outputDB = inputDB - distance * distance / (2 * knee)
            } else {
                outputDB = ceiling
            }
            let outputMagnitude = pow(10, outputDB / 20) * Self.pcmMaxValue
            return Self.clampToPCM(sample < 0 ? -outputMagnitude : outputMagnitude)
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
        guard !samples.isEmpty, sampleRate > 0 else { return samples }
        let effectiveWetLevel = wetLevel.isFinite ? max(0, min(1, wetLevel)) : 0
        let delaySamples = (Self.defaultReverbDelay * sampleRate) / 1000

        var output = Array(samples)

        // Buffers shorter than the delay line have nothing to reflect yet.
        guard delaySamples < samples.count else { return output }

        // Simple delay line effect
        for i in delaySamples..<samples.count {
            let delayed = Double(samples[i - delaySamples])
            let current = Double(samples[i])
            let mixed = current * (1.0 - effectiveWetLevel) + delayed * effectiveWetLevel

            output[i] = Self.clampToPCM(mixed)
        }

        return output
    }
}
