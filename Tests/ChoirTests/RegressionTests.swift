import Testing
@testable import Choir

/// Regression coverage for defects fixed between v1.0.0 and v0.2.0.
///
/// Every bug below shipped in a release whose suite reported success, so each
/// test here names the specific failure it guards against rather than testing
/// the feature generically.

@Suite("Regression: number expansion")
struct NumberExpansionRegressionTests {
    let normalizer = TextNormalizer()

    /// numberWords held only 0...19 and no tens table existed, so any value in
    /// 20...99 indexed past the end of the array and trapped. Every number test
    /// in the suite used a single digit, so nothing caught it.
    @Test("Every value in 0...200 expands without trapping")
    func testNoTrapAcrossRange() {
        for n in 0...200 {
            let result = normalizer.normalize("value \(n) end")
            let hasDigits = result.contains { $0.isNumber }
            #expect(!result.isEmpty)
            #expect(!hasDigits, "digits survived for \(n): \(result)")
        }
    }

    @Test("Exact tens read as single words")
    func testExactTens() {
        let expected: [(Int, String)] = [
            (20, "twenty"), (30, "thirty"), (40, "forty"), (50, "fifty"),
            (60, "sixty"), (70, "seventy"), (80, "eighty"), (90, "ninety"),
        ]
        for (value, word) in expected {
            #expect(normalizer.normalize("\(value)") == word)
        }
    }

    @Test("Compound tens combine tens and units")
    func testCompoundTens() {
        #expect(normalizer.normalize("42") == "forty two")
        #expect(normalizer.normalize("99") == "ninety nine")
        #expect(normalizer.normalize("21") == "twenty one")
    }

    @Test("Teens are not treated as compounds")
    func testTeensUnaffected() {
        #expect(normalizer.normalize("13") == "thirteen")
        #expect(normalizer.normalize("19") == "nineteen")
    }

    @Test("Scale words apply above one hundred")
    func testScaleWords() {
        #expect(normalizer.normalize("100").contains("hundred"))
        #expect(normalizer.normalize("1000").contains("thousand"))
        #expect(normalizer.normalize("1000000").contains("million"))
    }

    /// scaleWords was an inferred [(Int, String)] holding a one-trillion
    /// literal. Int is 32-bit on watchOS (arm64_32), so the module never
    /// type-checked there. Parsing with Int rather than Int64 also meant
    /// values above Int32.max silently passed through as raw digits.
    @Test("Values beyond Int32.max still expand")
    func testBeyondInt32Max() {
        let billions = normalizer.normalize("3000000000")  // > 2_147_483_647
        let billionsHasDigits = billions.contains { $0.isNumber }
        #expect(billions.contains("billion"))
        #expect(!billionsHasDigits)

        let trillions = normalizer.normalize("1000000000000")
        let trillionsHasDigits = trillions.contains { $0.isNumber }
        #expect(trillions.contains("trillion"))
        #expect(!trillionsHasDigits)
    }
}

@Suite("Regression: currency")
struct CurrencyRegressionTests {
    let normalizer = TextNormalizer()

    /// expandNumbers ran before expandCurrency, so "$50" became "$fifty" and
    /// the currency pattern could no longer match, leaving the sigil behind.
    @Test("Dollar amounts expand and drop the sigil")
    func testDollarExpansion() {
        let result = normalizer.normalize("It costs $50")
        #expect(result.contains("fifty"))
        #expect(result.contains("dollars"))
        #expect(!result.contains("$"))
    }

    @Test("Multiple amounts in one string all expand")
    func testMultipleAmounts() {
        let result = normalizer.normalize("$5 or $80")
        #expect(!result.contains("$"))
        #expect(result.contains("five"))
        #expect(result.contains("eighty"))
    }
}

@Suite("Regression: audio filters")
struct AudioFilterRegressionTests {
    let filters = AudioFilters()

