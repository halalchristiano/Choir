import Foundation

/// Common loudness targets for finished audio (AUD-020).
public enum LoudnessPreset: Sendable, Equatable, Hashable, Codable {
    case spokenWord
    case online
    case quietSpokenWord
    case custom(Double)

    public var targetLUFS: Double {
        switch self {
        case .spokenWord: -16
        case .online: -14
        case .quietSpokenWord: -19
        case .custom(let target): target
        }
    }
}

/// Settings for deterministic spoken-word mastering.
public struct AudioMasteringConfiguration: Sendable, Equatable {
    public var target: LoudnessPreset
    public var truePeakCeilingDBTP: Double
    public var fadeDurationMilliseconds: Double
    public var removesDCOffset: Bool

    public init(
        target: LoudnessPreset = .spokenWord,
        truePeakCeilingDBTP: Double = -1,
        fadeDurationMilliseconds: Double = 5,
        removesDCOffset: Bool = true
    ) {
        self.target = target
        self.truePeakCeilingDBTP = truePeakCeilingDBTP
        self.fadeDurationMilliseconds = fadeDurationMilliseconds
        self.removesDCOffset = removesDCOffset
    }

    public func validate() throws {
        guard target.targetLUFS.isFinite, -36 ... -5 ~= target.targetLUFS else {
            throw ChoirError.invalidParameter(
                parameter: "targetLUFS", reason: "Loudness target must be within -36...-5 LUFS")
        }
        guard truePeakCeilingDBTP.isFinite, -12 ... 0 ~= truePeakCeilingDBTP else {
            throw ChoirError.invalidParameter(
                parameter: "truePeakCeilingDBTP",
                reason: "True-peak ceiling must be within -12...0 dBTP")
        }
        guard fadeDurationMilliseconds.isFinite,
              0 ... 5 ~= fadeDurationMilliseconds else {
            throw ChoirError.invalidParameter(
                parameter: "fadeDurationMilliseconds",
                reason: "Click-prevention fades must be within 0...5 ms")
        }
    }
}

/// Measurements retained with a mastered render for release-gate inspection.
public struct AudioMasteringReport: Sendable, Equatable {
    public let inputIntegratedLUFS: Double
    public let outputIntegratedLUFS: Double
    public let inputTruePeakDBTP: Double
    public let outputTruePeakDBTP: Double
    public let appliedGainDB: Double
    public let peakLimitingDB: Double
    public let outputDCOffsetDBFS: Double

    public var targetWasPeakLimited: Bool { peakLimitingDB < -0.001 }
}

public struct MasteredAudio: Sendable, Equatable {
    public let audio: FloatAudioBuffer
    public let report: AudioMasteringReport
}

/// BS.1770-style loudness normalization, oversampled true-peak protection,
/// DC removal, denormal suppression, and click-prevention fades.
public struct AudioMasterer: Sendable {
    public init() {}

    public func master(
        _ input: FloatAudioBuffer,
        configuration: AudioMasteringConfiguration = .init()
    ) throws -> MasteredAudio {
        try input.validate()
        try configuration.validate()

        var samples = input.samples.map { abs($0) < 1e-30 ? 0 : $0 }
        if configuration.removesDCOffset {
            samples = removeDCOffset(samples, channels: input.channels)
        }

        let prepared = FloatAudioBuffer(
            samples: samples, sampleRate: input.sampleRate, channels: input.channels)
        let inputLoudness = integratedLoudness(of: prepared)
        let inputPeak = truePeakDBTP(of: prepared)

        var requestedGainDB = 0.0
        if inputLoudness.isFinite {
            requestedGainDB = configuration.target.targetLUFS - inputLoudness
            let gain = pow(10, requestedGainDB / 20)
            samples = samples.map { Float(Double($0) * gain) }
        }

        var gained = FloatAudioBuffer(
            samples: samples, sampleRate: input.sampleRate, channels: input.channels)
        let gainedPeak = truePeakDBTP(of: gained)
        var limitingDB = 0.0
        if gainedPeak.isFinite, gainedPeak > configuration.truePeakCeilingDBTP {
            limitingDB = configuration.truePeakCeilingDBTP - gainedPeak
            let limiterGain = pow(10, limitingDB / 20)
            samples = samples.map { Float(Double($0) * limiterGain) }
        }

        samples = applyEdgeFades(
            samples,
            frameCount: input.frameCount,
            channels: input.channels,
            sampleRate: input.sampleRate,
            durationMilliseconds: configuration.fadeDurationMilliseconds)
        samples = samples.map { sample in
            guard sample.isFinite, abs(sample) >= 1e-30 else { return 0 }
            return max(-1, min(1, sample))
        }
        gained = FloatAudioBuffer(
            samples: samples, sampleRate: input.sampleRate, channels: input.channels)

        return MasteredAudio(
            audio: gained,
            report: AudioMasteringReport(
                inputIntegratedLUFS: inputLoudness,
                outputIntegratedLUFS: integratedLoudness(of: gained),
                inputTruePeakDBTP: inputPeak,
                outputTruePeakDBTP: truePeakDBTP(of: gained),
                appliedGainDB: requestedGainDB,
                peakLimitingDB: limitingDB,
                outputDCOffsetDBFS: dcOffsetDBFS(of: gained)))
    }

