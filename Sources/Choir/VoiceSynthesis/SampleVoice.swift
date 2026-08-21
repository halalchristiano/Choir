import Foundation

/// Represents a single phoneme audio sample with timing information.
public struct PhonemeSample: Sendable, Equatable {
    public let phoneme: String
    public let audioData: [Int16]
    public let sampleRate: Int
    public let duration: Double
    public let averagePitch: Float

    public var durationMs: Double {
        duration * 1000
    }

    /// Number of PCM samples in the recording.
    public var sampleCount: Int { audioData.count }

    /// Size of the raw 16-bit PCM payload.
    public var byteCount: Int { audioData.count * MemoryLayout<Int16>.size }

    /// Whether the recording contains no PCM data.
    public var isEmpty: Bool { audioData.isEmpty }

    /// Largest absolute sample, normalized to the full 16-bit PCM range.
    public var peakAmplitude: Double {
        guard let peak = audioData.map({ abs(Int32($0)) }).max() else { return 0 }
        return Double(peak) / 32768
    }

    /// Root-mean-square amplitude, normalized to the full 16-bit PCM range.
    public var rmsAmplitude: Double {
        guard !audioData.isEmpty else { return 0 }
        let meanSquare = audioData.reduce(0.0) { partial, sample in
            let normalized = Double(sample) / 32768
            return partial + normalized * normalized
        } / Double(audioData.count)
        return sqrt(meanSquare)
    }

    public init(
        phoneme: String,
        audioData: [Int16],
        sampleRate: Int = 48000,
        averagePitch: Float = 100.0
    ) {
        let trimmedPhoneme = phoneme.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeSampleRate = (8_000...384_000).contains(sampleRate) ? sampleRate : 48000
        self.phoneme = Phoneme(trimmedPhoneme).symbol
        self.audioData = audioData
        self.sampleRate = safeSampleRate
        self.averagePitch = averagePitch.isFinite ? max(0, averagePitch) : 0
        self.duration = Double(audioData.count) / Double(safeSampleRate)
    }
}

/// Library of phoneme samples for a specific voice.
public actor VoiceSampleLibrary {
    private var samples: [String: [PhonemeSample]] = [:]
    private let voiceName: String

    public init(voiceName: String) {
        let trimmedName = voiceName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.voiceName = trimmedName.isEmpty ? "Unnamed Voice" : trimmedName
    }

    /// Adds a phoneme sample to the library.
    @discardableResult
    public func addSample(_ sample: PhonemeSample) -> Bool {
        guard !sample.phoneme.isEmpty, !sample.isEmpty else { return false }
        samples[sample.phoneme, default: []].append(sample)
        return true
    }

    /// Retrieves a sample for a phoneme, optionally choosing the closest pitch variant.
    public func getSample(
        for phoneme: String,
        preferredPitch: Float? = nil
    ) -> PhonemeSample? {
        let key = canonicalKey(for: phoneme)
        guard let candidates = samples[key], !candidates.isEmpty else { return nil }
        guard let preferredPitch, preferredPitch.isFinite, preferredPitch >= 0 else {
            return candidates.first
        }

        return candidates.min {
            abs($0.averagePitch - preferredPitch) < abs($1.averagePitch - preferredPitch)
        }
    }

    /// Retrieves every recorded variant for a phoneme in insertion order.
    public func getSamples(for phoneme: String) -> [PhonemeSample] {
        samples[canonicalKey(for: phoneme)] ?? []
    }

    /// Gets all available phonemes in the library.
    public func availablePhonemes() -> [String] {
        Array(samples.keys).sorted()
    }

    /// Checks if library has samples for a phoneme.
    public func hasSample(for phoneme: String) -> Bool {
        !(samples[canonicalKey(for: phoneme)]?.isEmpty ?? true)
    }

    /// Removes every recorded variant for a phoneme.
    @discardableResult
    public func removeSamples(for phoneme: String) -> Int {
        samples.removeValue(forKey: canonicalKey(for: phoneme))?.count ?? 0
    }

    /// Removes all recordings and returns how many samples were discarded.
    @discardableResult
    public func removeAllSamples() -> Int {
        let removedCount = samples.values.reduce(0) { $0 + $1.count }
        samples.removeAll(keepingCapacity: false)
        return removedCount
    }

    /// Gets library statistics.
    public func statistics() -> LibraryStats {
        let totalSamples = samples.values.reduce(0) { $0 + $1.count }
        let totalAudio = samples.values.reduce(0) { acc, phonemeSamples in
            acc + phonemeSamples.reduce(0) { $0 + $1.audioData.count }
        }

        return LibraryStats(
            voiceName: voiceName,
            phonemeCount: samples.count,
            totalSamples: totalSamples,
            totalAudioSamples: totalAudio,
            totalAudioBytes: totalAudio * MemoryLayout<Int16>.size,
            estimatedSizeKB: totalAudio * 2 / 1024
        )
    }

    private func canonicalKey(for phoneme: String) -> String {
        let trimmed = phoneme.trimmingCharacters(in: .whitespacesAndNewlines)
        return Phoneme(trimmed).symbol
    }
}

