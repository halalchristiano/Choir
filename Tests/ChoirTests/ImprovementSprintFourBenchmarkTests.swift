import Foundation
import Testing
@testable import Choir

@Suite("Fourth improvement sprint: benchmark measurements")
struct BenchmarkMeasurementSprintFourTests {
    private func measurement(
        value: Double = 1,
        target: Double? = 2,
        lowerIsBetter: Bool = true,
        samples: Int = 1,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) -> BenchmarkMeasurement {
        BenchmarkMeasurement(
            requirement: "PRF-001",
            name: "Batch RTF",
            value: value,
            unit: "RTF",
            target: target,
            lowerIsBetter: lowerIsBetter,
            samples: samples,
            minimum: minimum,
            maximum: maximum)
    }

    @Test("Judgements distinguish pass, fail, no target, and invalid evidence")
    func typedJudgements() {
        #expect(measurement().judgement == .passed)
        #expect(measurement(value: 3).judgement == .failed)
        #expect(measurement(target: nil).judgement == .untargeted)
        #expect(measurement(samples: 0).judgement == .invalid)
        #expect(measurement(samples: 0).statusText == "INVALID")
    }

    @Test("Negative successful-sample counts clamp to zero")
    func sampleCountClamps() {
        #expect(measurement(samples: -4).samples == 0)
    }

    @Test("Non-finite range endpoints are discarded")
    func nonFiniteBoundsAreDiscarded() {
        let value = measurement(minimum: .nan, maximum: .infinity)
        #expect(value.minimum == nil)
        #expect(value.maximum == nil)
    }

    @Test("Reversed sample ranges are ordered")
    func reversedRangeIsOrdered() {
        let value = measurement(value: 2, samples: 3, minimum: 3, maximum: 1)
        #expect(value.minimum == 1)
        #expect(value.maximum == 3)
        #expect(value.isValid)
    }

    @Test("Measurement validation rejects empty metadata and incoherent ranges")
    func structuralValidation() {
        let blankName = BenchmarkMeasurement(
            requirement: "PRF-001", name: "  ", value: 1, unit: "s")
        let oneSidedRange = measurement(value: 2, samples: 3, minimum: 1)
        let summaryOutsideRange = measurement(
            value: 4, samples: 3, minimum: 1, maximum: 3)
        #expect(!blankName.isValid)
        #expect(!oneSidedRange.isValid)
        #expect(!summaryOutsideRange.isValid)
    }

    @Test("Non-finite summaries and targets cannot pass")
    func nonFiniteValuesAreInvalid() {
        let infiniteValue = measurement(value: -.infinity)
        let nanTarget = measurement(target: .nan)
        #expect(infiniteValue.judgement == .invalid)
        #expect(infiniteValue.meetsTarget == false)
        #expect(nanTarget.judgement == .invalid)
        #expect(nanTarget.meetsTarget == false)
    }

    @Test("Target margin has one pass-positive convention in both directions")
    func targetMargin() {
        #expect(measurement(value: 1.5, target: 2).targetMargin == 0.5)
        #expect(measurement(value: 2.5, target: 2).targetMargin == -0.5)
        #expect(measurement(value: 3, target: 2, lowerIsBetter: false).targetMargin == 1)
        #expect(measurement(target: nil).targetMargin == nil)
    }
}

@Suite("Fourth improvement sprint: benchmark reports")
struct BenchmarkReportSprintFourTests {
    private func measurement(
        requirement: String = "PRF-001",
        name: String = "Batch RTF",
        value: Double = 1,
        target: Double? = 2,
        samples: Int = 1,
        caveat: String? = nil
    ) -> BenchmarkMeasurement {
        BenchmarkMeasurement(
            requirement: requirement,
            name: name,
            value: value,
            unit: "ms",
            target: target,
            caveat: caveat,
            samples: samples)
    }

    private func report(
        _ measurements: [BenchmarkMeasurement],
        hostDescription: String = "test host",
        packageVersion: String = "1.2.3",
        notMeasured: [String] = []
    ) -> BenchmarkReport {
        BenchmarkReport(
            device: .r3MacBook,
            hostDescription: hostDescription,
            packageVersion: packageVersion,
            measurements: measurements,
            notMeasured: notMeasured,
            isDebugBuild: false)
    }

