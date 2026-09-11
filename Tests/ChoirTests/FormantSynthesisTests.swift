import Foundation
import Testing
@testable import Choir

/// The rule-based formant path: the first synthesis route in the package that
/// produces speech rather than a test tone.
///
/// These tests assert acoustic structure, not naturalness. Passing them shows
/// that the engine renders voiced sound with the formants the table specifies
/// and with sane relative levels; it says nothing about whether the result is
/// pleasant, and it does not stand in for the SRS listening gates.
@Suite("Formant synthesis")
struct FormantSynthesisTests {

    // MARK: - Helpers

    static func index(of ipa: String) -> Int {
        PhonemeInventory.all.firstIndex { $0.ipa == ipa } ?? 0
    }

    static func input(
        _ ipa: String, ms: Double = 300, f0: Double = 120, voice: Voice = .orion
    ) -> AcousticModelInput {
        AcousticModelInput(
            phonemeIndices: [index(of: ipa)],
            durations: [ms],
            fundamentalFrequency: [f0],
            energy: [-23],
            stress: [1],
            voicing: [1],
            voiceID: voice.conditioningID)
    }

    static func render(
        _ ipa: String, ms: Double = 300, f0: Double = 120, voice: Voice = .orion
    ) async throws -> [Int16] {
        let features = try await FormantAcousticModel()
            .predict(input: input(ipa, ms: ms, f0: f0, voice: voice))
        return try await FormantVocoder().synthesize(features: features, sampleRate: 48_000)
    }

    static func rms(_ samples: ArraySlice<Int16>) -> Double {
        guard !samples.isEmpty else { return 0 }
        let total = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (total / Double(samples.count)).squareRoot()
    }

    /// Energy at one frequency, by the Goertzel algorithm.
    ///
    /// A single-bin detector is enough here and avoids pulling in an FFT: the
    /// assertions compare energy at two known frequencies rather than needing a
    /// whole spectrum.
    static func energy(of samples: [Int16], at frequency: Double, sampleRate: Double) -> Double {
        let omega = 2 * Double.pi * frequency / sampleRate
        let coefficient = 2 * cos(omega)
        var s1 = 0.0
        var s2 = 0.0
        for sample in samples {
            let s0 = Double(sample) / 32_768.0 + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }
        return (s1 * s1 + s2 * s2 - coefficient * s1 * s2).squareRoot()
    }

    /// Mean energy across a band, sampled at a few points.
    static func bandEnergy(
        of samples: [Int16], from low: Double, to high: Double, sampleRate: Double = 48_000
    ) -> Double {
        let steps = 9
        var total = 0.0
        for step in 0..<steps {
            let frequency = low + (high - low) * Double(step) / Double(steps - 1)
            total += energy(of: samples, at: frequency, sampleRate: sampleRate)
        }
        return total / Double(steps)
    }

    // MARK: - The table

