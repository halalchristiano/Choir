import Foundation
import Testing
@testable import Choir

@Suite("Third improvement sprint: prosody values")
struct ProsodyValueSprintThreeTests {
    @Test("Non-finite F0 uses its default")
    func f0Default() {
        #expect(ProsodyFeatures(fundamentalFrequency: .nan).fundamentalFrequency == 120)
    }

    @Test("Non-finite duration uses its default")
    func durationDefault() {
        #expect(ProsodyFeatures(duration: .infinity).duration == 100)
    }

    @Test("Non-finite energy uses its default")
    func energyDefault() {
        #expect(ProsodyFeatures(energy: -.infinity).energy == -20)
    }

    @Test("Non-finite voicing uses its default")
    func voicingDefault() {
        #expect(ProsodyFeatures(voicing: .nan).voicing == 1)
    }

    @Test("Prosody scalars remain inside documented envelopes")
    func scalarBounds() {
        let features = ProsodyFeatures(
            fundamentalFrequency: 900, duration: -4, energy: 20, voicing: -1)
        #expect(features.fundamentalFrequency == 400)
        #expect(features.duration == 10)
        #expect(features.energy == 0)
        #expect(features.voicing == 0)
    }

    @Test("Unknown accent and boundary labels safely normalize")
    func labelsNormalize() {
        let features = ProsodyFeatures(accentType: "LOUD", boundaryTone: "UP")
        #expect(features.accentType == "none")
        #expect(features.boundaryTone == "none")
    }

    @Test("Known accent and boundary labels are preserved")
    func labelsPreserve() {
        let features = ProsodyFeatures(accentType: "L+H*", boundaryTone: "H%")
        #expect(features.accentType == "L+H*")
        #expect(features.boundaryTone == "H%")
    }