    @Test("Reports expose passed measurements")
    func passedMeasurements() {
        let value = report([measurement(), measurement(value: 3)])
        #expect(value.passedMeasurements.map(\.value) == [1])
    }

    @Test("Failures exclude invalid evidence")
    func failuresExcludeInvalidEvidence() {
        let value = report([
            measurement(value: 3),
            measurement(value: 1, target: .nan),
        ])
        #expect(value.failures.map(\.value) == [3])
    }

    @Test("Reports expose valid untargeted measurements")
    func untargetedMeasurements() {
        let value = report([
            measurement(target: nil),
            measurement(target: nil, samples: 0),
        ])
        #expect(value.untargetedMeasurements.count == 1)
        #expect(value.untargetedMeasurements.first?.value == 1)
    }

    @Test("Reports expose invalid measurements separately")
    func invalidMeasurements() {
        let value = report([measurement(), measurement(samples: 0)])
        #expect(value.invalidMeasurements.count == 1)
        #expect(value.invalidMeasurements.first?.statusText == "INVALID")
    }

    @Test("Target pass rate excludes untargeted and invalid evidence")
    func targetPassRate() {
        let value = report([
            measurement(),
            measurement(value: 1.5),
            measurement(value: 3),
            measurement(target: nil),
            measurement(samples: 0),
        ])
        #expect(value.targetPassRate == 2.0 / 3.0)
        #expect(report([measurement(target: nil)]).targetPassRate == nil)
    }

    @Test("All-targets-met requires measured, valid passing targets")
    func allTargetsMetIsNotVacuous() {
        #expect(!report([]).allTargetsMet)
        #expect(!report([measurement(target: nil)]).allTargetsMet)
        #expect(report([measurement(), measurement(target: nil)]).allTargetsMet)
        #expect(!report([measurement(), measurement(samples: 0)]).allTargetsMet)
    }

    @Test("Requirement lookup is trimmed and case-insensitive")
    func normalizedRequirementLookup() {
        let value = report([
            measurement(requirement: "PRF-001"),
            measurement(requirement: "PRF-010"),
        ])
        #expect(value.measurements(forRequirement: "  prf-001\n").count == 1)
        #expect(value.measurements(forRequirement: "   ").isEmpty)
    }

    @Test("Report measurement ordering is deterministic and stable")
    func deterministicMeasurementOrdering() {
        let value = report([
            measurement(requirement: "PRF-010", name: "Zulu", value: 4),
            measurement(requirement: "PRF-001", name: "Batch", value: 1),
            measurement(requirement: "prf-010", name: "Alpha", value: 2),
            measurement(requirement: "PRF-010", name: "alpha", value: 3),
        ])
        #expect(value.measurementsSortedByRequirement.map(\.value) == [1, 2, 3, 4])
        let markdown = value.markdown()
        let batchRange = markdown.range(of: "Batch")
        let zuluRange = markdown.range(of: "Zulu")
        #expect(batchRange != nil)
        #expect(zuluRange != nil)
        if let batchRange, let zuluRange {
            #expect(batchRange.lowerBound < zuluRange.lowerBound)
        }
    }

    @Test("Markdown numbers always use a decimal point and fixed precision")
    func fixedLocaleNumberFormatting() {
        let markdown = report([measurement(value: 1.5, target: 2.25)]).markdown()
        #expect(markdown.contains("1.50 ms"))
        #expect(markdown.contains("2.25 ms"))
    }

    @Test("Markdown escapes and folds caller-provided fields")
    func markdownEscaping() {
        let unsafe = BenchmarkMeasurement(
            requirement: "PRF|001",
            name: "name|cell\nrow",
            value: 1,
            unit: "m*s",
            target: 2,
            caveat: "look [here]\nnext")
        let markdown = report(
            [unsafe],
            hostDescription: "host|pipe\nnext",
            packageVersion: "1|2\nnext",
            notMeasured: ["missing|item\nnext"]).markdown()
        #expect(markdown.contains("host\\|pipe next"))
        #expect(markdown.contains("name\\|cell row"))
        #expect(markdown.contains("m\\*s"))
        #expect(markdown.contains("look \\[here\\] next"))
        #expect(markdown.contains("missing\\|item next"))
        #expect(!markdown.contains("pipe\nnext"))
    }

