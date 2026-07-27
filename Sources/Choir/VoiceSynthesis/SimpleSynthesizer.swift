import Foundation

/// Simple end-to-end speech synthesizer using real voice samples.
public actor SimpleSynthesizer {
    private let library: VoiceSampleLibrary
    private let phonemizer: Phonemizer
    private let textNormalizer: TextNormalizer
    private let synthesizer: SampleBasedSynthesizer

    public init(library: VoiceSampleLibrary) {
        self.library = library
        self.phonemizer = Phonemizer()
        self.textNormalizer = TextNormalizer()
        self.synthesizer = SampleBasedSynthesizer(library: library)
    }

    /// Synthesizes speech from text.
    public func synthesize(text: String) async throws -> AudioBuffer {
        // Step 1: Normalize text
        let normalized = textNormalizer.normalize(text)

        // Step 2: Convert to phonemes
        let phonemes = phonemizer.phonemize(normalized)

        guard !phonemes.isEmpty else {
            throw ChoirError.invalidParameter(parameter: "text", reason: "Could not convert text to phonemes")
        }

        // Step 3: Synthesize from phonemes
        let audioSamples = try await synthesizer.synthesize(phonemes: phonemes)

        // Step 4: Return as audio buffer
        return AudioBuffer(
            samples: audioSamples,
            format: AudioFormat(sampleRate: 48000, channels: 1, bitDepth: 16)
        )
    }

    /// Gets library info.
    public func libraryInfo() async -> LibraryStats {
        await library.statistics()
    }
}

/// Quick demo of sample-based synthesis.
public struct SimpleSynthesizerDemo {
    public static func runDemo() async throws {
        print("🎙️ Sample-Based Voice Synthesis Demo")
        print(String(repeating: "=", count: 50))

        // Create a voice library
        let library = VoiceSampleLibrary(voiceName: "DemoVoice")

        // Populate with synthetic samples (in production, load real recordings)
        let phonemes = [
            "h", "ɛ", "l", "oʊ", "w", "ɝ", "l", "d",  // "hello world"
            "ð", "ɪ", "s", "ɪ", "z", "æ", "t", "ɛ", "s", "t"  // "this is a test"
        ]

        print("📚 Building voice library with \(phonemes.count) phonemes...")
        for phoneme in phonemes {
            let sample = SyntheticSampleGenerator.generateSample(
                for: phoneme,
                duration: 0.08,
                baseFrequency: 150.0
            )
            await library.addSample(sample)
        }

        // Show library stats
        let stats = await library.statistics()
        print("✅ Library loaded: \(stats.phonemeCount) unique phonemes, \(stats.estimatedSizeKB)KB")
        print("")

        // Create synthesizer
        let synthesizer = SimpleSynthesizer(library: library)

        // Synthesize some text
        let testPhrases = [
            "hello",
            "hi there",
            "this is a test"
        ]

        print("🔊 Synthesizing test phrases...")
        for phrase in testPhrases {
            do {
                let audio = try await synthesizer.synthesize(text: phrase)
                let durationSeconds = Double(audio.samples.count) / Double(audio.format.sampleRate)
                print("  ✓ '\(phrase)' → \(audio.samples.count) samples (\(String(format: "%.2f", durationSeconds))s)")
            } catch {
                print("  ✗ '\(phrase)' → Error: \(error)")
            }
        }

        print("")
        print("✨ Demo complete!")
    }
}
