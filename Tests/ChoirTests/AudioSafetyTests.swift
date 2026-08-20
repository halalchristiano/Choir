import Testing
import Foundation
@testable import Choir

/// Full-scale and degenerate audio input.
///
/// Two narrowing rules govern this package's audio path, and both trap when
/// broken rather than producing a wrong number:
///
///   - `abs(Int16.min)` overflows, because the magnitude of -32768 is 32768 and
///     that is not representable as an `Int16`. -32768 is an ordinary
///     full-scale PCM sample, not a corner case.
///   - `Int16(_:)` requires its argument to already be in range, so NaN,
///     infinity, and out-of-range values have to be clamped *before* the
///     conversion, never after.
///
/// The rest of the suite exercises the filters with mid-range positive samples,
/// which is why these paths stayed broken. Everything below is reachable from
/// the public API, most of it through `AudioEffectChain`.
@Suite("Full-scale and degenerate audio input")
struct AudioSafetyTests {
    let filters = AudioFilters()

    /// A buffer holding both PCM extremes, including the asymmetric minimum.
    static let fullScale: [Int16] = [.min, .max, .min, 0, .max, -1, 1, .min]

    // MARK: - Full-scale samples

    @Test("Soft clip shapes full-scale samples without trapping")
    func testSoftClipFullScale() {
        let clipped = filters.softClip(Self.fullScale, threshold: 0.9)

        #expect(clipped.count == Self.fullScale.count)
        // Everything past the knee is pulled strictly inside full scale.
        #expect(clipped.allSatisfy { AudioFilters.magnitude($0) < 32767 })
        // Samples below the knee are untouched.
        #expect(clipped[3] == 0)
        #expect(clipped[5] == -1)
        #expect(clipped[6] == 1)
    }

    @Test("Soft clip is continuous across the knee")
    func testSoftClipHasNoStepAtThreshold() {
        // The knee sits at 0.9 * 32767 = 29490.3, so these two samples straddle it.
        let below = filters.softClip([29490], threshold: 0.9)[0]
        let above = filters.softClip([29491], threshold: 0.9)[0]

        // Shaping the whole sample instead of the overshoot dropped the sample
        // just above the knee by about 6,000, which is audible distortion.
        #expect(abs(Int(above) - Int(below)) <= 2)
    }

    @Test("Compression handles full-scale samples")
    func testCompressFullScale() {
        let compressed = filters.compress(Self.fullScale, threshold: -20, ratio: 4.0)

        #expect(compressed.count == Self.fullScale.count)
        // Above the -20 dB threshold both extremes compress toward it.
        #expect(AudioFilters.magnitude(compressed[0]) < 32767)
        #expect(compressed[0] < 0)  // sign preserved
        #expect(compressed[1] > 0)
    }

    @Test("Filters accept full-scale samples")
    func testFiltersAcceptFullScale() {
        #expect(filters.highPassFilter(Self.fullScale).count == Self.fullScale.count)
        #expect(filters.lowPassFilter(Self.fullScale).count == Self.fullScale.count)
        #expect(filters.normalize(Self.fullScale).count == Self.fullScale.count)
        #expect(filters.deEsser(Self.fullScale).count == Self.fullScale.count)
        #expect(filters.reverb(Self.fullScale).count == Self.fullScale.count)
    }

    @Test("Effect chain presets accept full-scale samples")
    func testEffectChainsAcceptFullScale() {
        let buffer = Array(repeating: Int16.min, count: 5000)

        let chains: [AudioEffectChain] = [
            .standardMastering,
            .podcast,
            .warmth,
            .clean,
            .voiceClarity,
        ]

        for chain in chains {
            #expect(chain.process(buffer).count == buffer.count)
        }
    }

    // MARK: - Out-of-range parameters

    @Test("Soft clip clamps thresholds outside 0...1")
    func testSoftClipOutOfRangeThreshold() {
        // 32767 * 2 does not fit in an Int16.
        #expect(filters.softClip(Self.fullScale, threshold: 2.0).count == Self.fullScale.count)
        #expect(filters.softClip(Self.fullScale, threshold: -1.0).count == Self.fullScale.count)
        #expect(filters.softClip(Self.fullScale, threshold: .nan).count == Self.fullScale.count)

        // A threshold of exactly 1.0 leaves the buffer alone rather than
        // dividing by zero headroom.
        #expect(filters.softClip(Self.fullScale, threshold: 1.0) == Self.fullScale)
    }

    @Test("Compression rejects ratios below 1:1")
    func testCompressOutOfRangeRatio() {
        // A ratio of 0 divides by zero; anything below 1:1 expands past full
        // scale. Both are treated as 1:1, which leaves the buffer where it was
        // (to within the rounding of a round trip through Double).
        for ratio in [0.0, 0.5, -4.0, Double.nan] {
            let compressed = filters.compress(Self.fullScale, threshold: -20, ratio: ratio)

            #expect(compressed.count == Self.fullScale.count)
            #expect(zip(compressed, Self.fullScale).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
        }
    }

