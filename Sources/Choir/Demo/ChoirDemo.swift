import Foundation

/// Helper actor for collecting chunks in streaming demos.
actor ChunkCounter {
    private var chunks: [AudioChunk] = []

    func add(_ chunk: AudioChunk) {
        chunks.append(chunk)
    }

    func getResults() -> [AudioChunk] {
        chunks
    }
}

/// Example usage and demo of the Choir synthesis engine.
///
/// This module demonstrates all major features and provides reference implementations
/// for integrating Choir into applications.
public struct ChoirDemo {
    /// Simple demonstration of basic synthesis.
    public static func basicSynthesisDemo() async throws {
        // Initialize engine
        let engine = ChoirEngine()
        try await engine.initialize()

        // Synthesize simple text
        let audio = try await engine.synthesize(
            text: "Hello, welcome to Choir, the on-device voice synthesis engine.",
            voice: .isla,
            parameters: SynthesisParameters()
        )

        print("✓ Generated \(audio.samples.count) audio samples")
        print("✓ Duration: \(String(format: "%.2f", audio.duration)) seconds")
    }

    /// Demonstrates prosody control with various parameters.
    public static func prosodyControlDemo() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let text = "This is a demonstration of prosody control in Choir."

        // Slow, calm speech
        let calmParams = SynthesisParameters(rate: 0.8, emotionalIntensity: 0.3)
        let calmAudio = try await engine.synthesize(text: text, voice: .garrick, parameters: calmParams)
        print("✓ Calm speech: \(String(format: "%.2f", calmAudio.duration))s")

        // Fast, energetic speech
        let energeticParams = SynthesisParameters(pitchShift: 5, rate: 1.3, emotionalIntensity: 0.9)
        let energeticAudio = try await engine.synthesize(text: text, voice: .lyra, parameters: energeticParams)
        print("✓ Energetic speech: \(String(format: "%.2f", energeticAudio.duration))s")