/// Statistics about a voice sample library.
public struct LibraryStats: Sendable, Equatable {
    public let voiceName: String
    public let phonemeCount: Int
    public let totalSamples: Int
    public let totalAudioSamples: Int
    public let totalAudioBytes: Int
    public let estimatedSizeKB: Int
}

/// Synthesizes speech by concatenating phoneme samples.
public actor SampleBasedSynthesizer {
    private let library: VoiceSampleLibrary
    private let sampleRate: Int
    private let fadeDurationMs: Double

    public init(
        library: VoiceSampleLibrary,
        sampleRate: Int = 48000,
        fadeDurationMs: Double = 5.0
    ) {
        self.library = library
        self.sampleRate = (8_000...384_000).contains(sampleRate) ? sampleRate : 48000
        if fadeDurationMs.isFinite {
            self.fadeDurationMs = min(1_000, max(0, fadeDurationMs))
        } else {
            self.fadeDurationMs = 5.0
        }
    }

    /// Synthesizes speech from phonemes.
    public func synthesize(phonemes: [Phoneme]) async throws -> [Int16] {
        try Cancellation.check()
        guard !phonemes.isEmpty else {
            throw ChoirError.invalidParameter(parameter: "phonemes", reason: "Cannot synthesize empty phoneme list")
        }

        var output: [Int16] = []
        let fadeSamples = Int((fadeDurationMs / 1000.0 * Double(sampleRate)).rounded())

        for phoneme in phonemes {
            try Cancellation.check()
            guard let sample = await library.getSample(for: phoneme.symbol) else {
                // Skip unknown phonemes (or use silence)
                continue
            }

            let audioSegment = try resample(sample)
            guard !audioSegment.isEmpty else { continue }

            // Apply crossfade between segments (blend the transition)
            try append(audioSegment, to: &output, fadeSamples: fadeSamples)
        }

        guard !output.isEmpty else {
            throw ChoirError.synthesisError(reason: "No valid phoneme samples available")
        }

        // Normalize to prevent clipping
        return try normalize(output)
    }

    /// Resamples a recording to the synthesizer's output rate using linear interpolation.
    private func resample(_ sample: PhonemeSample) throws -> [Int16] {
        guard !sample.audioData.isEmpty, sample.sampleRate != sampleRate else {
            return sample.audioData
        }

        let rateRatio = Double(sampleRate) / Double(sample.sampleRate)
        let outputCount = max(1, Int((Double(sample.audioData.count) * rateRatio).rounded()))
        if sample.audioData.count == 1 {
            return Array(repeating: sample.audioData[0], count: outputCount)
        }

        var resampled: [Int16] = []
        resampled.reserveCapacity(outputCount)
        for outputIndex in 0..<outputCount {
            if outputIndex.isMultiple(of: 4_096) { try Cancellation.check() }
            let sourcePosition = Double(outputIndex) / rateRatio
            let lowerIndex = min(Int(sourcePosition), sample.audioData.count - 1)
            let upperIndex = min(lowerIndex + 1, sample.audioData.count - 1)
            let fraction = sourcePosition - Double(lowerIndex)
            let lower = Double(sample.audioData[lowerIndex])
            let upper = Double(sample.audioData[upperIndex])
            let interpolated = lower + (upper - lower) * fraction
            resampled.append(Int16(clamping: Int(interpolated.rounded())))
        }
        return resampled
    }

    /// Overlaps the tail and head of adjacent segments to make a true crossfade.
    private func append(
        _ segment: [Int16],
        to output: inout [Int16],
        fadeSamples: Int
    ) throws {
        let actualFade = min(fadeSamples, output.count, segment.count)
        guard actualFade > 0 else {
            output.append(contentsOf: segment)
            return
        }

        let outputStart = output.count - actualFade
        for index in 0..<actualFade {
            if index.isMultiple(of: 4_096) { try Cancellation.check() }
            let incomingWeight = Double(index + 1) / Double(actualFade + 1)
            let outgoingWeight = 1 - incomingWeight
            let mixed = Double(output[outputStart + index]) * outgoingWeight
                + Double(segment[index]) * incomingWeight
            output[outputStart + index] = Int16(clamping: Int(mixed.rounded()))
        }
        output.append(contentsOf: segment.dropFirst(actualFade))
    }

    /// Normalizes audio to prevent clipping.
    private func normalize(_ samples: [Int16]) throws -> [Int16] {
        guard !samples.isEmpty else { return samples }

        // `abs` traps on Int16.min; magnitude is UInt16 and holds 32768.
        var maxValue: UInt16 = 0
        for (index, sample) in samples.enumerated() {
            if index.isMultiple(of: 4_096) { try Cancellation.check() }
            maxValue = max(maxValue, sample.magnitude)
        }
        guard maxValue > 0 else { return samples }

        let targetPeak = Float(Int16.max) * 0.95
        guard Float(maxValue) > targetPeak else { return samples }
        let scale = targetPeak / Float(maxValue)

        var normalized: [Int16] = []
        normalized.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            if index.isMultiple(of: 4_096) { try Cancellation.check() }
            // Clamp before narrowing: Int16(_:) traps on out-of-range input.
            let scaled = Float(sample) * scale
            if scaled <= -32768 {
                normalized.append(-32768)
            } else if scaled >= 32767 {
                normalized.append(32767)
            } else {
                normalized.append(Int16(scaled.rounded()))
            }
        }
        return normalized
    }
}