    @Test("Prosody features round-trip through JSON")
    func featuresCodable() throws {
        let value = ProsodyFeatures(accentType: "H*", boundaryTone: "L%")
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(ProsodyFeatures.self, from: data) == value)
    }

    @Test("Timing sanitizes non-finite and backward bounds")
    func timingSanitizes() {
        let nonFinite = TimingInfo(startTime: .nan, endTime: .infinity)
        #expect(nonFinite == TimingInfo(startTime: 0, endTime: 0))
        let backward = TimingInfo(startTime: 50, endTime: 10)
        #expect(backward.startTime == 50)
        #expect(backward.endTime == 50)
        #expect(backward.isEmpty)
    }

    @Test("Timing exposes midpoint and half-open containment")
    func timingQueries() {
        let timing = TimingInfo(startTime: 20, endTime: 40)
        #expect(timing.midpoint == 30)
        #expect(timing.contains(20))
        #expect(!timing.contains(40))
        #expect(!timing.contains(.nan))
    }

    @Test("Timing shifts without becoming negative")
    func timingShift() {
        #expect(TimingInfo(startTime: 20, endTime: 40).shifted(by: -30)
            == TimingInfo(startTime: 0, endTime: 20))
        let original = TimingInfo()
        #expect(original.shifted(by: .nan) == original)
    }

    @Test("Annotated phonemes round-trip through JSON")
    func annotationCodable() throws {
        let value = AnnotatedPhoneme(
            phoneme: Phoneme("ɑ", stress: 1),
            prosody: ProsodyFeatures(),
            timing: TimingInfo(startTime: 0, endTime: 80))
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(AnnotatedPhoneme.self, from: data) == value)
    }

    @Test("Decoded phonemes preserve symbol and stress invariants")
    func phonemeDecodeSanitizes() throws {
        let data = Data(#"{"symbol":"g","stress":9}"#.utf8)
        let phoneme = try JSONDecoder().decode(Phoneme.self, from: data)
        #expect(phoneme.symbol == "ɡ")
        #expect(phoneme.stress == 2)
    }

    @Test("Contours discard non-finite points")
    func contourDropsInvalid() {
        let contour = ProsodyContour(points: [(.nan, 1), (0, .infinity), (1, 2)])
        #expect(contour.points.count == 1)
        #expect(contour.startTime == 1)
    }

    @Test("Contours sort points and keep the last duplicate")
    func contourSortsAndDeduplicates() {
        let contour = ProsodyContour(points: [(10, 1), (0, 0), (10, 2)])
        #expect(contour.points.map { $0.time } == [0, 10])
        #expect(contour.points.map { $0.value } == [0, 2])
    }

    @Test("Unknown interpolation falls back to linear")
    func interpolationFallback() {
        #expect(ProsodyContour(points: [], interpolation: "magic").interpolation == "linear")
        #expect(ProsodyContour(points: [], interpolation: "STEP").interpolation == "step")
    }

    @Test("Linear contours interpolate sorted points")
    func linearContour() {
        let contour = ProsodyContour(points: [(10, 20), (0, 0)], interpolation: "linear")
        #expect(contour.valueAt(5) == 10)
        #expect(contour.valueAt(-1) == 0)
        #expect(contour.valueAt(11) == 20)
    }

    @Test("Step contours hold the lower value")
    func stepContour() {
        let contour = ProsodyContour(points: [(0, 2), (10, 8)], interpolation: "step")
        #expect(contour.valueAt(5) == 2)
        #expect(contour.valueAt(10) == 8)
    }

    @Test("Contours reject non-finite query time")
    func contourRejectsNaNQuery() {
        #expect(ProsodyContour(points: [(0, 1)]).valueAt(.nan) == nil)
    }

    @Test("Contour summary properties are stable")
    func contourSummary() {
        let contour = ProsodyContour(points: [(4, -2), (1, 7), (3, 1)])
        #expect(!contour.isEmpty)
        #expect(contour.startTime == 1)
        #expect(contour.endTime == 4)
        #expect(contour.duration == 3)
        #expect(contour.minimumValue == -2)
        #expect(contour.maximumValue == 7)
    }

    @Test("Prosody descriptions use the latest timing, not array order")
    func descriptionDuration() {
        let later = AnnotatedPhoneme(phoneme: Phoneme("k"), timing: .init(startTime: 0, endTime: 200))
        let earlier = AnnotatedPhoneme(phoneme: Phoneme("æ"), timing: .init(startTime: 0, endTime: 100))
        let value = ProsodyDescription(
            phonemes: [later, earlier], pitchContour: .init(points: []),
            energyContour: .init(points: []), durations: [200, 100])
        #expect(value.totalDuration == 200)
        #expect(value.isStructurallyValid)
    }

    @Test("Prosody descriptions report duration structure issues")
    func descriptionValidation() {
        let value = ProsodyDescription(
            phonemes: [AnnotatedPhoneme(phoneme: Phoneme("k"))],
            pitchContour: .init(points: []), energyContour: .init(points: []),
            durations: [.nan, -1])
        #expect(!value.hasMatchingDurationCount)
        #expect(value.invalidDurationIndices == [0, 1])
        #expect(!value.isStructurallyValid)
    }
}

@Suite("Third improvement sprint: quality metrics")
struct QualityMetricSprintThreeTests {
    let analyzer = VoiceQualityAnalyzer()

    private var safeMetrics: VoiceQualityAnalyzer.QualityMetrics {
        .init(
            rmsLoudness: -18, peakLevel: 10_000, dynamicRange: 20,
            lufs: -22, snrEstimate: 30, clippingPercent: 0,
            zeroCrossingRate: 100)
    }

    @Test("Metric initializer sanitizes every non-finite scalar")
    func metricSanitization() {
        let value = VoiceQualityAnalyzer.QualityMetrics(
            rmsLoudness: .nan, peakLevel: -1, dynamicRange: .infinity,
            lufs: .nan, snrEstimate: -.infinity, clippingPercent: .nan,
            zeroCrossingRate: .infinity)
        #expect(value.rmsLoudness == -60)
        #expect(value.peakLevel == 0)
        #expect(value.dynamicRange == 0)
        #expect(value.lufs == -60)
        #expect(value.snrEstimate == 0)
        #expect(value.clippingPercent == 0)
        #expect(value.zeroCrossingRate == 0)
    }

    @Test("Clipping percent clamps to its physical range")
    func clippingBounds() {
        let high = VoiceQualityAnalyzer.QualityMetrics(
            rmsLoudness: 0, peakLevel: 0, dynamicRange: 0, lufs: 0,
            snrEstimate: 0, clippingPercent: 300, zeroCrossingRate: 0)
        #expect(high.clippingPercent == 100)
        #expect(high.clippingFraction == 1)
    }

