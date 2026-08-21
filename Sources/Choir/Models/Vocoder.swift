import Foundation

/// Protocol for vocoders (feature-to-waveform conversion).
public protocol VocoderProtocol: Sendable {
    /// Converts acoustic features to PCM audio samples.
    ///
    /// - Parameters:
    ///   - features: Acoustic features (Mel-spectrogram or similar).
    ///   - sampleRate: Target sample rate in Hz.
    /// - Returns: PCM samples as 16-bit integers.
    /// - Throws: `ChoirError` if vocoding fails.
    func synthesize(features: AcousticFeatures, sampleRate: Int) async throws -> [Int16]
}

private enum VocoderSafetyLimits {
    static let maximumFrames = 600_000
    static let maximumFrequencyBins = 4_096
    static let maximumFrameRate = 1_000
    static let maximumDurationSeconds = 600.0
    static let maximumFFTSize = 16_384
    static let maximumWorkingElements = 100_000_000
    static let maximumRenderedSamples = 50_000_000
}

/// Adapter for an Xcode-generated Core ML neural-vocoder model.
///
/// The asset target owns the generated model type and tensor names; this
/// adapter keeps those checkpoint-specific details behind one validated,
/// sendable closure while allowing the synthesis pipeline to use a real Core
/// ML vocoder without source changes.
public struct CoreMLVocoder: VocoderProtocol {
    public typealias Inference = @Sendable (AcousticFeatures, Int) async throws -> [Int16]

    private let inference: Inference

    public init(inference: @escaping Inference) {
        self.inference = inference
    }

    public func synthesize(features: AcousticFeatures, sampleRate: Int) async throws -> [Int16] {
        guard features.frameCount > 0,
              features.frameCount <= VocoderSafetyLimits.maximumFrames,
              features.frequencyBins > 0,
              features.frequencyBins <= VocoderSafetyLimits.maximumFrequencyBins,
              features.isRectangular,
              features.containsOnlyFiniteValues else {
            throw ChoirError.synthesisError(
                reason: "Core ML vocoder requires a non-empty rectangular finite feature tensor")
        }
        guard sampleRate >= 8_000, sampleRate <= 384_000 else {
            throw ChoirError.invalidParameter(
                parameter: "sampleRate", reason: "Sample rate must be within 8,000...384,000 Hz")
        }
        guard (1...VocoderSafetyLimits.maximumFrameRate).contains(features.frameRate),
              features.duration.isFinite,
              features.duration <= VocoderSafetyLimits.maximumDurationSeconds else {
            throw ChoirError.invalidParameter(
                parameter: "features",
                reason: "Feature frame rate/duration exceeds the bounded vocoder contract")
        }

        do {
            let samples = try await inference(features, sampleRate)
            guard !samples.isEmpty else {
                throw ChoirError.synthesisError(
                    reason: "Core ML vocoder returned an empty waveform")
            }
            return samples
        } catch let error as ChoirError {
            throw error
        } catch {
            throw ChoirError.synthesisError(
                reason: "Core ML vocoder inference failed: \(error.localizedDescription)")
        }
    }
}

/// Deterministic spectral fallback using phase reconstruction.
///
/// This is useful for integration tests and diagnostics, but it is not the
/// production neural asset required by ML-V-001. Production applications
/// should inject ``CoreMLVocoder`` with the shipped Core ML vocoder.
public struct NeuralVocoder: VocoderProtocol {
    /// Number of frequency bins in the spectrogram.
    private let frequencyBins: Int

    /// Sample rate for reconstruction.
    private let referenceRate: Int

    public init(frequencyBins: Int = 80, referenceRate: Int = 48000) {
        self.frequencyBins = min(
            VocoderSafetyLimits.maximumFrequencyBins,
            max(2, frequencyBins))
        self.referenceRate = min(384_000, max(8_000, referenceRate))
    }

