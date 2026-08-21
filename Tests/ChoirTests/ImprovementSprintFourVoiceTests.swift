import Foundation
import Testing
@testable import Choir

@Suite("Fourth improvement sprint: sample voice synthesis")
struct ImprovementSprintFourVoiceTests {
    private func sample(
        _ phoneme: String = "ɑ",
        audioData: [Int16] = [100, -100],
        sampleRate: Int = 48_000,
        averagePitch: Float = 100
    ) -> PhonemeSample {
        PhonemeSample(
            phoneme: phoneme,
            audioData: audioData,
            sampleRate: sampleRate,
            averagePitch: averagePitch
        )
    }

    @Test("01 Phoneme samples support value equality")
    func sampleEquality() {
        #expect(sample() == sample())
        #expect(sample(audioData: [1]) != sample(audioData: [2]))
    }

    @Test("02 Invalid recording rates safely fall back")
    func sampleRateSanitization() {
        let value = sample(audioData: [1, 2], sampleRate: 0)
        #expect(value.sampleRate == 48_000)
        #expect(value.duration == 2.0 / 48_000)
    }

    @Test("03 Invalid average pitches safely normalize")
    func pitchSanitization() {
        #expect(sample(averagePitch: .nan).averagePitch == 0)
        #expect(sample(averagePitch: -20).averagePitch == 0)
    }

    @Test("04 Recording phoneme keys are canonicalized")
    func samplePhonemeCanonicalization() {
        #expect(sample("  g\n").phoneme == "ɡ")
    }

    @Test("05 Recording sample counts are directly available")
    func sampleCount() {
        #expect(sample(audioData: [1, 2, 3]).sampleCount == 3)
    }

    @Test("06 Recording PCM byte counts are directly available")
    func sampleByteCount() {
        #expect(sample(audioData: [1, 2, 3]).byteCount == 6)
    }

    @Test("07 Empty recordings are identifiable")
    func sampleEmptyState() {
        #expect(sample(audioData: []).isEmpty)
        #expect(!sample(audioData: [0]).isEmpty)
    }

    @Test("08 Recording peaks handle full-scale negative PCM")
    func samplePeakAmplitude() {
        #expect(sample(audioData: [Int16.min]).peakAmplitude == 1)
        #expect(sample(audioData: []).peakAmplitude == 0)
    }

    @Test("09 Recording RMS amplitude is normalized")
    func sampleRMSAmplitude() {
        let value = sample(audioData: [16_384, -16_384])
        #expect(abs(value.rmsAmplitude - 0.5) < 0.000_001)
    }

    @Test("10 Voice names are trimmed and never blank")
    func voiceNameSanitization() async {
        let named = VoiceSampleLibrary(voiceName: "  Alto \n")
        let unnamed = VoiceSampleLibrary(voiceName: " \n")
        #expect((await named.statistics()).voiceName == "Alto")
        #expect((await unnamed.statistics()).voiceName == "Unnamed Voice")
    }

    @Test("11 Libraries reject unusable recordings")
    func unusableRecordingRejection() async {
        let library = VoiceSampleLibrary(voiceName: "Test")
        #expect(!(await library.addSample(sample("", audioData: [1]))))
        #expect(!(await library.addSample(sample("ɑ", audioData: []))))
        #expect((await library.statistics()).totalSamples == 0)
    }

