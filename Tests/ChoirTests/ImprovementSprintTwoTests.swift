import Foundation
import Testing
@testable import Choir

@Suite("Second improvement sprint: SSML resilience")
struct SSMLResilienceSprintTwoTests {
    @Test("Break durations never resolve negative")
    func breakClampsNegative() {
        #expect(SSMLBreak(timeMs: -25).resolvedMs == 0)
    }

    @Test("Non-finite break duration uses the medium default")
    func breakDefaultsNonFinite() {
        #expect(SSMLBreak(timeMs: .infinity).resolvedMs == 300)
    }

    @Test("Negative parsed durations are rejected")
    func negativeDurationRejected() {
        #expect(SSMLCParser.parseDuration("-1s") == nil)
    }

    @Test("Non-finite parsed durations are rejected")
    func infiniteDurationRejected() {
        #expect(SSMLCParser.parseDuration("inf") == nil)
    }

    @Test("Seconds convert to milliseconds")
    func secondsConvert() {
        #expect(SSMLCParser.parseDuration("1.25s") == 1250)
    }

    @Test("Zero prosody rate is rejected")
    func zeroRateRejected() {
        #expect(SSMLCParser.parsePercent("0%") == nil)
    }

    @Test("Non-finite pitch is rejected")
    func infinitePitchRejected() {
        #expect(SSMLCParser.parseSemitones("infst") == nil)
    }

    @Test("Non-finite volume is rejected")
    func nanVolumeRejected() {
        #expect(SSMLCParser.parseDecibels("nandb") == nil)
    }

    @Test("Decimal numeric XML entities decode")
    func decimalEntityDecodes() throws {
        #expect(try SSMLCParser().parse("A&#38;B").plainText == "A&B")
    }

    @Test("Hex numeric XML entities decode")
    func hexadecimalEntityDecodes() throws {
        #expect(try SSMLCParser().parse("&#x41;").plainText == "A")
    }

    @Test("Double-escaped numeric entities decode only once")
    func doubleEscapedEntityStaysEscaped() throws {
        #expect(try SSMLCParser().parse("&amp;#65;").plainText == "&#65;")
    }

    @Test("Mark names are trimmed")
    func markNamesTrim() throws {
        #expect(try SSMLCParser().parse("<mark name='  verse  '/>").markNames == ["verse"])
    }

    @Test("Whitespace-only mark names report diagnostics")
    func emptyMarkReports() throws {
        let result = try SSMLCParser().parse("<mark name='   '/>")
        #expect(result.markNames.isEmpty)
        #expect(result.diagnostics.count == 1)
    }

    @Test("Invalid break time reports and safely defaults")
    func invalidBreakReports() throws {
        let result = try SSMLCParser().parse("<break time='later'/>")
        #expect(result.diagnostics.count == 1)
        guard case .pause(let pause) = result.events.first else {
            Issue.record("Expected a pause event")
            return
        }
        #expect(pause.resolvedMs == 300)
    }

    @Test("Invalid break strength reports and safely defaults")
    func invalidStrengthReports() throws {
        let result = try SSMLCParser().parse("<break strength='huge'/>")
        #expect(result.diagnostics.count == 1)
    }

    @Test("Strict parsing throws for invalid break time")
    func strictBreakThrows() {
        do {
            _ = try SSMLCParser(strict: true).parse("<break time='later'/>")
            Issue.record("Expected strict parsing to throw")
        } catch {
            #expect(error is ChoirError)
        }
    }

    @Test("Mismatched nesting closes through the matching tag")
    func mismatchedNestingRecovers() throws {
        let result = try SSMLCParser().parse("<emphasis><prosody pitch='+2st'>x</emphasis>y")
        #expect(result.plainText == "xy")
        #expect(result.diagnostics.count == 1)
        guard case .speech(_, let finalStyle) = result.events.last else {
            Issue.record("Expected trailing speech")
            return
        }
        #expect(finalStyle.emphasis == .none)
        #expect(finalStyle.pitchSemitones == 0)
    }

    @Test("Attributes on closing tags are diagnosed")
    func closingAttributesDiagnosed() throws {
        let result = try SSMLCParser().parse("<emphasis>x</emphasis level='strong'>")
        #expect(result.plainText == "x")
        #expect(result.diagnostics.count == 1)
    }
}

@Suite("Second improvement sprint: safe audio")
struct SafeAudioSprintTwoTests {
    let filters = AudioFilters()
    let samples: [Int16] = [0, 1_000, -2_000, 3_000]