    public func synthesize(features: AcousticFeatures, sampleRate: Int) async throws -> [Int16] {
        guard features.frameCount > 0,
              features.frameCount <= VocoderSafetyLimits.maximumFrames else {
            throw ChoirError.synthesisError(reason: "Empty acoustic features")
        }
        guard sampleRate >= 8_000, sampleRate <= 384_000 else {
            throw ChoirError.invalidParameter(
                parameter: "sampleRate", reason: "Sample rate must be within 8,000...384,000 Hz")
        }
        guard features.isRectangular, features.containsOnlyFiniteValues else {
            throw ChoirError.synthesisError(
                reason: "Acoustic features must be rectangular and contain only finite values")
        }
        guard features.frequencyBins == frequencyBins else {
            throw ChoirError.invalidParameter(
                parameter: "features",
                reason: "Expected \(frequencyBins) frequency bins, received \(features.frequencyBins)")
        }
        guard (1...VocoderSafetyLimits.maximumFrameRate).contains(features.frameRate),
              features.duration.isFinite,
              features.duration <= VocoderSafetyLimits.maximumDurationSeconds else {
            throw ChoirError.invalidParameter(
                parameter: "features",
                reason: "Feature frame rate/duration exceeds the bounded vocoder contract")
        }

        // Convert Mel-spectrogram to linear spectrogram
        let linearSpec = melToLinear(features.features)

        // Reconstruct phase using Griffin-Lim algorithm
        let complexSpec = reconstructPhase(linearSpec, iterations: 10)

        // The acoustic tensor's frame rate defines time. Deriving the hop only
        // from the FFT size made 50 Hz features about 15x too short at 48 kHz.
        let featureFrameRate = max(1, features.frameRate)
        let hopSize = max(
            1,
            Int((Double(referenceRate) / Double(featureFrameRate)).rounded()))
        let expectedSampleCountValue = (features.duration * Double(referenceRate)).rounded()
        guard expectedSampleCountValue.isFinite,
              expectedSampleCountValue >= 1,
              expectedSampleCountValue <= Double(VocoderSafetyLimits.maximumRenderedSamples) else {
            throw ChoirError.invalidParameter(
                parameter: "features",
                reason: "Requested fallback waveform exceeds the bounded sample limit")
        }
        let expectedSampleCount = Int(expectedSampleCountValue)

        // Inverse FFT to time domain. Keep at least 50% overlap even when a
        // tiny diagnostic feature tensor has far fewer bins than production.
        let doubledBins = frequencyBins.multipliedReportingOverflow(by: 2)
        let doubledHop = hopSize.multipliedReportingOverflow(by: 2)
        guard !doubledBins.overflow, !doubledHop.overflow else {
            throw ChoirError.outOfMemory
        }
        let requiredFrameSize = max(doubledBins.partialValue, doubledHop.partialValue)
        guard requiredFrameSize <= VocoderSafetyLimits.maximumFFTSize,
              let frameSize = Self.nextPowerOfTwo(requiredFrameSize) else {
            throw ChoirError.invalidParameter(
                parameter: "features",
                reason: "Feature rate requires an unsupported reconstruction window")
        }
        let workingElements = features.frameCount.multipliedReportingOverflow(by: frameSize)
        guard !workingElements.overflow,
              workingElements.partialValue <= VocoderSafetyLimits.maximumWorkingElements else {
            throw ChoirError.outOfMemory
        }
        let waveform = inverseFFT(complexSpec, frameSize: frameSize)

        // Apply overlap-add windowing
        let smoothed = try overlapAdd(
            waveform,
            frameSize: frameSize,
            hopSize: hopSize,
            outputCount: expectedSampleCount)

        // Resample if needed
        let resampled = try resample(smoothed, from: referenceRate, to: sampleRate)

        // Convert to 16-bit PCM with normalization
        let pcm = toPCM16(resampled)

        return pcm
    }

    /// Converts Mel-spectrogram to linear spectrogram (inverse Mel scale).
    private func melToLinear(_ melSpec: [[Float]]) -> [[Float]] {
        var linear: [[Float]] = []

        for melFrame in melSpec {
            var linearFrame: [Float] = []

            for melValue in melFrame {
                // Inverse Mel scale formula (simplified)
                // Linear frequency = 700 * (10^(mel/2595) - 1)
                let mel = Double(melValue)
                let frequency = 700.0 * (pow(10.0, mel / 2595.0) - 1.0)

                // Exponential scaling to approximate inverse Mel
                let linearValue = Float(frequency / 4000.0)
                linearFrame.append(exp(linearValue))
            }

            linear.append(linearFrame)
        }

        return linear
    }