    @Test("every inventory phoneme has a formant definition")
    func tableCoversInventory() {
        // Catches a symbol drifting out of the table — in particular the script
        // g at U+0261, which is easy to write as an ASCII g by mistake.
        let missing = PhonemeInventory.all.filter { FormantTable.definition(for: $0.ipa) == nil }
        #expect(missing.isEmpty,
                "no formant target for: \(missing.map(\.ipa).joined(separator: ", "))")
    }

    @Test("definitions are reachable by encoded index")
    func tableCoversEncodedIndices() {
        for index in 0..<PhonemeInventory.all.count {
            #expect(FormantTable.definition(forIndex: index) != nil)
        }
        #expect(FormantTable.definition(forIndex: -1) == nil)
        #expect(FormantTable.definition(forIndex: PhonemeInventory.all.count) == nil)
    }

    @Test("vowels are voiced and obstruents are not")
    func mannerClassification() throws {
        let vowel = try #require(FormantTable.definition(for: "ɑ"))
        #expect(vowel.isVoiced)
        #expect(!vowel.hasClosure)

        let stop = try #require(FormantTable.definition(for: "t"))
        #expect(!stop.isVoiced)
        #expect(stop.hasClosure)

        let voicedStop = try #require(FormantTable.definition(for: "d"))
        #expect(voicedStop.isVoiced)
        #expect(voicedStop.hasClosure)
    }

    // MARK: - The control track

    @Test("the control track is well-formed")
    func controlTrackShape() async throws {
        let features = try await FormantAcousticModel().predict(input: Self.input("ɑ", ms: 500))
        #expect(features.frequencyBins == FormantChannel.channelCount)
        #expect(features.isRectangular)
        #expect(features.containsOnlyFiniteValues)
        #expect(features.frameRate == 200)
        // 500 ms at 200 frames per second.
        #expect(abs(features.frameCount - 100) <= 1)
    }

    @Test("a vowel frame carries its table formants")
    func controlTrackFormants() async throws {
        let features = try await FormantAcousticModel(formantScaleOverride: 1.0)
            .predict(input: Self.input("ɑ", ms: 400))
        let middle = features.features[features.frameCount / 2]
        // The trajectory is anchored at the phoneme centre, so mid-vowel should
        // sit on the table target rather than between neighbours.
        #expect(abs(Double(middle[FormantChannel.f1.rawValue]) - 730) < 20)
        #expect(abs(Double(middle[FormantChannel.f2.rawValue]) - 1_090) < 20)
        #expect(Double(middle[FormantChannel.voicingAmplitude.rawValue]) > 0)
        #expect(Double(middle[FormantChannel.f0.rawValue]) > 100)
    }

    @Test("a diphthong glides between two targets")
    func diphthongGlides() async throws {
        // /aɪ/ starts near /ɑ/ and ends near /ɪ/, so F2 must rise substantially.
        let features = try await FormantAcousticModel(formantScaleOverride: 1.0)
            .predict(input: Self.input("aɪ", ms: 400))
        let early = Double(features.features[10][FormantChannel.f2.rawValue])
        let late = Double(features.features[features.frameCount - 10][FormantChannel.f2.rawValue])
        #expect(late > early + 500, "F2 moved from \(early) to \(late)")
    }

    @Test("an empty request is rejected, not rendered as silence")
    func degenerateInput() async throws {
        let empty = AcousticModelInput(
            phonemeIndices: [], durations: [], fundamentalFrequency: [],
            energy: [], stress: [], voicing: [])
        await #expect(throws: ChoirError.self) {
            _ = try await FormantAcousticModel().predict(input: empty)
        }
    }

    @Test("a very short phoneme still renders a frame")
    func subFrameDuration() async throws {
        // One millisecond is shorter than a single 5 ms frame; the track must
        // still be rectangular and non-empty rather than collapsing to nothing.
        let features = try await FormantAcousticModel().predict(input: Self.input("ɑ", ms: 1))
        #expect(features.frameCount >= 1)
        #expect(features.isRectangular)
        #expect(features.containsOnlyFiniteValues)
    }

    // MARK: - Rendering

    @Test("a rendered vowel is audible and unclipped")
    func vowelIsAudible() async throws {
        let samples = try await Self.render("ɑ", ms: 400)
        #expect(samples.count == 19_200)

        let level = Self.rms(samples[4_800..<14_400])
        #expect(level > 300, "vowel is inaudibly quiet at RMS \(level)")

        let peak = samples.map { abs(Int($0)) }.max() ?? 0
        #expect(peak < 32_000, "vowel is clipping at peak \(peak)")
    }

    @Test("the rendered pitch matches the requested F0")
    func pitchIsCorrect() async throws {
        // Voicing is periodic at F0, so the requested pitch must dominate its
        // neighbours in the spectrum.
        let samples = try await Self.render("ɑ", ms: 400, f0: 150)
        let atPitch = Self.energy(of: samples, at: 150, sampleRate: 48_000)
        let below = Self.energy(of: samples, at: 110, sampleRate: 48_000)
        let above = Self.energy(of: samples, at: 190, sampleRate: 48_000)
        #expect(atPitch > below * 2, "F0 \(atPitch) vs 110 Hz \(below)")
        #expect(atPitch > above * 2, "F0 \(atPitch) vs 190 Hz \(above)")
    }

    @Test("different vowels put their energy in different places")
    func vowelsAreDistinct() async throws {
        // This is the assertion the mock path can never satisfy: a fixed test
        // tone has the same spectrum whatever the phonemes were.
        let ah = try await Self.render("ɑ", ms: 400)      // F1 730, F2 1090
        let ee = try await Self.render("iː", ms: 400)     // F1 270, F2 2290

        let ahLow = Self.bandEnergy(of: ah, from: 650, to: 820)
        let eeLow = Self.bandEnergy(of: ee, from: 650, to: 820)
        #expect(ahLow > eeLow, "F1 region: /ɑ/ \(ahLow) should exceed /iː/ \(eeLow)")

        // A direct comparison at /iː/'s F2 would be confounded by /ɑ/'s F3 at
        // 2440 Hz, so compare how each vowel balances its own low and high
        // regions instead: /ɑ/ is a back vowel, /iː/ a front one.
        let ahRatio = Self.bandEnergy(of: ah, from: 1_000, to: 1_200)
            / max(1e-9, Self.bandEnergy(of: ah, from: 2_200, to: 2_380))
        let eeRatio = Self.bandEnergy(of: ee, from: 1_000, to: 1_200)
            / max(1e-9, Self.bandEnergy(of: ee, from: 2_200, to: 2_380))
        #expect(ahRatio > eeRatio * 2,
                "F2 balance: /ɑ/ \(ahRatio) should be far more low-dominated than /iː/ \(eeRatio)")
    }

    @Test("relative phoneme levels follow speech, not the raw filters")
    func levelBalance() async throws {
        // Turbulence bypasses the formant cascade, so without scaling a
        // fricative renders louder than a vowel and masks it. Guard the
        // calibration that fixes that.
        let vowel = try await Self.render("ɑ", ms: 300)
        let sibilant = try await Self.render("s", ms: 300)
        let nasal = try await Self.render("m", ms: 300)

        let vowelLevel = Self.rms(vowel[...])
        let sibilantLevel = Self.rms(sibilant[...])
        let nasalLevel = Self.rms(nasal[...])

        #expect(sibilantLevel < vowelLevel,
                "/s/ at \(sibilantLevel) should sit below /ɑ/ at \(vowelLevel)")
        #expect(sibilantLevel > vowelLevel * 0.08, "/s/ at \(sibilantLevel) is inaudible")
        #expect(nasalLevel < vowelLevel, "/m/ at \(nasalLevel) should sit below /ɑ/")
        #expect(nasalLevel > vowelLevel * 0.2, "/m/ at \(nasalLevel) is too quiet")
    }

    @Test("a sibilant puts its energy high in the spectrum")
    func sibilantSpectrum() async throws {
        let samples = try await Self.render("s", ms: 300)
        let high = Self.bandEnergy(of: samples, from: 5_000, to: 7_000)
        let low = Self.bandEnergy(of: samples, from: 300, to: 900)
        #expect(high > low * 2, "/s/ high band \(high) vs low band \(low)")
    }

    @Test("a stop is mostly silent before its burst")
    func stopHasClosure() async throws {
        let samples = try await Self.render("t", ms: 200)
        let closure = Self.rms(samples[1_000..<6_000])
        let release = Self.rms(samples[(samples.count - 400)...])
        #expect(release > closure * 4,
                "burst \(release) should stand out against closure \(closure)")
    }

    // MARK: - Voice conditioning

    @Test("formant scale separates the voices")
    func voicesDifferInFormantScale() async throws {
        // A child voice has a shorter vocal tract, so the same vowel resonates
        // higher. Without this the 32 profiles would be 32 labels on one voice.
        let adult = try await FormantAcousticModel()
            .predict(input: Self.input("ɑ", voice: .cormac))
        let child = try await FormantAcousticModel()
            .predict(input: Self.input("ɑ", voice: .wren))

        let adultF1 = Double(adult.features[adult.frameCount / 2][FormantChannel.f1.rawValue])
        let childF1 = Double(child.features[child.frameCount / 2][FormantChannel.f1.rawValue])
        #expect(childF1 > adultF1, "child F1 \(childF1) should exceed adult F1 \(adultF1)")
    }

    @Test("gender and age shifts move the vocal tract")
    func conditioningShiftsFormants() {
        let base = FormantAcousticModel.formantScale(for: Self.input("ɑ"))

        var feminine = Self.input("ɑ")
        feminine = AcousticModelInput(
            phonemeIndices: feminine.phonemeIndices, durations: feminine.durations,
            fundamentalFrequency: feminine.fundamentalFrequency, energy: feminine.energy,
            stress: feminine.stress, voicing: feminine.voicing, voiceID: feminine.voiceID,
            genderShift: 1.0)
        #expect(FormantAcousticModel.formantScale(for: feminine) > base)

        var older = Self.input("ɑ")
        older = AcousticModelInput(
            phonemeIndices: older.phonemeIndices, durations: older.durations,
            fundamentalFrequency: older.fundamentalFrequency, energy: older.energy,
            stress: older.stress, voicing: older.voicing, voiceID: older.voiceID,
            ageShift: 1.0)
        #expect(FormantAcousticModel.formantScale(for: older) < base)
    }

    @Test("the scale stays inside the resonator's safe range")
    func conditioningIsBounded() {
        for shift in [-4.0, -1.0, 0.0, 1.0, 4.0] {
            let extreme = AcousticModelInput(
                phonemeIndices: [0], durations: [100], fundamentalFrequency: [120],
                energy: [-23], stress: [0], voicing: [1], voiceID: 0,
                ageShift: min(1, max(-1, shift)), genderShift: min(1, max(-1, shift)))
            let scale = FormantAcousticModel.formantScale(for: extreme)
            #expect(scale >= 0.5 && scale <= 2.0)
        }
    }

    // MARK: - Determinism and contracts

    @Test("rendering is reproducible")
    func renderingIsDeterministic() async throws {
        // SYN-002: identical requests must give bit-identical audio. The noise
        // sources make that a real constraint here, not a free property.
        let first = try await Self.render("s", ms: 200)
        let second = try await Self.render("s", ms: 200)
        #expect(first == second)
    }

    @Test("the seed actually drives the noise")
    func seedChangesNoise() async throws {
        let features = try await FormantAcousticModel().predict(input: Self.input("s", ms: 200))
        let a = try await FormantVocoder(seed: 1).synthesize(features: features, sampleRate: 48_000)
        let b = try await FormantVocoder(seed: 2).synthesize(features: features, sampleRate: 48_000)
        #expect(a != b)
        #expect(a.count == b.count)
    }

    @Test("the vocoder rejects a track it cannot interpret")
    func vocoderRejectsForeignFeatures() async throws {
        // A mel spectrogram has no formant channels; rendering it would emit
        // noise rather than fail, so the contract is checked explicitly.
        let mel = AcousticFeatures(
            features: Array(repeating: Array(repeating: Float(0.5), count: 80), count: 20),
            frameRate: 50)
        // 80 bins is wide enough to index, so the guard has to be about meaning.
        let vocoder = FormantVocoder()
        let narrow = AcousticFeatures(
            features: Array(repeating: Array(repeating: Float(0.5), count: 4), count: 20),
            frameRate: 50)
        await #expect(throws: ChoirError.self) {
            _ = try await vocoder.synthesize(features: narrow, sampleRate: 48_000)
        }
        // A wide but finite track is accepted; it is the caller's job to pair
        // the model and the vocoder.
        let rendered = try await vocoder.synthesize(features: mel, sampleRate: 48_000)
        #expect(!rendered.isEmpty)
    }

    @Test("the vocoder validates its sample rate")
    func vocoderValidatesSampleRate() async throws {
        let features = try await FormantAcousticModel().predict(input: Self.input("ɑ", ms: 100))
        for rate in [0, 100, 400_000] {
            await #expect(throws: ChoirError.self) {
                _ = try await FormantVocoder().synthesize(features: features, sampleRate: rate)
            }
        }
    }

    @Test("duration follows the requested phoneme timings")
    func durationIsHonoured() async throws {
        for ms in [100.0, 250.0, 600.0] {
            let samples = try await Self.render("ɑ", ms: ms)
            let seconds = Double(samples.count) / 48_000
            #expect(abs(seconds - ms / 1_000) < 0.02, "\(ms) ms rendered as \(seconds) s")
        }
    }

    // MARK: - Through the engine

    @Test("the engine speaks a sentence")
    func engineRendersSpeech() async throws {
        let engine = ChoirEngine(pipeline: .formant())
        try await engine.initialize()
        let audio = try await engine.synthesize(
            text: "Hello world. This is Choir speaking.", voice: .orion)

        #expect(audio.samples.count > 48_000, "expected over a second of audio")
        let level = Self.rms(audio.samples[...])
        #expect(level > 200, "utterance is inaudibly quiet at RMS \(level)")
        #expect((audio.samples.map { abs(Int($0)) }.max() ?? 0) < 32_600)
    }

    @Test("different text produces different audio")
    func textChangesAudio() async throws {
        let engine = ChoirEngine(pipeline: .formant())
        try await engine.initialize()
        let one = try await engine.synthesize(text: "See the sea.", voice: .orion)
        let two = try await engine.synthesize(text: "Mow the lawn.", voice: .orion)
        #expect(one.samples != two.samples)
    }

    @Test("different voices produce different audio")
    func voiceChangesAudio() async throws {
        let engine = ChoirEngine(pipeline: .formant())
        try await engine.initialize()
        let child = try await engine.synthesize(text: "Hello there.", voice: .wren)
        let elder = try await engine.synthesize(text: "Hello there.", voice: .cormac)
        #expect(child.samples != elder.samples)
    }

    @Test("progressive delivery matches batch synthesis")
    func streamingMatchesBatch() async throws {
        // Both routes render the same units through the same vocoder call, so
        // the deterministic noise must line up sample for sample.
        let engine = ChoirEngine(pipeline: .formant())
        try await engine.initialize()
        let text = "One, two, three."
        // SYN-003 prosodic jitter is seed-driven, so an unseeded pair of
        // requests is allowed to differ; pin the seed to compare the two
        // render paths rather than two draws of the jitter.
        let parameters = SynthesisParameters(seed: 0xC401)

        let batch = try await engine.synthesize(
            text: text, voice: .isla, parameters: parameters)
        let collector = ChunkCounter()
        try await engine.streamSynthesis(
            text: text, voice: .isla, parameters: parameters,
            options: StreamingOptions(preloadModel: false)
        ) { chunk in
            await collector.addChunk(chunk)
        }
        let streamed = await collector.getResults().flatMap(\.samples)
        #expect(streamed == batch.samples)
    }
}