    @Test("PCM clamp maps NaN to silence")
    func nanPCMIsSilence() {
        #expect(AudioFilters.clampToPCM(.nan) == 0)
    }

    @Test("Invalid high-pass sample rate is a no-op")
    func invalidHighPassRate() {
        #expect(filters.highPassFilter(samples, sampleRate: 0) == samples)
    }

    @Test("Invalid high-pass cutoff is a no-op")
    func invalidHighPassCutoff() {
        #expect(filters.highPassFilter(samples, cutoffFrequency: .infinity) == samples)
    }

    @Test("Invalid low-pass sample rate is a no-op")
    func invalidLowPassRate() {
        #expect(filters.lowPassFilter(samples, sampleRate: -1) == samples)
    }

    @Test("Negative low-pass cutoff is a no-op")
    func negativeLowPassCutoff() {
        #expect(filters.lowPassFilter(samples, cutoffFrequency: -20) == samples)
    }

    @Test("Non-finite normalization target remains safe")
    func normalizationHandlesInfinity() {
        #expect(filters.normalize(samples, targetLevel: .infinity).count == samples.count)
    }

    @Test("Non-finite soft-clip threshold remains safe")
    func softClipHandlesNaN() {
        #expect(filters.softClip(samples, threshold: .nan).count == samples.count)
    }

    @Test("Compression ratio below one cannot expand audio")
    func compressionClampsRatio() {
        #expect(filters.compress(samples, threshold: -120, ratio: 0) == samples)
    }

    @Test("Non-finite compressor values remain safe")
    func compressorHandlesNonFinite() {
        #expect(filters.compress(samples, threshold: .nan, ratio: .infinity).count == samples.count)
    }

    @Test("Invalid de-esser frequency is a no-op")
    func deEsserRejectsInvalidFrequency() {
        #expect(filters.deEsser(samples, sibilantFrequency: 0) == samples)
    }

    @Test("Negative reverb wet level becomes dry")
    func reverbClampsWetLow() {
        let long = Array(repeating: Int16(1_000), count: 3_000)
        #expect(filters.reverb(long, wetLevel: -1) == long)
    }

    @Test("Invalid reverb sample rate is a no-op")
    func reverbRejectsSampleRate() {
        #expect(filters.reverb(samples, sampleRate: 0) == samples)
    }

    @Test("Effect chains expose deterministic introspection")
    func effectChainIntrospection() {
        let chain = AudioEffectChain(sampleRate: 44_100)
            .add(AudioEffect(name: "Dry", kind: .reverb(wetLevel: 0)))
        #expect(chain.effectCount == 1)
        #expect(chain.effectNames == ["Dry"])
        #expect(chain.sampleRateHz == 44_100)
        #expect(!chain.isEmpty)
    }

    @Test("Audio buffer exposes byte and frame metrics")
    func bufferMetrics() {
        let buffer = AudioBuffer(samples: samples, format: AudioFormat(sampleRate: 2, channels: 2))
        #expect(buffer.byteCount == 8)
        #expect(buffer.frameCount == 2)
        #expect(buffer.duration == 1)
        #expect(!buffer.isEmpty)
    }

    @Test("Audio buffer extracts interleaved channels")
    func extractsChannels() {
        let buffer = AudioBuffer(samples: [1, 10, 2, 20], format: AudioFormat(channels: 2))
        #expect(buffer.samples(forChannel: 0) == [1, 2])
        #expect(buffer.samples(forChannel: 1) == [10, 20])
        #expect(buffer.samples(forChannel: 2) == nil)
    }

    @Test("Audio buffer validates frame alignment")
    func validatesAlignment() {
        let buffer = AudioBuffer(samples: [1, 2, 3], format: AudioFormat(channels: 2))
        do {
            try buffer.validate()
            Issue.record("Expected invalid frame alignment")
        } catch {
            #expect(error is ChoirError)
        }
    }

    @Test("Audio buffer reports normalized peak and RMS")
    func bufferLevels() {
        let buffer = AudioBuffer(samples: [Int16.min, 0], format: AudioFormat())
        #expect(buffer.peakAmplitude == 1)
        #expect(buffer.rmsAmplitude > 0.7 && buffer.rmsAmplitude < 0.71)
    }

    @Test("Audio chunks sanitize timestamps and report size")
    func chunkMetrics() {
        let chunk = AudioChunk(samples: [1, 2], timestamp: -.infinity)
        #expect(chunk.timestamp == nil)
        #expect(chunk.sampleCount == 2)
        #expect(chunk.byteCount == 4)
        #expect(!chunk.isEmpty)
    }