    /// Reconstructs phase using Griffin-Lim algorithm.
    private func reconstructPhase(_ spec: [[Float]], iterations: Int) -> [[Complex]] {
        var complexSpec: [[Complex]] = []

        // Initialize with deterministic low-discrepancy phase. Random phase
        // made an otherwise seeded synthesis request produce different bytes
        // on every render, violating SYN-002.
        for (frameIndex, frame) in spec.enumerated() {
            var complexFrame: [Complex] = []
            for (binIndex, magnitude) in frame.enumerated() {
                let phaseIndex = (frameIndex &* 131 &+ binIndex &* 197) % 1024
                let phase = Float(phaseIndex) / 1024 * 2 * .pi
                let complex = Complex(real: magnitude * cos(phase), imag: magnitude * sin(phase))
                complexFrame.append(complex)
            }
            complexSpec.append(complexFrame)
        }

        // Smooth phase progression across frames. This deterministic fallback
        // is deliberately bounded; production releases still require the
        // Core ML neural vocoder asset and its quality gates.
        for _ in 0..<iterations {
            guard complexSpec.count > 1 else { break }
            for frameIndex in 1..<complexSpec.count {
                for binIndex in complexSpec[frameIndex].indices {
                    let current = complexSpec[frameIndex][binIndex]
                    let previous = complexSpec[frameIndex - 1][binIndex]
                    let magnitude = current.magnitude
                    let blendedPhase = current.phase * 0.75 + previous.phase * 0.25
                    complexSpec[frameIndex][binIndex] = Complex(
                        real: magnitude * cos(blendedPhase),
                        imag: magnitude * sin(blendedPhase))
                }
            }
        }

        return complexSpec
    }

    /// Performs an O(n log n) radix-2 inverse FFT on each spectral frame.
    private func inverseFFT(_ spec: [[Complex]], frameSize: Int) -> [[Float]] {
        spec.map { frame in
            var spectrum = Array(repeating: Complex(real: 0, imag: 0), count: frameSize)
            let positiveBinCount = min(frame.count, frameSize / 2 + 1)
            for bin in 0..<positiveBinCount {
                spectrum[bin] = frame[bin]
                let mirror = frameSize - bin
                if bin > 0, mirror < frameSize, mirror != bin {
                    spectrum[mirror] = Complex(real: frame[bin].real, imag: -frame[bin].imag)
                }
            }
            Self.radixTwoTransform(&spectrum, inverse: true)
            return spectrum.map(\.real)
        }
    }

    /// Applies overlap-add windowing to smooth frame transitions.
    private func overlapAdd(
        _ waveform: [[Float]],
        frameSize: Int,
        hopSize: Int,
        outputCount: Int
    ) throws -> [Float] {
        guard !waveform.isEmpty else { return [] }
        let stepped = (waveform.count - 1).multipliedReportingOverflow(by: hopSize)
        guard !stepped.overflow else { throw ChoirError.outOfMemory }
        let rendered = stepped.partialValue.addingReportingOverflow(frameSize)
        guard !rendered.overflow,
              rendered.partialValue <= VocoderSafetyLimits.maximumRenderedSamples
                + VocoderSafetyLimits.maximumFFTSize else {
            throw ChoirError.outOfMemory
        }
        let renderedCount = rendered.partialValue
        var output = Array(repeating: Float(0), count: renderedCount)
        var windowWeight = Array(repeating: Float(0), count: renderedCount)
        let denominator = Double(max(1, frameSize - 1))
        let window: [Float] = (0..<frameSize).map { index in
            Float(0.5 - 0.5 * cos(2 * .pi * Double(index) / denominator))
        }

        for (frameIdx, frame) in waveform.enumerated() {
            let startIdx = frameIdx * hopSize

            for i in 0..<min(frame.count, frameSize) {
                let windowValue = window[i]
                output[startIdx + i] += frame[i] * windowValue
                windowWeight[startIdx + i] += windowValue * windowValue
            }
        }

        for index in output.indices where windowWeight[index] > 0.000_001 {
            output[index] /= windowWeight[index]
        }

        if output.count > outputCount {
            return Array(output.prefix(outputCount))
        }
        if output.count < outputCount {
            output.append(contentsOf: repeatElement(0, count: outputCount - output.count))
        }
        return output
    }

    /// Resamples waveform to a different sample rate.
    private func resample(
        _ waveform: [Float],
        from inputRate: Int,
        to outputRate: Int
    ) throws -> [Float] {
        guard inputRate != outputRate else { return waveform }

        let ratio = Double(outputRate) / Double(inputRate)
        let outputLengthValue = Double(waveform.count) * ratio
        guard outputLengthValue.isFinite,
              outputLengthValue >= 0,
              outputLengthValue <= Double(VocoderSafetyLimits.maximumRenderedSamples) else {
            throw ChoirError.outOfMemory
        }
        let outputLength = Int(outputLengthValue)

        var resampled: [Float] = []

        for i in 0..<outputLength {
            let inputIdx = Double(i) / ratio
            let index = Int(inputIdx)
            let frac = Float(inputIdx - Double(index))

            if index < waveform.count - 1 {
                // Linear interpolation
                let value = waveform[index] * (1.0 - frac) + waveform[index + 1] * frac
                resampled.append(value)
            } else if index < waveform.count {
                resampled.append(waveform[index])
            }
        }

        return resampled
    }

