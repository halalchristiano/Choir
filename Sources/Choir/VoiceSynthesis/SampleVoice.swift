import Foundation

/// Represents a single phoneme audio sample with timing information.
public struct PhonemeSample: Sendable {
    public let phoneme: String
    public let audioData: [Int16]
    public let sampleRate: Int
    public let duration: Double
    public let averagePitch: Float

    public var durationMs: Double {
        Double(audioData.count) / Double(sampleRate) * 1000
    }

    public init(
        phoneme: String,
        audioData: [Int16],
        sampleRate: Int = 48000,
        averagePitch: Float = 100.0
    ) {
        self.phoneme = phoneme
        self.audioData = audioData
        self.sampleRate = sampleRate
        self.averagePitch = averagePitch
        self.duration = Double(audioData.count) / Double(sampleRate)
    }
}

/// Library of phoneme samples for a specific voice.
public actor VoiceSampleLibrary {
    private var samples: [String: [PhonemeSample]] = [:]
    private let voiceName: String

    public init(voiceName: String) {
        self.voiceName = voiceName
    }

    /// Adds a phoneme sample to the library.
    public func addSample(_ sample: PhonemeSample) {
        if samples[sample.phoneme] == nil {
            samples[sample.phoneme] = []
        }
        samples[sample.phoneme]?.append(sample)
    }

    /// Retrieves a sample for a phoneme.
    public func getSample(for phoneme: String) -> PhonemeSample? {
        samples[phoneme]?.first
    }

    /// Gets all available phonemes in the library.
    public func availablePhonemes() -> [String] {
        Array(samples.keys).sorted()
    }

    /// Checks if library has samples for a phoneme.
    public func hasSample(for phoneme: String) -> Bool {
        samples[phoneme] != nil && !(samples[phoneme]?.isEmpty ?? true)
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
            estimatedSizeKB: totalAudio * 2 / 1024
        )
    }
}

/// Statistics about a voice sample library.
public struct LibraryStats: Sendable {
    public let voiceName: String
    public let phonemeCount: Int
    public let totalSamples: Int
    public let totalAudioSamples: Int
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
        self.sampleRate = sampleRate
        self.fadeDurationMs = fadeDurationMs
    }

    /// Synthesizes speech from phonemes.
    public func synthesize(phonemes: [Phoneme]) async throws -> [Int16] {
        guard !phonemes.isEmpty else {
            throw ChoirError.invalidParameter(parameter: "phonemes", reason: "Cannot synthesize empty phoneme list")
        }

        var output: [Int16] = []
        let fadeSamples = Int(fadeDurationMs / 1000.0 * Double(sampleRate))

        for (index, phoneme) in phonemes.enumerated() {
            guard let sample = await library.getSample(for: phoneme.symbol) else {
                // Skip unknown phonemes (or use silence)
                continue
            }

            var audioSegment = sample.audioData

            // Apply crossfade between segments (blend the transition)
            if index > 0 && output.count > fadeSamples && audioSegment.count > fadeSamples {
                audioSegment = applyCrossfade(
                    audioSegment,
                    fadeSamples: fadeSamples
                )
            }

            output.append(contentsOf: audioSegment)
        }

        guard !output.isEmpty else {
            throw ChoirError.synthesisError(reason: "No valid phoneme samples available")
        }

        // Normalize to prevent clipping
        return normalize(output)
    }

    /// Applies a crossfade between the end of output and start of new segment.
    private func applyCrossfade(_ segment: [Int16], fadeSamples: Int) -> [Int16] {
        var faded = segment
        let actualFade = min(fadeSamples, segment.count / 2)

        for i in 0..<actualFade {
            let fade = Float(i) / Float(actualFade)
            faded[i] = Int16(Float(faded[i]) * fade)
        }

        return faded
    }

    /// Normalizes audio to prevent clipping.
    private func normalize(_ samples: [Int16]) -> [Int16] {
        guard !samples.isEmpty else { return samples }

        // `abs(Int16.min)` traps, and a recorded sample can legitimately sit at
        // the full-scale minimum, so widen to Int before taking the magnitude.
        let maxValue = samples.map(AudioFilters.magnitude).max() ?? 0
        guard maxValue > 0 else { return samples }

        let scale = 32767.0 / Double(maxValue)

        return samples.map { sample in
            AudioFilters.clampToPCM(Double(sample) * scale * 0.95)  // 0.95 for headroom
        }
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
        let sampleCount = Int(duration * Double(sampleRate))
        var samples: [Int16] = []

        // Generate a simple sine wave with pitch based on phoneme type
        let frequency = adjustFrequencyForPhoneme(phoneme, baseFrequency: baseFrequency)

        for i in 0..<sampleCount {
            let t = Float(i) / Float(sampleRate)
            let phase = 2.0 * .pi * frequency * t
            let value = sin(phase) * 0.5  // 0.5 amplitude for headroom
            samples.append(Int16(value * 32767.0))
        }

        return PhonemeSample(
            phoneme: phoneme,
            audioData: samples,
            sampleRate: sampleRate,
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
        case "p", "b", "t", "d", "k", "g": return baseFrequency * 0.6

        // Nasals (rich, mid-range)
        case "m", "n", "ŋ": return baseFrequency * 0.9

        default: return baseFrequency
        }
    }
}