    @Test("Audio chunk duration respects channels")
    func chunkDuration() {
        let chunk = AudioChunk(samples: [1, 2, 3, 4])
        #expect(chunk.duration(format: AudioFormat(sampleRate: 2, channels: 2)) == 1)
    }
}

@Suite("Second improvement sprint: blending and parameters")
struct BlendingAndParametersSprintTwoTests {
    let blending = VoiceBlending()

    @Test("NaN blend selects the first profile")
    func nanBlendIsFirst() {
        let first = VoiceBlending.VoiceProfile(
            voice: .orion, parameters: SynthesisParameters(pitchShift: -4, seed: 1))
        let second = VoiceBlending.VoiceProfile(
            voice: .lyra, parameters: SynthesisParameters(pitchShift: 4, seed: 2))
        let result = blending.blend(first, with: second, mix: .nan)
        #expect(result.pitchShift == -4)
        #expect(result.seed == 1)
    }

    @Test("Blend seed switches at midpoint")
    func blendSeedSelection() {
        let first = VoiceBlending.VoiceProfile(voice: .orion, parameters: .init(seed: 1))
        let second = VoiceBlending.VoiceProfile(voice: .lyra, parameters: .init(seed: 2))
        #expect(blending.blend(first, with: second, mix: 0.49).seed == 1)
        #expect(blending.blend(first, with: second, mix: 0.5).seed == 2)
    }

    @Test("Zero-step gender transition returns its source")
    func zeroStepGender() {
        let result = blending.genderTransition(from: .orion, to: .lyra, steps: 0)
        #expect(result.count == 1)
        #expect(result[0].genderShift == 1)
    }

    @Test("Negative-step age transition returns its source")
    func negativeStepAge() {
        let result = blending.ageTransition(from: .wren, to: .maeve, steps: -2)
        #expect(result.count == 1)
        #expect(result[0].ageShift == -5)
    }

    @Test("Gender transition follows requested direction")
    func directionalGender() {
        let result = blending.genderTransition(from: .orion, to: .lyra, steps: 2)
        #expect(result.map(\.genderShift) == [1, 0, -1])
    }

    @Test("Age transition reaches both documented endpoints")
    func directionalAge() {
        let result = blending.ageTransition(from: .wren, to: .maeve, steps: 2)
        #expect(result.map(\.ageShift) == [-5, 0, 5])
    }

    @Test("Predefined style lookup trims and ignores case")
    func styleLookup() {
        #expect(SpeakingStyle.predefined(id: " FAST ") == .fast)
        #expect(SpeakingStyle.predefined(id: "missing") == nil)
    }

    @Test("Non-finite synthesis parameters use defaults")
    func nonFiniteParameters() {
        let parameters = SynthesisParameters(
            pitchShift: .nan, rate: .infinity, emotionalIntensity: -.infinity,
            breathiness: .nan, ageShift: .infinity, genderShift: -.infinity)
        #expect(parameters.pitchShift == 0)
        #expect(parameters.rate == 1)
        #expect(parameters.emotionalIntensity == 0.5)
        #expect(parameters.breathiness == 0)
        #expect(parameters.ageShift == 0)
        #expect(parameters.genderShift == 0)
        #expect(parameters.clampings.count == 6)
    }

    @Test("Non-finite clamping reports remain JSON encodable")
    func nonFiniteParametersEncode() throws {
        let parameters = SynthesisParameters(rate: .nan)
        #expect(try JSONEncoder().encode(parameters).isEmpty == false)
        #expect(parameters.clampings.first?.reason != nil)
    }

    @Test("Validated rebuilds directly mutated parameters")
    func validatesMutation() {
        var parameters = SynthesisParameters()
        parameters.rate = 9
        let validated = parameters.validated()
        #expect(validated.rate == 2)
        #expect(validated.wasClamped)
    }
}

@Suite("Second improvement sprint: lexicon and inventory")
struct LexiconAndInventorySprintTwoTests {
    @Test("Empty pronunciations identify themselves")
    func emptyPronunciations() {
        #expect(UserPronunciation.phonemes([" "]).isEmpty)
        #expect(UserPronunciation.respelling("\n").isEmpty)
        #expect(!UserPronunciation.phonemes(["k"]).isEmpty)
    }