    @Test("Silent metrics report negative-infinite peak dBFS")
    func silentPeak() {
        let metrics = analyzer.analyzeQuality([], sampleRate: 48_000)
        #expect(metrics.isSilent)
        #expect(metrics.peakDBFS == -Double.infinity)
    }

    @Test("Silence has finite zero dynamic range and SNR")
    func silenceIsFinite() {
        let metrics = analyzer.analyzeQuality([0, 0, 0], sampleRate: 48_000)
        #expect(metrics.dynamicRange == 0)
        #expect(metrics.snrEstimate == 0)
        #expect(metrics.zeroCrossingRate == 0)
    }

    @Test("Invalid sample rate does not create infinite zero-crossing rate")
    func invalidSampleRate() {
        let metrics = analyzer.analyzeQuality([-1, 1, -1], sampleRate: 0)
        #expect(metrics.zeroCrossingRate == 0)
    }

    @Test("Full-scale negative PCM remains safe")
    func minimumPCM() {
        let metrics = analyzer.analyzeQuality([Int16.min], sampleRate: 48_000)
        #expect(metrics.peakLevel == Int16.max)
        #expect(metrics.clippingPercent == 100)
    }

    @Test("Quality metrics round-trip through JSON")
    func metricsCodable() throws {
        let data = try JSONEncoder().encode(safeMetrics)
        #expect(try JSONDecoder().decode(VoiceQualityAnalyzer.QualityMetrics.self, from: data) == safeMetrics)
    }

    @Test("Quality report sanitizes rating")
    func reportRatingSanitizes() {
        let report = QualityReport(
            metrics: safeMetrics, rating: .nan, issues: [], recommendations: [])
        #expect(report.rating == 1)
        #expect(report.ratingStars.count > 0)
    }

    @Test("Perfect rating never calculates a negative star count")
    func perfectStars() {
        let report = QualityReport(
            metrics: safeMetrics, rating: 99, issues: [], recommendations: [])
        #expect(report.rating == 5)
        #expect(report.ratingStars == "⭐⭐⭐⭐⭐")
    }

    @Test("Quality report exposes decision helpers")
    func reportHelpers() {
        let good = QualityReport(
            metrics: safeMetrics, rating: 4.5, issues: [], recommendations: [])
        #expect(!good.hasIssues)
        #expect(good.issueCount == 0)
        #expect(good.isRecommendedForUse)
        let bad = QualityReport(
            metrics: safeMetrics, rating: 4.5, issues: ["clip"], recommendations: [])
        #expect(!bad.isRecommendedForUse)
    }

    @Test("Silent quality summary avoids a NaN peak")
    func silentSummary() {
        let report = analyzer.generateReport([], sampleRate: 0)
        #expect(report.summary.contains("−∞ dBFS"))
        #expect(!report.summary.lowercased().contains("nan"))
    }

    @Test("Quality reports round-trip through JSON")
    func reportCodable() throws {
        let report = QualityReport(
            metrics: safeMetrics, rating: 4.5,
            issues: ["one"], recommendations: ["two"])
        let data = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(QualityReport.self, from: data) == report)
    }
}

@Suite("Third improvement sprint: English expansion")
struct EnglishExpansionSprintThreeTests {
    let normalizer = TextNormalizer()

    @Test("Negative integers are spoken")
    func negativeInteger() {
        #expect(NumberSpelling.words(for: -42) == "minus forty two")
        #expect(NumberSpelling.words(for: " -7 ") == "minus seven")
    }

    @Test("Int64 minimum spells without overflow")
    func minimumInteger() {
        let spoken = NumberSpelling.words(for: Int64.min)
        #expect(spoken.hasPrefix("minus nine quintillion"))
        #expect(spoken.hasSuffix("eight hundred eight"))
    }

    @Test("Quadrillion and quintillion scales are available")
    func largeScales() {
        #expect(NumberSpelling.words(for: 1_000_000_000_000_000) == "one quadrillion")
        #expect(NumberSpelling.words(for: 1_000_000_000_000_000_000) == "one quintillion")
    }