    /// Converts normalized float samples to 16-bit PCM.
    private func toPCM16(_ samples: [Float]) -> [Int16] {
        // Find max for normalization
        let maxValue = samples.map(abs).max() ?? 1.0

        let normalized = samples.map { sample in
            let scaled = (sample / (maxValue + 0.001)) * 32767.0
            return Int16(max(-32768, min(32767, scaled)))
        }

        return normalized
    }

    private static func nextPowerOfTwo(_ value: Int) -> Int? {
        guard value > 0, value <= VocoderSafetyLimits.maximumFFTSize else { return nil }
        var result = 1
        while result < value {
            let doubled = result.multipliedReportingOverflow(by: 2)
            guard !doubled.overflow else { return nil }
            result = doubled.partialValue
        }
        return result
    }

    /// In-place iterative Cooley-Tukey transform. The input length must be a
    /// power of two; callers enforce that through ``nextPowerOfTwo(_:)``.
    private static func radixTwoTransform(_ values: inout [Complex], inverse: Bool) {
        let count = values.count
        guard count > 1, count.nonzeroBitCount == 1 else { return }

        var j = 0
        for i in 1..<count {
            var bit = count >> 1
            while (j & bit) != 0 {
                j ^= bit
                bit >>= 1
            }
            j ^= bit
            if i < j { values.swapAt(i, j) }
        }

        var length = 2
        while length <= count {
            let angle = (inverse ? 2 : -2) * Float.pi / Float(length)
            let root = Complex(real: cos(angle), imag: sin(angle))
            let half = length / 2
            var start = 0
            while start < count {
                var factor = Complex(real: 1, imag: 0)
                for offset in 0..<half {
                    let even = values[start + offset]
                    let oddSource = values[start + offset + half]
                    let odd = Complex(
                        real: oddSource.real * factor.real - oddSource.imag * factor.imag,
                        imag: oddSource.real * factor.imag + oddSource.imag * factor.real)
                    values[start + offset] = Complex(
                        real: even.real + odd.real,
                        imag: even.imag + odd.imag)
                    values[start + offset + half] = Complex(
                        real: even.real - odd.real,
                        imag: even.imag - odd.imag)
                    factor = Complex(
                        real: factor.real * root.real - factor.imag * root.imag,
                        imag: factor.real * root.imag + factor.imag * root.real)
                }
                start += length
            }
            length <<= 1
        }

        if inverse {
            let scale = Float(count)
            for index in values.indices {
                values[index].real /= scale
                values[index].imag /= scale
            }
        }
    }
}

/// Simple complex number representation.
private struct Complex: Sendable {
    var real: Float
    var imag: Float

    var magnitude: Float {
        sqrt(real * real + imag * imag)
    }

    var phase: Float {
        atan2(imag, real)
    }
}

/// Mock vocoder for testing.
public struct MockVocoder: VocoderProtocol {
    public init() {}

    public func synthesize(features: AcousticFeatures, sampleRate: Int) async throws -> [Int16] {
        guard features.frameCount > 0,
              features.frameCount <= VocoderSafetyLimits.maximumFrames,
              features.frequencyBins > 0,
              features.frequencyBins <= VocoderSafetyLimits.maximumFrequencyBins,
              features.isRectangular,
              features.containsOnlyFiniteValues,
              (1...VocoderSafetyLimits.maximumFrameRate).contains(features.frameRate),
              features.duration.isFinite,
              features.duration <= VocoderSafetyLimits.maximumDurationSeconds else {
            throw ChoirError.invalidParameter(
                parameter: "features", reason: "Invalid or unbounded acoustic features")
        }
        guard (8_000...384_000).contains(sampleRate) else {
            throw ChoirError.invalidParameter(
                parameter: "sampleRate", reason: "Sample rate must be within 8,000...384,000 Hz")
        }
        // Generate sine wave at nominal pitch (200 Hz)
        let duration = features.duration
        let sampleCountValue = duration * Double(sampleRate)
        guard sampleCountValue.isFinite,
              sampleCountValue >= 1,
              sampleCountValue <= Double(VocoderSafetyLimits.maximumRenderedSamples) else {
            throw ChoirError.outOfMemory
        }
        let sampleCount = Int(sampleCountValue)

        var samples: [Int16] = []
        let frequency = 200.0
        let amplitude: Int16 = 16000

        for i in 0..<sampleCount {
            let time = Double(i) / Double(sampleRate)
            let phase = 2.0 * .pi * frequency * time
            let sample = Int16(Double(amplitude) * sin(phase))
            samples.append(sample)
        }

        return samples
    }
}