    @Test("Empty lexicon keys are ignored")
    func emptyLexiconKey() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "  ", respelling: "word")
        #expect(await lexicon.count == 0)
    }

    @Test("Empty phoneme sequences are ignored")
    func emptyLexiconPhonemes() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "word", phonemes: [" ", "\n"])
        #expect(await lexicon.count == 0)
    }

    @Test("Lexicon phoneme symbols are trimmed")
    func lexiconTrimsSymbols() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "word", phonemes: [" k ", " ", "æ"])
        #expect(await lexicon.pronunciation(for: "word") == .phonemes(["k", "æ"]))
    }

    @Test("Lexicon respellings are trimmed")
    func lexiconTrimsRespelling() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "word", respelling: "  wurd  ")
        #expect(await lexicon.pronunciation(for: "word") == .respelling("wurd"))
    }

    @Test("Bulk lexicon registration skips invalid entries")
    func bulkSkipsInvalid() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(["": .respelling("x"), "valid": .respelling(" v ")])
        #expect(await lexicon.count == 1)
    }

    @Test("Snapshot words are deterministic")
    func snapshotWordsSorted() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(["z": .respelling("z"), "a": .respelling("a")])
        #expect((await lexicon.snapshot()).registeredWords == ["a", "z"])
    }

    @Test("ARPAbet lookup normalizes case and whitespace")
    func arpabetNormalizes() {
        #expect(PhonemeInventory.ipa(forARPAbet: " aa1 ") == "ɑ")
        #expect(PhonemeInventory.isValidARPAbet("iy2"))
    }

    @Test("IPA lookup trims whitespace")
    func ipaLookupTrims() {
        #expect(PhonemeInventory.arpabet(forIPA: " ɡ ") == "G")
    }

    @Test("Strict ARPAbet conversion preserves unknown tokens")
    func conversionReportsUnknown() {
        let result = PhonemeInventory.conversion(fromARPAbet: "K XX AE1 BAD")
        #expect(result.phonemes.map(\.symbol) == ["k", "æ"])
        #expect(result.unknownSymbols == ["XX", "BAD"])
        #expect(!result.isComplete)
    }

    @Test("Complete ARPAbet conversion reports completeness")
    func conversionComplete() {
        #expect(PhonemeInventory.conversion(fromARPAbet: "HH AH0").isComplete)
    }

    @Test("Duration estimate sanitizes non-finite rate")
    func estimateHandlesNaNRate() {
        let result = DurationEstimator().estimate(text: "Hello.", voice: .isla, rate: .nan)
        #expect(result.seconds.isFinite)
        #expect(result.seconds >= 0)
    }

    @Test("Duration estimate initializer sanitizes fields")
    func estimateInitializerSanitizes() {
        let result = DurationEstimate(
            seconds: .nan, syllables: -1, breathGroupCount: -2, pauseSeconds: -.infinity)
        #expect(result == DurationEstimate(seconds: 0, syllables: 0, breathGroupCount: 0, pauseSeconds: 0))
    }
}

@Suite("Second improvement sprint: metadata, cache, and sessions")
struct MetadataCacheSessionSprintTwoTests {
    private func metadata(
        total: Double = 100,
        words: [TimedSpan] = [],
        phonemes: [TimedSpan] = [],
        sentences: [Range<Int>] = [],
        marks: [MarkPosition] = [],
        diagnostics: [SynthesisDiagnostic] = []
    ) -> SynthesisMetadata {
        SynthesisMetadata(
            totalDurationMs: total, words: words, phonemes: phonemes,
            sentences: sentences, marks: marks, voice: .isla,
            diagnostics: diagnostics)
    }

    @Test("Timed spans sanitize bounds")
    func spanSanitizes() {
        let span = TimedSpan(content: "x", startMs: -.infinity, endMs: -4)
        #expect(span.startMs == 0)
        #expect(span.endMs == 0)
        #expect(span.isEmpty)
    }

    @Test("Timed span progress clamps")
    func spanProgress() {
        let span = TimedSpan(content: "x", startMs: 10, endMs: 20)
        #expect(span.midpointMs == 15)
        #expect(span.progress(at: 5) == 0)
        #expect(span.progress(at: 15) == 0.5)
        #expect(span.progress(at: 25) == 1)
        #expect(!span.contains(.nan))
    }

    @Test("Mark positions sanitize time")
    func markSanitizes() {
        #expect(MarkPosition(name: "m", timeMs: .nan).timeMs == 0)
    }

    @Test("Word lookup remains correct for unordered caller metadata")
    func unorderedWordLookup() {
        let value = metadata(words: [
            TimedSpan(content: "late", startMs: 50, endMs: 100),
            TimedSpan(content: "early", startMs: 0, endMs: 50),
        ])
        #expect(value.word(at: 25)?.content == "early")
    }