    @Test("Negative ordinals remain grammatical")
    func negativeOrdinal() {
        #expect(NumberSpelling.ordinal(for: -21) == "minus twenty first")
    }

    @Test("Malformed Roman numerals are rejected")
    func malformedRoman() {
        #expect(TextNormalizer.romanValue("IIV") == nil)
        #expect(TextNormalizer.romanValue("VX") == nil)
        #expect(TextNormalizer.romanValue("IIII") == nil)
    }

    @Test("Canonical Roman numerals remain accepted case-insensitively")
    func canonicalRoman() {
        #expect(TextNormalizer.romanValue("xiv") == 14)
        #expect(TextNormalizer.romanValue("MMMCMXCIX") == 3999)
    }

    @Test("Twelve-hour suffix rejects twenty-four-hour values")
    func suffixClockValidation() {
        #expect(normalizer.expandClockTimes("13:00 pm") == "13:00 pm")
        #expect(normalizer.expandClockTimes("11:00 pm") == "eleven o'clock p m")
    }

    @Test("Gregorian leap-day validation is correct")
    func leapDates() {
        #expect(TextNormalizer.isValidDate(year: 2000, month: 2, day: 29))
        #expect(!TextNormalizer.isValidDate(year: 1900, month: 2, day: 29))
        #expect(TextNormalizer.isValidDate(year: 2024, month: 2, day: 29))
        #expect(!TextNormalizer.isValidDate(year: 2023, month: 2, day: 29))
    }

    @Test("Impossible month dates remain unexpanded")
    func impossibleDates() {
        #expect(normalizer.expandDates("2025-04-31") == "2025-04-31")
        #expect(normalizer.expandDates("02/29/2023") == "02/29/2023")
    }

    @Test("Valid dates still expand")
    func validDates() {
        #expect(normalizer.expandDates("2024-02-29").contains("february twenty ninth"))
    }
}

@Suite("Third improvement sprint: segmentation")
struct SegmentationSprintThreeTests {
    @Test("Phrase boundaries expose seconds and document weight")
    func boundaryQueries() {
        #expect(PhraseBoundary.major.nominalPauseSeconds == 0.5)
        #expect(!PhraseBoundary.major.isDocumentBoundary)
        #expect(PhraseBoundary.paragraph.isDocumentBoundary)
    }

    @Test("Breath groups trim their outer whitespace")
    func groupTrims() {
        let group = BreathGroup(text: "  hello \n", boundary: .major)
        #expect(group.text == "hello")
        #expect(!group.isEmpty)
    }

    @Test("Empty and punctuation-only groups have zero syllables")
    func emptySyllables() {
        #expect(BreathGroup(text: "", boundary: .minor).estimatedSyllables == 0)
        #expect(BreathGroup(text: "!!!", boundary: .minor).estimatedSyllables == 0)
    }

    @Test("Invalid speech tempo yields a finite zero estimate")
    func invalidTempo() {
        let group = BreathGroup(text: "hello", boundary: .minor)
        #expect(group.estimatedDurationSeconds(syllablesPerSecond: .nan) == 0)
        #expect(group.estimatedDurationSeconds(syllablesPerSecond: 0) == 0)
    }

    @Test("Segmenter clamps word cap to one")
    func wordCapClamps() {
        #expect(SentenceSegmenter(maxWordsPerBreathGroup: 0).maxWordsPerBreathGroup == 1)
    }

    @Test("Segmenter replaces invalid duration ceiling")
    func durationCeilingDefaults() {
        #expect(SentenceSegmenter(maxBreathGroupSeconds: .nan).maxBreathGroupSeconds == 9)
        #expect(SentenceSegmenter(maxBreathGroupSeconds: -1).maxBreathGroupSeconds == 9)
    }

    @Test("Empty input produces no breath group")
    func emptyInput() {
        #expect(SentenceSegmenter().breathGroups(in: "   ").isEmpty)
        #expect(SentenceSegmenter().segment("\n \n").isEmpty)
    }

    @Test("Ellipses remain attached to one sentence")
    func ellipsisAttachment() {
        let sentences = SentenceSegmenter().sentences(in: "Wait... Then go.")
        #expect(sentences.map(\.text) == ["Wait...", "Then go."])
    }

