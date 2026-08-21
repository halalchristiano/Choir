import Foundation
import Testing
@testable import Choir

/// SRS TXT-022 (MUST) — runtime user lexicon.
///
/// "A user lexicon API shall allow consuming apps to register custom
/// pronunciations (word → phonemes or word → respelling) at runtime,
/// persisting per app, taking precedence over the built-in lexicon."
///
/// The rationale names the motivating cases: theological names (Socinus,
/// Crellius, Athanasius, Melchizedek), invented game names, and brand names
/// must be pronounceable on day one without a package update.
@Suite("SRS TXT-022 — user lexicon")
struct UserLexiconTests {

    @Test("TXT-022: registers an explicit phoneme sequence")
    func testRegisterPhonemes() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "Melchizedek", phonemes: ["m", "ɛ", "l", "k", "ɪ", "z", "ə", "d", "ɛ", "k"])

        let stored = await lexicon.pronunciation(for: "Melchizedek")
        #expect(stored == .phonemes(["m", "ɛ", "l", "k", "ɪ", "z", "ə", "d", "ɛ", "k"]))
    }

    @Test("TXT-022: lookup is case-insensitive")
    func testCaseInsensitive() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "Socinus", respelling: "so SY nus")

        for spelling in ["Socinus", "socinus", "SOCINUS", "  Socinus  "] {
            let found = await lexicon.contains(spelling)
            #expect(found, "did not resolve \(spelling)")
        }
    }

    @Test("TXT-022: registrations take precedence over the built-in lexicon")
    func testPrecedence() async {
        // "the" is in the built-in dictionary, so it proves precedence.
        let custom = [Phoneme("z"), Phoneme("æ"), Phoneme("p")]
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "the", phonemes: custom.map(\.symbol))

        let snapshot = await lexicon.snapshot()
        let overridden = Phonemizer(userLexicon: snapshot).phonemize("the")
        let builtIn = Phonemizer().phonemize("the")

        #expect(overridden.map(\.symbol) == custom.map(\.symbol))
        #expect(overridden.map(\.symbol) != builtIn.map(\.symbol),
                "override produced the built-in pronunciation")
    }

    @Test("TXT-022: respellings are phonemized by the normal rules")
    func testRespelling() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "Crellius", respelling: "krel ee us")

        let snapshot = await lexicon.snapshot()
        let phonemes = Phonemizer(userLexicon: snapshot).phonemize("Crellius")
        #expect(!phonemes.isEmpty, "respelling produced no phonemes")

        let unregistered = Phonemizer().phonemize("Crellius")
        #expect(phonemes.map(\.symbol) != unregistered.map(\.symbol),
                "respelling did not change the pronunciation")
    }

    @Test("TXT-022: registrations can be removed")
    func testRemoval() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "Athanasius", respelling: "ath uh NAY zhus")
        #expect(await lexicon.contains("Athanasius"))

        let removed = await lexicon.remove(word: "athanasius")
        #expect(removed)
        #expect(!(await lexicon.contains("Athanasius")))

        let removedAgain = await lexicon.remove(word: "athanasius")
        #expect(!removedAgain, "removing a missing word reported success")
    }

    /// TXT-022 requires registrations to persist per app.
    @Test("TXT-022: registrations persist across instances")
    func testPersistence() async {
        let store = InMemoryLexiconStore()

        let first = UserLexicon(store: store)
        await first.register(word: "Ponte", respelling: "PON tay")

        // A fresh lexicon over the same store must see the registration.
        let second = UserLexicon(store: store)
        #expect(await second.contains("Ponte"))
        #expect(await second.pronunciation(for: "Ponte") == .respelling("PON tay"))
    }

    @Test("TXT-022: bulk registration")
    func testBulkRegistration() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register([
            "socinus": .respelling("so SY nus"),
            "crellius": .respelling("KREL ee us"),
            "melchizedek": .phonemes(["m", "ɛ", "l"]),
        ])
        #expect(await lexicon.count == 3)

        await lexicon.removeAll()
        #expect(await lexicon.count == 0)
    }

    @Test("TXT-022: snapshot is a stable copy")
    func testSnapshotIsStable() async {
        let lexicon = UserLexicon(store: InMemoryLexiconStore())
        await lexicon.register(word: "wick", respelling: "wik")
        let snapshot = await lexicon.snapshot()

        await lexicon.removeAll()

        // The snapshot taken for an in-flight request must not change under it.
        #expect(snapshot.pronunciation(for: "wick") == .respelling("wik"))
        #expect(await lexicon.count == 0)
    }

    @Test("TXT-022: an empty lexicon changes nothing")
    func testEmptyLexiconIsInert() {
        let plain = Phonemizer().phonemize("hello")
        let withEmpty = Phonemizer(userLexicon: .empty).phonemize("hello")
        #expect(plain.map(\.symbol) == withEmpty.map(\.symbol))
    }
}

/// SRS SYN-005 (MUST) — synthesis metadata.
///
/// "Every synthesis result shall include metadata: total duration; per-word and
/// per-phoneme timing (start/end ms); sentence boundaries; positions of all
/// <mark> tags; the effective parameter set used; and any diagnostics."
///
/// The specification calls this "a core deliverable, not an extra", because
/// verse highlighting, caption sync, lip-sync and video timeline placement all
/// depend on it.
@Suite("SRS SYN-005 — synthesis metadata")
struct SynthesisMetadataTests {