    /// Integrated loudness using the BS.1770 K-weighting stages and the
    /// absolute/relative gating specified by EBU R128.
    public func integratedLoudness(of input: FloatAudioBuffer) -> Double {
        guard input.frameCount > 0, input.sampleRate > 0, input.channels > 0 else {
            return -Double.infinity
        }
        let weighted = kWeightedSamples(input)
        let blockFrames = max(1, Int((0.4 * Double(input.sampleRate)).rounded()))
        let stepFrames = max(1, Int((0.1 * Double(input.sampleRate)).rounded()))
        var blockEnergies: [Double] = []

        if input.frameCount <= blockFrames {
            blockEnergies.append(meanSquare(
                weighted, frames: 0..<input.frameCount, channels: input.channels))
        } else {
            var start = 0
            while start + blockFrames <= input.frameCount {
                blockEnergies.append(meanSquare(
                    weighted,
                    frames: start..<(start + blockFrames),
                    channels: input.channels))
                start += stepFrames
            }
        }

        let aboveAbsoluteGate = blockEnergies.filter { loudness(forMeanSquare: $0) > -70 }
        guard !aboveAbsoluteGate.isEmpty else { return -Double.infinity }
        let ungatedMean = aboveAbsoluteGate.reduce(0, +) / Double(aboveAbsoluteGate.count)
        let relativeGate = loudness(forMeanSquare: ungatedMean) - 10
        let gated = aboveAbsoluteGate.filter { loudness(forMeanSquare: $0) > relativeGate }
        guard !gated.isEmpty else { return -Double.infinity }
        return loudness(forMeanSquare: gated.reduce(0, +) / Double(gated.count))
    }

    /// Estimates inter-sample true peak at 4x using a windowed-sinc
    /// reconstruction rather than relying only on sample peaks.
    public func truePeakDBTP(of input: FloatAudioBuffer) -> Double {
        guard input.frameCount > 0, input.channels > 0 else { return -Double.infinity }
        let radius = 12
        var peak = 0.0
        for frame in 0..<input.frameCount {
            for channel in 0..<input.channels {
                peak = max(peak, abs(Double(input.samples[frame * input.channels + channel])))
                guard frame + 1 < input.frameCount else { continue }
                for phaseIndex in 1...3 {
                    let position = Double(frame) + Double(phaseIndex) / 4
                    let center = Int(floor(position))
                    let lower = max(0, center - radius)
                    let upper = min(input.frameCount - 1, center + radius)
                    var value = 0.0
                    var weightSum = 0.0
                    if lower <= upper {
                        for sourceFrame in lower...upper {
                            let distance = position - Double(sourceFrame)
                            let normalized = abs(distance) / Double(radius)
                            guard normalized <= 1 else { continue }
                            let window = 0.5 + 0.5 * cos(Double.pi * normalized)
                            let weight = sinc(distance) * window
                            value += Double(
                                input.samples[sourceFrame * input.channels + channel]) * weight
                            weightSum += weight
                        }
                    }
                    if abs(weightSum) > 1e-12 { peak = max(peak, abs(value / weightSum)) }
                }
            }
        }
        guard peak > 0 else { return -Double.infinity }
        return 20 * log10(peak)
    }