    @Test("Combined dialogue punctuation remains attached")
    func combinedPunctuation() {
        let sentences = SentenceSegmenter().sentences(in: "Really?! Yes.")
        #expect(sentences.map(\.text) == ["Really?!", "Yes."])
    }

    @Test("Terminal etcetera can end before a capitalized sentence")
    func terminalAbbreviation() {
        let sentences = SentenceSegmenter().sentences(in: "Bring rope, food, etc. Then leave.")
        #expect(sentences.count == 2)
    }

    @Test("Titles remain non-terminal before names")
    func titleAbbreviation() {
        let sentences = SentenceSegmenter().sentences(in: "Dr. Smith arrived. He sat.")
        #expect(sentences.map(\.text) == ["Dr. Smith arrived.", "He sat."])
    }

    @Test("Scripture abbreviations remain non-terminal before references")
    func scriptureAbbreviation() {
        let sentences = SentenceSegmenter().sentences(in: "Read Gen. 1 today. Then rest.")
        #expect(sentences.count == 2)
    }

    @Test("Invalid segmentation tempo uses a safe default")
    func segmentationTempoDefaults() {
        let segmenter = SentenceSegmenter(maxWordsPerBreathGroup: 2)
        let groups = segmenter.breathGroups(in: "one two three", syllablesPerSecond: .nan)
        #expect(groups.count >= 2)
    }
}

@Suite("Third improvement sprint: explainable scoring")
struct ExplainableScoringSprintThreeTests {
    @Test("Hyphen variants become word boundaries")
    func hyphenNormalization() {
        #expect(TranscriptionScoring.normalizedWords("state-of—the-art")
            == ["state", "of", "the", "art"])
    }

    @Test("Curly apostrophes normalize without losing contractions")
    func apostropheNormalization() {
        #expect(TranscriptionScoring.normalizedWords("It’s ITS") == ["it's", "its"])
    }

    @Test("Exact alignment reports only correct words")
    func exactBreakdown() {
        let value = TranscriptionScoring.breakdown(reference: "one two", hypothesis: "one two")
        #expect(value.correct == 2)
        #expect(value.totalErrors == 0)
        #expect(value.isExactMatch)
        #expect(value.wordAccuracy == 1)
    }

    @Test("Substitutions are counted separately")
    func substitutionBreakdown() {
        let value = TranscriptionScoring.breakdown(reference: "one two", hypothesis: "one too")
        #expect(value.substitutions == 1)
        #expect(value.deletions == 0)
        #expect(value.insertions == 0)
    }

    @Test("Deletions are counted separately")
    func deletionBreakdown() {
        let value = TranscriptionScoring.breakdown(reference: "one two", hypothesis: "one")
        #expect(value.deletions == 1)
        #expect(value.hypothesisWordCount == 1)
    }

    @Test("Insertions are counted separately")
    func insertionBreakdown() {
        let value = TranscriptionScoring.breakdown(reference: "one", hypothesis: "one two")
        #expect(value.insertions == 1)
        #expect(value.wordErrorRate == 1)
    }

    @Test("Empty alignment behavior is explicit")
    func emptyBreakdown() {
        #expect(TranscriptionScoring.breakdown(reference: "", hypothesis: "").wordErrorRate == 0)
        let inserted = TranscriptionScoring.breakdown(reference: "", hypothesis: "word")
        #expect(inserted.wordErrorRate == 1)
        #expect(inserted.insertions == 1)
    }

    @Test("Alignment operations preserve speaking order")
    func operationOrder() {
        let value = TranscriptionScoring.breakdown(reference: "a b", hypothesis: "a c")
        #expect(value.operations == [
            .match("a"), .substitution(reference: "b", hypothesis: "c"),
        ])
    }

    @Test("Breakdowns round-trip through JSON")
    func breakdownCodable() throws {
        let value = TranscriptionScoring.breakdown(reference: "a b", hypothesis: "a c d")
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(TranscriptionScoring.WordErrorBreakdown.self, from: data) == value)
    }

    @Test("Sentence scores expose word counts and error types")
    func sentenceScoreDetails() {
        let score = SentenceScore(reference: "one two", hypothesis: "one too extra")
        #expect(score.referenceWordCount == 2)
        #expect(score.hypothesisWordCount == 3)
        #expect(score.totalErrors == 2)
        #expect(!score.isExactMatch)
    }

    @Test("Reports expose corpus totals and failed sentences")
    func reportDetails() {
        let report = IntelligibilityReport(
            voice: .isla, condition: .defaultParameters,
            transcriberIdentifier: "test", parameters: .init(), scores: [
                SentenceScore(reference: "one", hypothesis: "one"),
                SentenceScore(reference: "two", hypothesis: "too"),
            ])
        #expect(report.totalReferenceWords == 2)
        #expect(report.totalErrors == 1)
        #expect(report.exactSentenceCount == 1)
        #expect(report.sentenceAccuracy == 0.5)
        #expect(report.failedSentences.count == 1)
        #expect(!report.isEmpty)
    }

    @Test("Harness trims, removes empty sentences, and de-duplicates")
    func harnessNormalizesCorpus() {
        let harness = IntelligibilityHarness(sentences: [" one ", "", "one", "two"])
        #expect(harness.sentences == ["one", "two"])
    }

    @Test("Transcriber failures propagate instead of becoming false zero scores")
    func transcriberFailurePropagates() async throws {
        enum TestFailure: Error { case failed }
        struct Thrower: SpeechTranscriber {
            let identifier = "thrower"
            var isAvailable: Bool { get async { true } }
            func transcribe(_ audio: AudioBuffer) async throws -> String { throw TestFailure.failed }
        }
        let engine = ChoirEngine()
        try await engine.initialize()
        do {
            _ = try await IntelligibilityHarness(sentences: ["one"])
                .evaluate(voice: .isla, engine: engine, transcriber: Thrower())
            Issue.record("Expected transcription failure")
        } catch {
            #expect(error is TestFailure)
        }
    }
}