    /// reverb built `delaySamples..<samples.count` unguarded. The delay line is
    /// 2400 samples (50 ms at 48 kHz), so every shorter buffer produced a range
    /// with lowerBound > upperBound and trapped.
    @Test("Reverb tolerates buffers shorter than its delay line")
    func testReverbShortBuffer() {
        for count in [0, 1, 100, 2399, 2400, 2401] {
            let samples = Array(repeating: Int16(1000), count: count)
            let output = filters.reverb(samples)
            #expect(output.count == count, "reverb changed length at \(count)")
        }
    }

    /// Five filter sites narrowed to Int16 *before* clamping. Int16(_:)
    /// requires its argument already in range, so the "clipping protection"
    /// trapped on exactly the out-of-range values it existed to guard against.
    @Test("Normalize clamps instead of trapping on large gain")
    func testNormalizeClampsExtremeGain() {
        // A mostly-quiet buffer with one loud spike: RMS is low, so the
        // computed gain is large and the spike scales far beyond Int16.
        var samples = Array(repeating: Int16(1), count: 999)
        samples.append(1000)

        let output = filters.normalize(samples, targetLevel: 0.0)
        #expect(output.count == samples.count)
        // Int16 cannot exceed these by construction; the point is that we
        // reach this line at all rather than trapping during conversion.
        #expect(output.allSatisfy { $0 >= -32768 && $0 <= 32767 })
    }

    @Test("Filters tolerate full-scale input without trapping")
    func testFiltersAtFullScale() {
        let loud: [Int16] = [32767, -32768, 32767, -32768, 0, 32767]
        #expect(filters.normalize(loud).count == loud.count)
        #expect(filters.deEsser(loud).count == loud.count)
        #expect(filters.compress(loud).count == loud.count)
        #expect(filters.highPassFilter(loud).count == loud.count)
        #expect(filters.lowPassFilter(loud).count == loud.count)
    }
}

@Suite("Regression: ToBI pitch accents")
struct ToBIRegressionTests {
    let predictor = ToBIPredictor()

    private func contour(_ accent: ToBI.PitchAccent) -> [Double] {
        let tobi = ToBI(pitchAccent: accent)
        return [0.0, 0.25, 0.5, 0.75, 1.0].map {
            predictor.applyToBIToF0(baseF0: 120, tobi: tobi, position: $0)
        }
    }

    /// L_H computed `f0 -= 15 + (30 * position)`, which Swift parses as
    /// `f0 - (15 + 30*position)`. F0 fell from 105 Hz to 75 Hz across the
    /// syllable for an accent whose own comment reads "Rising accent".
    @Test("L+H* rises across the syllable")
    func testRisingAccentRises() {
        let f0 = contour(.L_H)
        let start = f0[0]
        let end = f0[f0.count - 1]
        #expect(start < end)
        for (a, b) in zip(f0, f0.dropFirst()) {
            #expect(a <= b, "L+H* fell from \(a) to \(b)")
        }
    }

    /// L_H_delayed shared the same inverted arithmetic.
    @Test("L*+H rises once the delay has elapsed")
    func testDelayedRisingAccentRises() {
        let f0 = contour(.L_H_delayed)
        let start = f0[0]
        let end = f0[f0.count - 1]
        #expect(start < end)
    }

    /// H+L* was correct only because `+=` distributes over its subtraction.
    /// Guard it so a future edit to the neighbouring case cannot invert it.
    @Test("H+L* falls across the syllable")
    func testFallingAccentFalls() {
        let f0 = contour(.H_L)
        let start = f0[0]
        let end = f0[f0.count - 1]
        #expect(start > end)
        for (a, b) in zip(f0, f0.dropFirst()) {
            #expect(a >= b, "H+L* rose from \(a) to \(b)")
        }
    }

    @Test("Accent output stays within the documented F0 range")
    func testF0StaysInRange() {
        for accent in [ToBI.PitchAccent.H_star, .L_star, .L_H, .H_L, .L_H_delayed] {
            for value in contour(accent) {
                #expect(value >= 50 && value <= 400)
            }
        }
    }
}
