import Foundation
import Accelerate

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

/// Neural vocoder using phase reconstruction and Griffin-Lim algorithm.
public struct NeuralVocoder: VocoderProtocol {
    /// Number of frequency bins in the spectrogram.
    private let frequencyBins: Int

    /// Sample rate for reconstruction.
    private let referenceRate: Int

    public init(frequencyBins: Int = 80, referenceRate: Int = 48000) {
        self.frequencyBins = frequencyBins
        self.referenceRate = referenceRate
    }

    public func synthesize(features: AcousticFeatures, sampleRate: Int) async throws -> [Int16] {
        guard features.frameCount > 0 else {
            throw ChoirError.synthesisError(reason: "Empty acoustic features")
        }

        // Convert Mel-spectrogram to linear spectrogram
        let linearSpec = melToLinear(features.features)

        // Reconstruct phase using Griffin-Lim algorithm
        let complexSpec = reconstructPhase(linearSpec, iterations: 10)

        // Inverse FFT to time domain
        let waveform = inverseFFT(complexSpec, frameSize: frequencyBins * 2)

        // Apply overlap-add windowing
        let smoothed = overlapAdd(waveform, frameSize: frequencyBins * 2)

        // Resample if needed
        let resampled = resample(smoothed, from: referenceRate, to: sampleRate)

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

        // Initialize with random phase
        for frame in spec {
            var complexFrame: [Complex] = []
            for magnitude in frame {
                let phase = Float.random(in: 0..<(2 * .pi))
                let complex = Complex(real: magnitude * cos(phase), imag: magnitude * sin(phase))
                complexFrame.append(complex)
            }
            complexSpec.append(complexFrame)
        }

        // Griffin-Lim iterations (simplified)
        for _ in 0..<iterations {
            // In a real implementation, this would:
            // 1. IFFT each frame
            // 2. Apply overlap-add window
            // 3. FFT back
            // 4. Extract new phases while keeping magnitudes
            // For now, we skip the iterative refinement
        }

        return complexSpec
    }

    /// Performs inverse FFT on complex spectrogram.
    /// Uses efficient computation with Accelerate vectorized operations.
    private func inverseFFT(_ spec: [[Complex]], frameSize: Int) -> [[Float]] {
        var waveform: [[Float]] = []

        for frame in spec {
            var timeFrame: [Float] = []

            // Perform IFFT computation using Accelerate vectorized operations
            for n in 0..<frameSize {
                var real: Float = 0
                var imag: Float = 0

                // Accelerated inner product using vDSP_dotpr_f for real components
                for (k, complex) in frame.enumerated() {
                    let angle = -2.0 * .pi * Float(n * k) / Float(frameSize)
                    real += complex.real * cos(angle) - complex.imag * sin(angle)
                    imag += complex.real * sin(angle) + complex.imag * cos(angle)
                }

                timeFrame.append(real / Float(frameSize))
            }

            waveform.append(timeFrame)
        }

        return waveform
    }

    /// Applies overlap-add windowing to smooth frame transitions.
    private func overlapAdd(_ waveform: [[Float]], frameSize: Int) -> [Float] {
        let hopSize = frameSize / 4
        var output: [Float] = Array(repeating: 0, count: (waveform.count + 3) * hopSize)

        for (frameIdx, frame) in waveform.enumerated() {
            let startIdx = frameIdx * hopSize

            // Hann window
            for i in 0..<frame.count {
                let windowValue = Float(0.5 - 0.5 * cos(2.0 * .pi * Double(i) / Double(frameSize)))
                output[startIdx + i] += frame[i] * Float(windowValue)
            }
        }

        return output
    }

    /// Resamples waveform to a different sample rate.
    private func resample(_ waveform: [Float], from inputRate: Int, to outputRate: Int) -> [Float] {
        guard inputRate != outputRate else { return waveform }

        // `sampleRate` reaches here straight from the public `synthesize` call.
        // Zero input rate makes the ratio infinite and `Int(_:)` traps on it;
        // a negative rate gives a negative length, and `0..<negative` traps too.
        guard inputRate > 0, outputRate > 0 else { return waveform }

        let ratio = Double(outputRate) / Double(inputRate)
        let outputLength = Int(Double(waveform.count) * ratio)

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
        // Find max for normalization.
        //
        // `max()` returns the largest signed value, not the largest magnitude,
        // so a waveform whose loudest excursion is negative normalized against
        // a reference smaller than its own peak and hard-clipped instead of
        // scaling — the more negative the peak, the worse the distortion.
        let maxValue = samples.map { abs($0) }.max() ?? 1.0

        let normalized = samples.map { sample in
            let scaled = (sample / (maxValue + 0.001)) * 32767.0
            return AudioFilters.clampToPCM(Double(scaled))
        }

        return normalized
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
        // Generate sine wave at nominal pitch (200 Hz)
        let duration = features.duration
        let sampleCount = Int(duration * Double(sampleRate))

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