    public func dcOffsetDBFS(of input: FloatAudioBuffer) -> Double {
        guard input.frameCount > 0, input.channels > 0 else { return -Double.infinity }
        var largest = 0.0
        for channel in 0..<input.channels {
            var sum = 0.0
            for frame in 0..<input.frameCount {
                sum += Double(input.samples[frame * input.channels + channel])
            }
            largest = max(largest, abs(sum / Double(input.frameCount)))
        }
        guard largest > 0 else { return -Double.infinity }
        return 20 * log10(largest)
    }

    private func removeDCOffset(_ samples: [Float], channels: Int) -> [Float] {
        guard channels > 0, !samples.isEmpty else { return samples }
        let frameCount = samples.count / channels
        guard frameCount > 0 else { return samples }
        var means = [Double](repeating: 0, count: channels)
        for frame in 0..<frameCount {
            for channel in 0..<channels {
                means[channel] += Double(samples[frame * channels + channel])
            }
        }
        means = means.map { $0 / Double(frameCount) }
        return samples.enumerated().map { index, sample in
            Float(Double(sample) - means[index % channels])
        }
    }

    private func applyEdgeFades(
        _ samples: [Float],
        frameCount: Int,
        channels: Int,
        sampleRate: Int,
        durationMilliseconds: Double
    ) -> [Float] {
        guard frameCount > 0, channels > 0, durationMilliseconds > 0 else { return samples }
        let requestedFrames = Int(
            (durationMilliseconds / 1_000 * Double(sampleRate)).rounded(.up))
        let fadeFrames = min(requestedFrames, max(1, frameCount / 2))
        var output = samples
        for frame in 0..<fadeFrames {
            let denominator = Double(max(1, fadeFrames - 1))
            let fadeIn = Double(frame) / denominator
            let endFrame = frameCount - 1 - frame
            for channel in 0..<channels {
                output[frame * channels + channel] *= Float(fadeIn)
                output[endFrame * channels + channel] *= Float(fadeIn)
            }
        }
        return output
    }

    private func kWeightedSamples(_ input: FloatAudioBuffer) -> [Double] {
        var shelves = [BiquadState](repeating: .kWeightingShelf, count: input.channels)
        var highPasses = [BiquadState](repeating: .kWeightingHighPass, count: input.channels)
        var output = [Double](repeating: 0, count: input.samples.count)
        for frame in 0..<input.frameCount {
            for channel in 0..<input.channels {
                let index = frame * input.channels + channel
                let shelved = shelves[channel].process(Double(input.samples[index]))
                output[index] = highPasses[channel].process(shelved)
            }
        }
        return output
    }

    private func meanSquare(
        _ samples: [Double], frames: Range<Int>, channels: Int
    ) -> Double {
        guard !frames.isEmpty, channels > 0 else { return 0 }
        var sum = 0.0
        for frame in frames {
            for channel in 0..<channels {
                let value = samples[frame * channels + channel]
                sum += value * value
            }
        }
        return sum / Double(frames.count * channels)
    }

    private func loudness(forMeanSquare value: Double) -> Double {
        guard value > 0, value.isFinite else { return -Double.infinity }
        return -0.691 + 10 * log10(value)
    }

    private func sinc(_ x: Double) -> Double {
        guard abs(x) > 1e-12 else { return 1 }
        let angle = Double.pi * x
        return sin(angle) / angle
    }
}

private struct BiquadState {
    let b0: Double
    let b1: Double
    let b2: Double
    let a1: Double
    let a2: Double
    var z1 = 0.0
    var z2 = 0.0

    mutating func process(_ input: Double) -> Double {
        let output = b0 * input + z1
        z1 = b1 * input - a1 * output + z2
        z2 = b2 * input - a2 * output
        return output
    }

    static var kWeightingShelf: BiquadState {
        BiquadState(
            b0: 1.53512485958697,
            b1: -2.69169618940638,
            b2: 1.19839281085285,
            a1: -1.69065929318241,
            a2: 0.73248077421585)
    }

    static var kWeightingHighPass: BiquadState {
        BiquadState(
            b0: 1,
            b1: -2,
            b2: 1,
            a1: -1.99004745483398,
            a2: 0.99007225036621)
    }
}