    @Test("Markdown reports a categorical result summary")
    func markdownResultSummary() {
        let markdown = report([
            measurement(),
            measurement(value: 3),
            measurement(target: nil),
            measurement(samples: 0),
        ]).markdown()
        #expect(markdown.contains(
            "**Results:** 1 passed; 1 failed; 1 no target; 1 invalid"))
    }
}

@Suite("Fourth improvement sprint: benchmark statistics")
struct BenchmarkStatisticsSprintFourTests {
    @Test("Median ignores non-finite samples")
    func medianIgnoresNonFiniteSamples() {
        #expect(BenchmarkHarness.median([.nan, 1, .infinity, 3]) == 2)
        #expect(BenchmarkHarness.median([.nan, .infinity]) == 0)
    }

    @Test("Even medians cannot overflow while averaging")
    func medianAvoidsOverflow() {
        let greatest = Double.greatestFiniteMagnitude
        #expect(BenchmarkHarness.median([greatest, greatest]) == greatest)
        #expect(BenchmarkHarness.median([-greatest, greatest]) == 0)
    }

    @Test("Percentiles interpolate finite sorted samples")
    func percentiles() {
        let values = [30.0, .nan, 0, 20, 10]
        #expect(BenchmarkHarness.percentile(0, of: values) == 0)
        #expect(BenchmarkHarness.percentile(0.25, of: values) == 7.5)
        #expect(BenchmarkHarness.percentile(1, of: values) == 30)
        #expect(BenchmarkHarness.percentile(-0.1, of: values) == nil)
        #expect(BenchmarkHarness.percentile(.nan, of: values) == nil)
    }

    @Test("Sample standard deviation is stable and finite-only")
    func sampleStandardDeviation() {
        let result = BenchmarkHarness.sampleStandardDeviation(
            [2, 4, 4, .nan, 4, 5, 5, 7, 9])
        #expect(abs((result ?? 0) - sqrt(32.0 / 7.0)) < 0.000_000_001)
        #expect(BenchmarkHarness.sampleStandardDeviation([1, .infinity]) == nil)
    }
}

@Suite("Fourth improvement sprint: reference devices")
struct ReferenceDeviceSprintFourTests {
    @Test("Reference identifiers accept trimmed IDs and display names")
    func normalizedIdentifierParsing() {
        #expect(ReferenceDevice(identifier: " r1\n") == .r1iPhone13)
        #expect(ReferenceDevice(identifier: "iphone 13 (a15)") == .r1iPhone13)
        #expect(ReferenceDevice(identifier: "APPLE VISION PRO") == .r5VisionPro)
        #expect(ReferenceDevice(identifier: "unknown") == nil)
        #expect(ReferenceDevice(identifier: "   ") == nil)
    }
}

@Suite("Fourth improvement sprint: Harvard corpus selection")
struct HarvardSentenceSprintFourTests {
    @Test("Published Harvard lists have safe one-based lookup")
    func safeListLookup() {
        #expect(HarvardSentences.list(number: 1) == HarvardSentences.list1)
        #expect(HarvardSentences.list(number: 2) == HarvardSentences.list2)
        #expect(HarvardSentences.list(number: 0) == nil)
        #expect(HarvardSentences.list(number: 3) == nil)
        #expect(HarvardSentences.list(number: Int.min) == nil)
    }

    @Test("Seeded Harvard selection is deterministic, unique, balanced, and bounded")
    func deterministicSelection() {
        let first = HarvardSentences.deterministicSelection(count: 7, seed: 42)
        let repeated = HarvardSentences.deterministicSelection(count: 7, seed: 42)
        let otherSeed = HarvardSentences.deterministicSelection(count: 7, seed: 43)
        #expect(first == repeated)
        #expect(first != otherSeed)
        #expect(first.count == 7)
        #expect(Set(first).count == 7)
        #expect(first.allSatisfy { HarvardSentences.standard.contains($0) })

        let list1 = Set(HarvardSentences.list1)
        let list1Count = first.filter { list1.contains($0) }.count
        #expect(abs(list1Count - (first.count - list1Count)) <= 1)
        #expect(HarvardSentences.deterministicSelection(count: -1).isEmpty)
        #expect(HarvardSentences.deterministicSelection(count: Int.max).count
            == HarvardSentences.standard.count)
    }
}