    @Test("Filters pass through a non-positive cutoff or sample rate")
    func testNonPositiveRatesArePassThrough() {
        // A zero cutoff makes the RC time constant infinite and alpha NaN.
        #expect(filters.highPassFilter(Self.fullScale, cutoffFrequency: 0) == Self.fullScale)
        #expect(filters.lowPassFilter(Self.fullScale, cutoffFrequency: 0) == Self.fullScale)
        #expect(filters.highPassFilter(Self.fullScale, sampleRate: 0) == Self.fullScale)
        #expect(filters.lowPassFilter(Self.fullScale, sampleRate: -48000) == Self.fullScale)

        // A negative rate gives a negative delay, which reads past the buffer end.
        let buffer = Array(repeating: Int16(1000), count: 5000)
        #expect(filters.reverb(buffer, sampleRate: -48000) == buffer)
    }

    @Test("Reverb clamps wet level outside 0...1")
    func testReverbOutOfRangeWetLevel() {
        let buffer = Array(repeating: Int16(1000), count: 5000)

        #expect(filters.reverb(buffer, wetLevel: 5.0).count == buffer.count)
        #expect(filters.reverb(buffer, wetLevel: -3.0).count == buffer.count)
        #expect(filters.reverb(buffer, wetLevel: .nan).count == buffer.count)
    }

    // MARK: - Empty buffers

    @Test("Every filter accepts an empty buffer")
    func testEmptyBuffers() {
        let empty: [Int16] = []

        #expect(filters.highPassFilter(empty).isEmpty)
        #expect(filters.lowPassFilter(empty).isEmpty)
        #expect(filters.normalize(empty).isEmpty)
        #expect(filters.softClip(empty).isEmpty)
        #expect(filters.compress(empty).isEmpty)
        #expect(filters.deEsser(empty).isEmpty)
        #expect(filters.reverb(empty).isEmpty)
    }

    // MARK: - Quality analysis

    @Test("Quality analysis handles a full-scale negative peak")
    func testQualityAnalysisFullScale() {
        let analyzer = VoiceQualityAnalyzer()

        let metrics = analyzer.analyzeQuality(Self.fullScale, sampleRate: 48000)

        // The loudest excursion is negative, so the reported peak is too.
        #expect(metrics.peakLevel == Int16.min)
        #expect(metrics.dynamicRange.isFinite)
        #expect(metrics.snrEstimate.isFinite)
        #expect(metrics.clippingPercent > 0)
    }

    @Test("Quality report never prints nan for a negative peak")
    func testQualityReportNegativePeak() {
        let analyzer = VoiceQualityAnalyzer()

        let report = analyzer.generateReport(Self.fullScale, sampleRate: 48000)

        // `log10` of a negative peak is NaN, which reached the summary as "nan".
        #expect(report.peakDbFS.isFinite)
        #expect(abs(report.peakDbFS) < 1.0)  // full scale is 0 dBFS
        #expect(!report.summary.lowercased().contains("nan"))
        #expect(!report.summary.lowercased().contains("inf"))
    }

    @Test("Quality analysis handles digital silence")
    func testQualityAnalysisSilence() {
        let analyzer = VoiceQualityAnalyzer()

        let metrics = analyzer.analyzeQuality(Array(repeating: 0, count: 100), sampleRate: 48000)

        // A zero peak used to give log10(0), i.e. -inf dynamic range.
        #expect(metrics.dynamicRange.isFinite)
        #expect(metrics.peakLevel == 0)
    }

    @Test("Quality analysis handles a zero sample rate")
    func testQualityAnalysisZeroSampleRate() {
        let analyzer = VoiceQualityAnalyzer()

        let metrics = analyzer.analyzeQuality(Self.fullScale, sampleRate: 0)

        // Zero duration made the zero-crossing rate 0/0.
        #expect(metrics.zeroCrossingRate.isFinite)
    }

    // MARK: - Sample-based synthesis

    @Test("Sample-based normalization handles a full-scale negative sample")
    func testSampleSynthesizerFullScale() async throws {
        let library = VoiceSampleLibrary(voiceName: "test")
        await library.addSample(
            PhonemeSample(phoneme: "a", audioData: [.min, .max, .min, 0])
        )
        let synthesizer = SampleBasedSynthesizer(library: library)

        let output = try await synthesizer.synthesize(phonemes: [Phoneme("a")])

        #expect(output.count == 4)
        // Normalization targets 95% of full scale, leaving headroom.
        let peak = output.map(AudioFilters.magnitude).max() ?? 0
        #expect(peak > 30_000)
        #expect(peak < 32767)
    }
}