/// Fallback: Generates synthetic phoneme samples (for demo/testing).
/// In production, these would be real recordings.
public struct SyntheticSampleGenerator {
    /// Generates a simple sine wave approximation of a phoneme.
    public static func generateSample(
        for phoneme: String,
        duration: Double = 0.1,
        sampleRate: Int = 48000,
        baseFrequency: Float = 200.0
    ) -> PhonemeSample {
        let safeSampleRate = (8_000...384_000).contains(sampleRate) ? sampleRate : 48000
        let safeDuration = duration.isFinite && duration > 0 ? min(duration, 60) : 0
        let safeBaseFrequency = baseFrequency.isFinite && baseFrequency > 0
            ? baseFrequency
            : 200
        let sampleCount = Int(safeDuration * Double(safeSampleRate))
        var samples: [Int16] = []

        // Generate a simple sine wave with pitch based on phoneme type
        let adjustedFrequency = adjustFrequencyForPhoneme(
            Phoneme(phoneme.trimmingCharacters(in: .whitespacesAndNewlines)).symbol,
            baseFrequency: safeBaseFrequency
        )
        let frequency = min(adjustedFrequency, Float(safeSampleRate) * 0.45)

        for i in 0..<sampleCount {
            let t = Float(i) / Float(safeSampleRate)
            let phase = 2.0 * .pi * frequency * t
            let value = sin(phase) * 0.5  // 0.5 amplitude for headroom
            samples.append(Int16(value * 32767.0))
        }

        return PhonemeSample(
            phoneme: phoneme,
            audioData: samples,
            sampleRate: safeSampleRate,
            averagePitch: frequency
        )
    }

    /// Adjusts frequency based on phoneme characteristics.
    private static func adjustFrequencyForPhoneme(
        _ phoneme: String,
        baseFrequency: Float
    ) -> Float {
        // Vowels get base frequency, consonants get varied frequencies
        switch phoneme {
        // Vowels
        case "a", "ɑ": return baseFrequency
        case "e", "ɛ": return baseFrequency * 1.1
        case "i", "ɪ": return baseFrequency * 1.3
        case "o", "ɔ": return baseFrequency * 0.9
        case "u", "ʊ": return baseFrequency * 0.8

        // Fricatives (higher frequency)
        case "s", "z", "ʃ", "ʒ": return baseFrequency * 1.8
        case "f", "v": return baseFrequency * 1.5
        case "θ", "ð": return baseFrequency * 1.4

        // Stops (short, lower)
        case "p", "b", "t", "d", "k", "ɡ": return baseFrequency * 0.6

        // Nasals (rich, mid-range)
        case "m", "n", "ŋ": return baseFrequency * 0.9

        default: return baseFrequency
        }
    }
}