    private func metadata(for text: String) throws -> SynthesisMetadata {
        let transcript = try LinguisticFrontend().process(text)
        // One phoneme, 50 ms each, so expected timings are exactly computable.
        let durations = Array(repeating: 50.0, count: transcript.phonemes.count)
        let audio = AudioBuffer(samples: [], format: AudioFormat())
        return SynthesisPipeline.buildMetadata(
            transcript: transcript,
            durationsMs: durations,
            audio: audio,
            voice: .isla,
            parameters: SynthesisParameters(rate: 1.1)
        )
    }

    @Test("SYN-005: per-phoneme timing is contiguous and ordered")
    func testPhonemeTiming() throws {
        let meta = try metadata(for: "Hello world.")
        #expect(!meta.phonemes.isEmpty)

        var previousEnd = 0.0
        for span in meta.phonemes {
            #expect(span.startMs == previousEnd, "gap or overlap at \(span.content)")
            #expect(span.endMs >= span.startMs)
            previousEnd = span.endMs
        }
    }

    @Test("SYN-005: per-word timing covers its phonemes")
    func testWordTiming() throws {
        let meta = try metadata(for: "Hello world.")
        #expect(!meta.words.isEmpty)

        for span in meta.words {
            #expect(span.durationMs > 0, "word \(span.content) had no duration")
            #expect(!span.content.isEmpty, "word span carried no text")
        }

        // Words run in order and do not overlap.
        for (a, b) in zip(meta.words, meta.words.dropFirst()) {
            #expect(a.endMs <= b.startMs, "\(a.content) overlaps \(b.content)")
        }
    }

    @Test("SYN-005: total duration is reported")
    func testTotalDuration() throws {
        let meta = try metadata(for: "Hello world.")
        #expect(meta.totalDurationMs > 0)
        // With no audio, the total falls back to the prosody sum.
        if let last = meta.phonemes.last {
            #expect(meta.totalDurationMs >= last.endMs - 0.001)
        }
    }

    @Test("SYN-005: sentence boundaries are reported")
    func testSentenceBoundaries() throws {
        let meta = try metadata(for: "First one. Second one. Third one.")
        #expect(meta.sentences.count >= 2, "found \(meta.sentences.count) sentences")

        // Ranges must be ordered, non-overlapping and within bounds.
        var previousEnd = 0
        for range in meta.sentences {
            #expect(range.lowerBound >= previousEnd)
            #expect(range.upperBound <= meta.words.count)
            previousEnd = range.upperBound
        }
    }

    @Test("SYN-005: the effective parameter set and voice are recorded")
    func testEffectiveParameters() throws {
        let meta = try metadata(for: "Hello world.")
        #expect(meta.voice == .isla)
        // 1.1 is inside the permitted range, so it survives clamping.
        #expect(meta.effectiveParameters.rate == 1.1)
    }

    /// The query that verse highlighting is built on.
    @Test("SYN-005: word lookup by playback time")
    func testWordAtTime() throws {
        let meta = try metadata(for: "Hello world.")
        guard let first = meta.words.first, let last = meta.words.last else {
            Issue.record("no words")
            return
        }

        #expect(meta.word(at: first.startMs)?.content == first.content)
        #expect(meta.word(at: last.endMs - 0.001)?.content == last.content)
        #expect(meta.word(at: -1) == nil)
        #expect(meta.word(at: last.endMs + 10_000) == nil)
    }

    /// The query lip-sync is built on.
    @Test("SYN-005: phoneme lookup by playback time")
    func testPhonemeAtTime() throws {
        let meta = try metadata(for: "Hello world.")
        guard let first = meta.phonemes.first else {
            Issue.record("no phonemes")
            return
        }
        #expect(meta.phoneme(at: first.startMs)?.content == first.content)
        #expect(meta.phoneme(at: -1) == nil)
    }

    @Test("SYN-005: spans are start-inclusive and end-exclusive")
    func testSpanBoundaries() {
        let span = TimedSpan(content: "a", startMs: 100, endMs: 200)
        #expect(span.contains(100))
        #expect(span.contains(199.999))
        #expect(!span.contains(200), "adjacent spans would both match")
        #expect(!span.contains(99.999))
        #expect(span.durationMs == 100)
    }

    @Test("SYN-005: metadata survives a Codable round trip")
    func testCodable() throws {
        let meta = try metadata(for: "Hello world.")
        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(SynthesisMetadata.self, from: data)
        #expect(decoded == meta)
    }

    /// Robustness: fewer durations than phonemes must not trap (SYN-008).
    @Test("SYN-005: mismatched duration count does not trap")
    func testMismatchedDurations() throws {
        let transcript = try LinguisticFrontend().process("Hello world.")
        let meta = SynthesisPipeline.buildMetadata(
            transcript: transcript,
            durationsMs: [],  // deliberately empty
            audio: AudioBuffer(samples: [], format: AudioFormat()),
            voice: .isla,
            parameters: SynthesisParameters()
        )
        #expect(meta.phonemes.count == transcript.phonemes.count)
        #expect(meta.totalDurationMs >= 0)
    }
}
