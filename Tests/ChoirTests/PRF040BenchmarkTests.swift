import Foundation
import Testing
@testable import Choir

/// SRS PRF-040 (MUST) — the benchmark harness.
///
/// "A reproducible benchmark harness (part of the repo) shall measure every PRF
/// number on every reference device per release; releases ship with the
/// benchmark report."
@Suite("SRS PRF-040 — benchmark harness")
struct BenchmarkHarnessTests {

    @Test("PRF-040: the five reference devices of §28.1 are modelled")
    func testReferenceDevices() {
        #expect(ReferenceDevice.allCases.count == 5)
        #expect(ReferenceDevice(rawValue: "R1") == .r1iPhone13)
        #expect(ReferenceDevice(rawValue: "R4") == .r4AppleWatch)
    }

    /// The targets are transcribed from §28 and are the point of the harness,
    /// so they are pinned.
    @Test("PRF-001/010/011/020: targets match the specification")
    func testTargets() {
        #expect(ReferenceDevice.r1iPhone13.batchRTFTarget == 0.35)
        #expect(ReferenceDevice.r3MacBook.batchRTFTarget == 0.15)

        #expect(ReferenceDevice.r1iPhone13.streamingTTFATargetMs == 350)
        #expect(ReferenceDevice.r2iPhonePro.streamingTTFATargetMs == 250)
        #expect(ReferenceDevice.r3MacBook.streamingTTFATargetMs == 250)
        #expect(ReferenceDevice.r5VisionPro.streamingTTFATargetMs == 250)

        #expect(ReferenceDevice.r1iPhone13.coldStartTargetSeconds == 3.0)
        #expect(ReferenceDevice.r3MacBook.coldStartTargetSeconds == 1.5)

        #expect(ReferenceDevice.r1iPhone13.peakMemoryTargetMB == 350)
        #expect(ReferenceDevice.r4AppleWatch.peakMemoryTargetMB == 180)

        #expect(ReferenceDevice.r1iPhone13.sustainedStreamingRTFTarget == 0.5)
    }

    /// PRF-030 sets 400 MB installed; PRF-032 sets 60 MB for watchOS.
    @Test("PRF-030/032: asset budgets")
    func testAssetBudgets() {
        #expect(ReferenceDevice.r1iPhone13.assetBudgetMB == 400)
        #expect(ReferenceDevice.r4AppleWatch.assetBudgetMB == 60)
        #expect(ReferenceDevice.r1iPhone13.assetTargetMB == 250)
    }

    /// A device the specification sets no target for must report "no target"
    /// rather than passing by default.
    @Test("PRF-040: an absent target is not a pass")
    func testAbsentTargetIsNotPass() {
        #expect(ReferenceDevice.r2iPhonePro.batchRTFTarget == nil)

        let untargeted = BenchmarkMeasurement(
            requirement: "PRF-001", name: "Batch RTF", value: 99, unit: "RTF", target: nil)
        #expect(untargeted.meetsTarget == nil)
        #expect(untargeted.statusText == "no target")
    }

    @Test("PRF-040: measurements are judged against their target")
    func testMeasurementJudgement() {
        let pass = BenchmarkMeasurement(
            requirement: "PRF-001", name: "RTF", value: 0.10, unit: "RTF", target: 0.15)
        let fail = BenchmarkMeasurement(
            requirement: "PRF-001", name: "RTF", value: 0.20, unit: "RTF", target: 0.15)
        let boundary = BenchmarkMeasurement(
            requirement: "PRF-001", name: "RTF", value: 0.15, unit: "RTF", target: 0.15)

        #expect(pass.meetsTarget == true)
        #expect(fail.meetsTarget == false)
        // The requirement reads "≤", so the boundary passes.
        #expect(boundary.meetsTarget == true)
    }

    @Test("PRF-030: the shipped asset size is measurable and within budget")
    func testAssetSize() {
        let mb = BenchmarkHarness.measureAssetSizeMB()
        #expect(mb > 0, "no shipped assets found; the lexicon should be present")
        #expect(mb < ReferenceDevice.r1iPhone13.assetBudgetMB,
                "assets are \(mb) MB against a 400 MB budget")
    }

    @Test("PRF-020: resident memory is readable")
    func testResidentMemory() {
        let bytes = BenchmarkHarness.residentBytes()
        #expect(bytes != nil, "could not read resident memory")
        #expect((bytes ?? 0) > 0)
    }

    /// The harness must produce a complete report, including the things it
    /// cannot measure — a silent omission would read as a pass.
    @Test("PRF-040: a run produces a complete report")
    func testRunProducesReport() async {
        let report = await BenchmarkHarness(iterations: 1).run(voice: .isla, device: .r3MacBook)

        #expect(report.device == .r3MacBook)
        #expect(report.packageVersion == Choir.version)
        #expect(!report.hostDescription.isEmpty)

        let requirements = Set(report.measurements.map(\.requirement))
        for expected in ["PRF-001", "PRF-010", "PRF-011", "PRF-020", "PRF-030"] {
            #expect(requirements.contains(expected), "missing \(expected)")
        }

        // PRF-021 and the other-device runs cannot be taken here and must be
        // declared rather than omitted.
        #expect(!report.notMeasured.isEmpty)
        #expect(report.notMeasured.contains { $0.contains("PRF-021") })
    }

    /// A synthetic report. Rendering and encoding do not depend on real
    /// measurement, and running the whole harness to test them made the suite
    /// spend forty seconds re-measuring what it had already measured.
    private func sampleReport(debug: Bool = false) -> BenchmarkReport {
        BenchmarkReport(
            device: .r3MacBook,
            hostDescription: "test host",
            packageVersion: Choir.version,
            measurements: [
                BenchmarkMeasurement(
                    requirement: "PRF-001", name: "Batch RTF",
                    value: 0.04, unit: "RTF", target: 0.15,
                    samples: 9, minimum: 0.03, maximum: 0.06),
            ],
            notMeasured: ["PRF-021 battery: requires a physical device."],
            isDebugBuild: debug)
    }

    @Test("PRF-040: the report renders as Markdown for shipping")
    func testMarkdownReport() {
        let markdown = sampleReport().markdown()

        #expect(markdown.contains("# CHOIR Benchmark Report"))
        #expect(markdown.contains("PRF-001"))
        #expect(markdown.contains("Not measured by this harness"))
        #expect(markdown.contains(Choir.version))
    }

    /// An unoptimized build must announce itself in the report; a debug
    /// number that reads as a measurement is worse than no number.
    @Test("PRF-040: a debug build is declared in the report")
    func testDebugBuildDeclared() {
        #expect(sampleReport(debug: true).markdown().contains("unoptimized build"))
        #expect(!sampleReport(debug: false).markdown().contains("unoptimized build"))
    }

    @Test("PRF-040: the report round-trips as JSON")
    func testReportCodable() throws {
        let report = sampleReport()
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(BenchmarkReport.self, from: data)
        #expect(decoded == report)
    }

    /// The version constant is printed into every report, so a stale value
    /// misattributes the measurements. It had drifted to 0.1.0 across eleven
    /// releases before the harness surfaced it.
    @Test("The package version is a plausible semantic version")
    func testVersionIsSemver() {
        let parts = Choir.version.split(separator: ".")
        #expect(parts.count == 3, "version '\(Choir.version)' is not major.minor.patch")
        #expect(parts.allSatisfy { Int($0) != nil }, "version '\(Choir.version)' has non-numeric parts")
        #expect(Choir.version != "0.1.0", "version constant has drifted behind the released tag")
    }
}