    @Test("Phoneme lookup remains correct for unordered caller metadata")
    func unorderedPhonemeLookup() {
        let value = metadata(phonemes: [
            TimedSpan(content: "b", startMs: 50, endMs: 100),
            TimedSpan(content: "a", startMs: 0, endMs: 50),
        ])
        #expect(value.phoneme(at: 25)?.content == "a")
    }

    @Test("Duplicate mark queries return every occurrence")
    func duplicateMarkTimes() {
        let value = metadata(marks: [
            MarkPosition(name: "v", timeMs: 10),
            MarkPosition(name: "v", timeMs: 20),
        ])
        #expect(value.times(ofMark: "v") == [10, 20])
    }

    @Test("Metadata partitions diagnostic severities")
    func diagnosticPartitions() {
        let value = metadata(diagnostics: [
            SynthesisDiagnostic(severity: .warning, message: "w"),
            SynthesisDiagnostic(severity: .info, message: "i"),
        ])
        #expect(value.warnings.map(\.message) == ["w"])
        #expect(value.informationalDiagnostics.map(\.message) == ["i"])
    }

    @Test("Metadata validation reports out-of-bounds content")
    func metadataValidation() {
        let value = metadata(
            words: [TimedSpan(content: "x", startMs: 90, endMs: 120)],
            sentences: [0..<2], marks: [MarkPosition(name: "late", timeMs: 101)])
        #expect(value.validationIssues.count == 3)
        #expect(!value.isStructurallyValid)
        #expect(value.durationSeconds == 0.1)
    }

    @Test("Cache exposes typed containment and removal")
    func cacheContainment() async {
        let cache = AssetCache(maxCacheSize: 1_000)
        await cache.cacheAcousticFeatures(
            AcousticFeatures(features: [[1]], frameRate: 50), for: "voice")
        #expect(await cache.containsAcousticFeatures(for: "voice"))
        #expect(await cache.cachedKeys == ["voice"])
        #expect(await cache.removeValue(for: "voice"))
        #expect(!(await cache.removeValue(for: "voice")))
    }

    @Test("Cache statistics expose totals and fractions")
    func cacheStatistics() async {
        let cache = AssetCache(maxCacheSize: 4)
        await cache.cacheAcousticFeatures(
            AcousticFeatures(features: [[1]], frameRate: 50), for: "one")
        let stats = await cache.getStatistics()
        #expect(stats.totalCount == 1)
        #expect(stats.utilizationFraction == 1)
        #expect(stats.isAtCapacity)
    }

    @Test("Session enforces one active synthesis")
    func sessionBusyState() async {
        let session = SynthesisSession()
        #expect(await session.beginSynthesis())
        #expect(!(await session.beginSynthesis()))
        await session.resetState()
        #expect(await session.getState() == .idle)
    }

    @Test("Session cache is inspectable and selectively removable")
    func sessionCacheControl() async {
        let session = SynthesisSession()
        let audio = AudioBuffer(samples: [1, 2], format: AudioFormat())
        await session.cacheAudio(audio, for: "b")
        await session.cacheAudio(audio, for: "a")
        #expect(await session.cachedKeys == ["a", "b"])
        #expect(await session.containsCachedAudio(for: "a"))
        #expect(await session.removeCachedAudio(for: "a"))
        #expect(!(await session.containsCachedAudio(for: "a")))
    }

    @Test("Session statistics report last synthesis")
    func sessionLastSynthesis() async {
        let session = SynthesisSession()
        let audio = AudioBuffer(samples: [1, 2], format: AudioFormat())
        await session.recordSynthesis(text: "hello", audio: audio)
        let stats = await session.getStatistics()
        #expect(await session.getLastSynthesizedText() == "hello")
        #expect(stats.lastSynthesizedText == "hello")
        #expect(stats.lastAudioByteCount == 4)
        #expect(!stats.hasCachedAudio)
    }

    @Test("Detailed manager statistics aggregate session caches")
    func managerDetailedStatistics() async {
        let manager = SynthesisSessionManager()
        let session = await manager.createSession()
        await session.cacheAudio(
            AudioBuffer(samples: [1, 2, 3], format: AudioFormat()), for: "x")
        let stats = await manager.getDetailedStatistics()
        #expect(stats.totalSessions == 1)
        #expect(stats.activeSessions == 1)
        #expect(stats.totalCacheSize == 6)
        #expect(stats.completedSessions == 0)
    }
}