        // Whispered speech
        let whisperParams = SynthesisParameters(pitchShift: -5, rate: 0.9, breathiness: 0.8)
        let whisperAudio = try await engine.synthesize(text: text, voice: .isla, parameters: whisperParams)
        print("✓ Whispered speech: \(String(format: "%.2f", whisperAudio.duration))s")
    }

    /// Demonstrates speaking style presets.
    public static func speakingStyleDemo() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let text = "Speaking styles make synthesis more expressive."
        let voice = Voice.lyra

        for style in SpeakingStyle.allStyles {
            let audio = try await engine.synthesize(
                text: text,
                voice: voice,
                parameters: style.parameters
            )
            print("✓ \(style.name): \(String(format: "%.2f", audio.duration))s")
        }
    }

    /// Demonstrates voice blending between two voices.
    public static func voiceBlendingDemo() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let text = "Voice blending creates smooth transitions between voices."
        let blending = VoiceBlending()

        // Blend between two voices
        let profile1 = VoiceBlending.VoiceProfile(voice: .garrick)
        let profile2 = VoiceBlending.VoiceProfile(voice: .isla)

        print("Voice blending demo:")
        for step in 0...4 {
            let mix = Double(step) / 4.0
            let blendedParams = blending.blend(profile1, with: profile2, mix: mix)

            let audio = try await engine.synthesize(
                text: text,
                voice: profile1.voice,
                parameters: blendedParams
            )
            print("  Mix \(step)/4: \(String(format: "%.2f", audio.duration))s")
        }
    }

    /// Demonstrates SSML markup for fine prosody control.
    public static func ssmlMarkupDemo() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let ssml = """
            <s>
            This is normal speech.
            <prosody pitch="+10">This part is higher pitched.</prosody>
            <emphasis level="strong">This is emphasized!</emphasis>
            <prosody rate="1.5">And this is faster.</prosody>
            </s>
            """

        let audio = try await engine.synthesize(text: ssml, voice: .orion)
        print("✓ SSML synthesis: \(String(format: "%.2f", audio.duration))s")
    }

    /// Demonstrates streaming synthesis for real-time playback.
    public static func streamingSynthesisDemo() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        print("Streaming synthesis demo:")

        let streamCounter = ChunkCounter()

        try await engine.streamSynthesis(
            text: "Streaming synthesis allows real-time audio generation.",
            voice: .isla,
            options: StreamingOptions(chunkSize: 2400),  // 50ms chunks
            onChunk: { chunk in
                await streamCounter.add(chunk)
            }
        )

        let results = await streamCounter.getResults()
        print("✓ Total: \(results.count) chunks, \(results.reduce(0) { $0 + $1.samples.count }) samples")
    }

    /// Demonstrates audio post-processing.
    public static func audioPostProcessingDemo() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let audio = try await engine.synthesize(
            text: "Audio post-processing improves quality.",
            voice: .lyra
        )

        let filters = AudioFilters()

        // Apply various filters
        let deessed = filters.deEsser(audio.samples)
        let normalized = filters.normalize(deessed, targetLevel: -6.0)
        let compressed = filters.compress(normalized, threshold: -20, ratio: 4.0)

        print("✓ Original: \(audio.samples.count) samples")
        print("✓ De-essed: \(deessed.count) samples")
        print("✓ Normalized: \(normalized.count) samples")
        print("✓ Compressed: \(compressed.count) samples")

        // Create filtered audio buffer
        let filteredAudio = AudioBuffer(samples: compressed, format: audio.format)
        print("✓ Final duration: \(String(format: "%.2f", filteredAudio.duration))s")
    }

    /// Demonstrates audio encoding to different formats.
    public static func audioEncodingDemo() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let audio = try await engine.synthesize(
            text: "Audio can be exported to different formats.",
            voice: .garrick
        )

        let encoder = AudioEncoder()

        // Export to WAV
        let wavData = encoder.encodeWAV(audio)
        print("✓ WAV encoded: \(wavData.count) bytes")

        // Export raw PCM
        let rawData = encoder.encodeRaw(audio)
        print("✓ Raw PCM encoded: \(rawData.count) bytes")

        // Note: MP3, AAC would require external libraries
        print("ℹ MP3 and AAC encoding require external codec libraries")
    }

    /// Demonstrates character voice synthesis for games/narration.
    public static func characterVoicesDemo() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let dialogues = [
            (voice: Voice.hespera, text: "Beware the curse..."),
            (voice: Voice.bram, text: "Aye, what brings ye to these parts?"),
            (voice: Voice.sable, text: "BEEP BOOP. Analyzing your request."),
            (voice: Voice.malvern, text: "You fool! You've played right into my hands!"),
            (voice: Voice.ravenna, text: "Pathetic. Your resistance is futile."),
        ]

        print("Character voice synthesis:")
        for (voice, text) in dialogues {
            let audio = try await engine.synthesize(text: text, voice: voice)
            print("✓ \(voice.displayName): \(String(format: "%.2f", audio.duration))s")
        }
    }

    /// Runs all demonstrations.
    public static func runAllDemos() async throws {
        print("""
        ┌─────────────────────────────────────┐
        │  CHOIR Synthesis Engine Demos       │
        └─────────────────────────────────────┘
        """)

        print("\n1. Basic Synthesis")
        try await basicSynthesisDemo()

        print("\n2. Prosody Control")
        try await prosodyControlDemo()

        print("\n3. Speaking Styles")
        try await speakingStyleDemo()

        print("\n4. Voice Blending")
        try await voiceBlendingDemo()

        print("\n5. SSML Markup")
        try await ssmlMarkupDemo()

        print("\n6. Streaming Synthesis")
        try await streamingSynthesisDemo()

        print("\n7. Audio Post-Processing")
        try await audioPostProcessingDemo()

        print("\n8. Audio Encoding")
        try await audioEncodingDemo()

        print("\n9. Character Voices")
        try await characterVoicesDemo()

        print("""

        ┌─────────────────────────────────────┐
        │  All demos completed successfully!  │
        └─────────────────────────────────────┘
        """)
    }
}