    @Test("12 Library queries canonicalize phoneme keys")
    func canonicalLibraryQueries() async {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample("g"))
        #expect(await library.hasSample(for: " \nɡ "))
        #expect((await library.getSample(for: "g"))?.phoneme == "ɡ")
    }

    @Test("13 Every recorded phoneme variant can be retrieved")
    func variantRetrieval() async {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample(averagePitch: 100))
        await library.addSample(sample(averagePitch: 200))
        let variants = await library.getSamples(for: "ɑ")
        #expect(variants.map(\.averagePitch) == [100, 200])
    }

    @Test("14 Pitch-aware lookup selects the nearest variant")
    func pitchAwareLookup() async {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample(averagePitch: 100))
        await library.addSample(sample(averagePitch: 200))
        let closest = await library.getSample(for: "ɑ", preferredPitch: 180)
        let fallback = await library.getSample(for: "ɑ", preferredPitch: .nan)
        #expect(closest?.averagePitch == 200)
        #expect(fallback?.averagePitch == 100)
    }

    @Test("15 Phoneme variants can be removed atomically")
    func variantRemoval() async {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample())
        await library.addSample(sample())
        #expect(await library.removeSamples(for: " ɑ ") == 2)
        #expect(!(await library.hasSample(for: "ɑ")))
    }

    @Test("16 Libraries can be cleared and report the removed count")
    func libraryClearing() async {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample("ɑ"))
        await library.addSample(sample("s"))
        #expect(await library.removeAllSamples() == 2)
        #expect((await library.availablePhonemes()).isEmpty)
    }

    @Test("17 Library statistics support value equality")
    func statisticEquality() async {
        let library = VoiceSampleLibrary(voiceName: "Test")
        let first = await library.statistics()
        let second = await library.statistics()
        #expect(first == second)
    }

    @Test("18 Library statistics expose exact PCM bytes")
    func statisticBytes() async {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample(audioData: [1, 2, 3]))
        let stats = await library.statistics()
        #expect(stats.totalAudioSamples == 3)
        #expect(stats.totalAudioBytes == 6)
    }

    @Test("19 Mixed-rate recordings are resampled to the output rate")
    func mixedRateResampling() async throws {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample(audioData: [0, 1_000], sampleRate: 8_000))
        let synthesizer = SampleBasedSynthesizer(
            library: library,
            sampleRate: 16_000,
            fadeDurationMs: 0
        )
        let output = try await synthesizer.synthesize(phonemes: [Phoneme("ɑ")])
        #expect(output == [0, 500, 1_000, 1_000])
    }

    @Test("20 Adjacent recordings use a true overlap crossfade")
    func overlapCrossfade() async throws {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample(
            "ɑ", audioData: [1_000, 1_000, 1_000, 1_000], sampleRate: 8_000))
        await library.addSample(sample(
            "s", audioData: [-1_000, -1_000, -1_000, -1_000], sampleRate: 8_000))
        let synthesizer = SampleBasedSynthesizer(
            library: library,
            sampleRate: 8_000,
            fadeDurationMs: 0.25
        )
        let output = try await synthesizer.synthesize(
            phonemes: [Phoneme("ɑ"), Phoneme("s")])
        #expect(output == [1_000, 1_000, 333, -333, -1_000, -1_000])
    }

    @Test("21 Unsafe synthesizer configuration falls back or clamps")
    func synthesisConfigurationSanitization() async throws {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample(
            "ɑ", audioData: [100, 100], sampleRate: 24_000))
        let synthesizer = SampleBasedSynthesizer(
            library: library,
            sampleRate: 0,
            fadeDurationMs: -1
        )
        let output = try await synthesizer.synthesize(
            phonemes: [Phoneme("ɑ"), Phoneme("ɑ")])
        #expect(output.count == 8)
    }

    @Test("22 Normalization preserves intentionally quiet audio")
    func quietAudioPreservation() async throws {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample(audioData: [100, -100]))
        let synthesizer = SampleBasedSynthesizer(
            library: library,
            fadeDurationMs: 0
        )
        let output = try await synthesizer.synthesize(phonemes: [Phoneme("ɑ")])
        #expect(output == [100, -100])
    }

    @Test("23 Sample synthesis cooperatively honors cancellation")
    func synthesisCancellation() async {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample())
        let synthesizer = SampleBasedSynthesizer(library: library)
        let task = Task {
            try? await Task.sleep(nanoseconds: 20_000_000)
            return try await synthesizer.synthesize(phonemes: [Phoneme("ɑ")])
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch let error as ChoirError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("Expected ChoirError.cancelled, got \(type(of: error))")
        }
    }

    @Test("24 Synthetic generation sanitizes unsafe numeric inputs")
    func syntheticInputSanitization() {
        let invalidDuration = SyntheticSampleGenerator.generateSample(
            for: "ɑ", duration: .nan)
        #expect(invalidDuration.isEmpty)

        let invalidConfiguration = SyntheticSampleGenerator.generateSample(
            for: "s", duration: 0.001, sampleRate: 0, baseFrequency: .infinity)
        #expect(invalidConfiguration.sampleRate == 48_000)
        #expect(invalidConfiguration.sampleCount == 48)
        #expect(invalidConfiguration.averagePitch.isFinite)
        #expect(invalidConfiguration.averagePitch <= 21_600)
    }

    @Test("25 Simple synthesis honors its configured output format")
    func simpleSynthesizerConfiguration() async throws {
        let library = VoiceSampleLibrary(voiceName: "Test")
        await library.addSample(sample(
            "ə", audioData: [100, 200, 300, 400], sampleRate: 8_000))
        let synthesizer = SimpleSynthesizer(
            library: library,
            sampleRate: 16_000,
            fadeDurationMs: 0
        )
        let output = try await synthesizer.synthesize(text: "a")
        #expect(output.format.sampleRate == 16_000)
        #expect(output.samples.count == 8)
    }
}