@Suite("Third improvement sprint: G2P evidence")
struct G2PEvidenceSprintThreeTests {
    @Test("Report initializer sanitizes impossible counts")
    func reportSanitizes() {
        let report = G2PEvaluator.Report(
            wordCount: -1, referencePhonemeCount: -2,
            totalEditDistance: -3, exactMatches: 9,
            missingReferences: -4, invalidReferences: -5)
        #expect(report.wordCount == 0)
        #expect(report.referencePhonemeCount == 0)
        #expect(report.totalEditDistance == 0)
        #expect(report.exactMatches == 0)
        #expect(report.skippedWords == 0)
        #expect(!report.hasUsableSample)
    }

    @Test("Report exposes error rate and inexact matches")
    func reportQueries() {
        let report = G2PEvaluator.Report(
            wordCount: 4, referencePhonemeCount: 10,
            totalEditDistance: 2, exactMatches: 3)
        #expect(report.phonemeErrorRate == 0.2)
        #expect(report.phonemeAccuracy == 0.8)
        #expect(report.inexactMatches == 1)
        #expect(report.hasUsableSample)
    }

    @Test("Evaluation distinguishes missing and malformed references")
    func evaluatorSkipReasons() {
        let report = G2PEvaluator().evaluate(
            words: ["", "missing", "bad", "cat"],
            reference: { word in
                ["bad": "XX", "cat": "K AE1 T"][word]
            },
            phonemizer: Phonemizer())
        #expect(report.wordCount == 1)
        #expect(report.missingReferences == 2)
        #expect(report.invalidReferences == 1)
        #expect(report.skippedWords == 3)
    }

    @Test("Zero requested sample size returns no words")
    func zeroSample() {
        #expect(G2PEvaluator.sampleWords(from: BuiltInLexicon(), count: 0).isEmpty)
    }

    @Test("Negative requested sample size returns no words")
    func negativeSample() {
        #expect(G2PEvaluator.sampleWords(from: BuiltInLexicon(), count: -5).isEmpty)
    }

    @Test("Deterministic sampling returns the requested unique count")
    func deterministicSample() {
        let lexicon = BuiltInLexicon()
        let first = G2PEvaluator.sampleWords(from: lexicon, count: 25)
        let second = G2PEvaluator.sampleWords(from: lexicon, count: 25)
        #expect(first == second)
        #expect(first.count == 25)
        #expect(Set(first).count == 25)
    }
}
