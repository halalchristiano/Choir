import Foundation

/// The outcome of judging one benchmark measurement.
public enum BenchmarkJudgement: String, Sendable, Equatable, Codable {
    case passed
    case failed
    case untargeted
    case invalid

    public var statusText: String {
        switch self {
        case .passed: return "PASS"
        case .failed: return "FAIL"
        case .untargeted: return "no target"
        case .invalid: return "INVALID"
        }
    }
}

/// One measured performance number, judged against its requirement.
public struct BenchmarkMeasurement: Sendable, Equatable, Codable {
    /// The requirement this measures, e.g. `"PRF-001"`.
    public let requirement: String

    /// What was measured, e.g. `"Batch RTF"`.
    public let name: String

    /// The measured value.
    public let value: Double

    /// Unit, e.g. `"RTF"`, `"ms"`, `"MB"`.
    public let unit: String

    /// The target for this device, or `nil` when the specification sets none.
    public let target: Double?

    /// Whether lower values are better. All current PRF targets are ceilings.
    public let lowerIsBetter: Bool

    /// Why the measurement should not be read at face value, if applicable.
    public let caveat: String?

    /// How many timed samples the value summarizes.
    public let samples: Int

    /// Smallest and largest sample, so the reader can see the noise.
    ///
    /// A single figure hides whether a result sits comfortably inside its
    /// target or straddles it, and latency measurements on a shared machine
    /// routinely straddle.
    public let minimum: Double?
    public let maximum: Double?

    public init(
        requirement: String,
        name: String,
        value: Double,
        unit: String,
        target: Double? = nil,
        lowerIsBetter: Bool = true,
        caveat: String? = nil,
        samples: Int = 1,
        minimum: Double? = nil,
        maximum: Double? = nil
    ) {
        self.samples = max(0, samples)
        let finiteMinimum = minimum.flatMap { $0.isFinite ? $0 : nil }
        let finiteMaximum = maximum.flatMap { $0.isFinite ? $0 : nil }
        if let finiteMinimum, let finiteMaximum, finiteMinimum > finiteMaximum {
            self.minimum = finiteMaximum
            self.maximum = finiteMinimum
        } else {
            self.minimum = finiteMinimum
            self.maximum = finiteMaximum
        }
        self.requirement = requirement
        self.name = name
        self.value = value
        self.unit = unit
        self.target = target
        self.lowerIsBetter = lowerIsBetter
        self.caveat = caveat
    }

    /// Whether the value, target, and optional range are usable evidence.
    ///
    /// Empty labels, zero successful samples, half-present ranges, and ranges
    /// that do not contain their summary are all malformed measurements. The
    /// benchmark report keeps them visible, but never lets them pass a target.
    public var isValid: Bool {
        guard !requirement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              samples > 0,
              value.isFinite,
              target?.isFinite != false
        else { return false }

        switch (minimum, maximum) {
        case (nil, nil):
            return true
        case let (minimum?, maximum?):
            return minimum.isFinite && maximum.isFinite
                && minimum <= maximum && minimum <= value && value <= maximum
        default:
            return false
        }
    }

    /// A typed result that distinguishes missing targets from invalid data.
    public var judgement: BenchmarkJudgement {
        guard isValid else { return .invalid }
        guard let target else { return .untargeted }
        let passed = lowerIsBetter ? value <= target : value >= target
        return passed ? .passed : .failed
    }

    /// Whether the measurement meets its target.
    ///
    /// `nil` when there is no target for this device — untargeted is not the
    /// same as passing.
    public var meetsTarget: Bool? {
        switch judgement {
        case .passed: return true
        case .failed: return false
        case .untargeted: return nil
        case .invalid: return target == nil ? nil : false
        }
    }

    /// Signed distance from the target; non-negative means the target is met.
    public var targetMargin: Double? {
        guard isValid, let target else { return nil }
        return lowerIsBetter ? target - value : value - target
    }

    public var statusText: String { judgement.statusText }
}

/// A complete benchmark run (SRS PRF-040).
public struct BenchmarkReport: Sendable, Equatable, Codable {
    /// The device the run was attributed to, if it is a reference device.
    public let device: ReferenceDevice?

    /// Free-form description of the host, for runs off a reference device.
    public let hostDescription: String

    /// Package version the run measured.
    public let packageVersion: String

    public let measurements: [BenchmarkMeasurement]

    /// Measurements the harness could not take, and why.
    public let notMeasured: [String]

    /// Whether the measured binary was built without optimization.
    ///
    /// A debug build is not a slower release build, it is a different program.
    /// The first run of this harness reported lexicon load at 0.97 s in debug
    /// against 0.45 s in release, and a hand-written byte loop measured four
    /// times *slower* than the stdlib call it replaced — purely because
    /// bounds checks and unspecialized generics were still in. Every PRF figure
    /// from a debug build is meaningless, so the report says so rather than
    /// letting a reader assume otherwise.
    public let isDebugBuild: Bool

    public init(
        device: ReferenceDevice?,
        hostDescription: String,
        packageVersion: String,
        measurements: [BenchmarkMeasurement],
        notMeasured: [String] = [],
        isDebugBuild: Bool = BenchmarkReport.builtWithoutOptimization
    ) {
        self.isDebugBuild = isDebugBuild
        self.device = device
        self.hostDescription = hostDescription
        self.packageVersion = packageVersion
        self.measurements = measurements
        self.notMeasured = notMeasured
    }

    /// Whether this binary was compiled without optimization.
    public static var builtWithoutOptimization: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// Measurements that failed their target.
    public var failures: [BenchmarkMeasurement] {
        measurements.filter { $0.judgement == .failed }
    }

    /// Measurements that passed their target.
    public var passedMeasurements: [BenchmarkMeasurement] {
        measurements.filter { $0.judgement == .passed }
    }

    /// Valid measurements for which the specification sets no target.
    public var untargetedMeasurements: [BenchmarkMeasurement] {
        measurements.filter { $0.judgement == .untargeted }
    }

    /// Measurements that cannot safely be judged.
    public var invalidMeasurements: [BenchmarkMeasurement] {
        measurements.filter { $0.judgement == .invalid }
    }

    /// The fraction of valid, targeted measurements that passed.
    public var targetPassRate: Double? {
        let judgedCount = passedMeasurements.count + failures.count
        guard judgedCount > 0 else { return nil }
        return Double(passedMeasurements.count) / Double(judgedCount)
    }

    /// Whether at least one target was measured and every such result passed.
    public var allTargetsMet: Bool {
        let targeted = measurements.filter { $0.target != nil }
        return !targeted.isEmpty && targeted.allSatisfy { $0.judgement == .passed }
    }

    /// Finds all measurements for a requirement, ignoring case and padding.
    public func measurements(forRequirement requirement: String) -> [BenchmarkMeasurement] {
        let key = Self.normalizedRequirement(requirement)
        guard !key.isEmpty else { return [] }
        return measurements.filter { Self.normalizedRequirement($0.requirement) == key }
    }

    /// A deterministic view suitable for reports and release-to-release diffs.
    public var measurementsSortedByRequirement: [BenchmarkMeasurement] {
        measurements.enumerated().sorted { lhs, rhs in
            let lhsRequirement = Self.normalizedRequirement(lhs.element.requirement)
            let rhsRequirement = Self.normalizedRequirement(rhs.element.requirement)
            if lhsRequirement != rhsRequirement { return lhsRequirement < rhsRequirement }

            let lhsName = lhs.element.name.lowercased()
            let rhsName = rhs.element.name.lowercased()
            if lhsName != rhsName { return lhsName < rhsName }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }

    /// The report as Markdown, for shipping alongside a release (PRF-040).
    public func markdown() -> String {
        var lines: [String] = []
        lines.append("# CHOIR Benchmark Report")
        lines.append("")
        if isDebugBuild {
            lines.append("> **These numbers are from an unoptimized build and mean nothing.**")
            lines.append("> Re-run with `swift run -c release choir-benchmark`. A debug build is")
            lines.append("> not a slower release build; it is a different program.")
            lines.append("")
        }
        lines.append("- **Package version:** \(Self.markdownText(packageVersion))")
        lines.append("- **Host:** \(Self.markdownText(hostDescription))")
        let deviceDescription = device.map { "\($0.rawValue) — \($0.displayName)" }
            ?? "not a reference device; targets not applied"
        lines.append("- **Reference device:** \(Self.markdownText(deviceDescription))")
        lines.append("- **Results:** \(passedMeasurements.count) passed; \(failures.count) failed; \(untargetedMeasurements.count) no target; \(invalidMeasurements.count) invalid")
        lines.append("")
        lines.append("| Requirement | Measurement | Median | Range | Samples | Target | Status |")
        lines.append("|---|---|---:|---:|---:|---:|---|")
        for m in measurementsSortedByRequirement {
            let requirement = Self.markdownText(m.requirement)
            let name = Self.markdownText(m.name)
            let unit = Self.markdownText(m.unit)
            let target = m.target.map { "\(Self.formattedNumber($0)) \(unit)" } ?? "—"
            let range: String
            if let low = m.minimum, let high = m.maximum, m.samples > 1 {
                range = "\(Self.formattedNumber(low))–\(Self.formattedNumber(high))"
            } else {
                range = "—"
            }
            lines.append("| `\(requirement)` | \(name) | \(Self.formattedNumber(m.value)) \(unit) | \(range) | \(m.samples) | \(target) | \(m.statusText) |")
        }

        let caveats = measurements.compactMap { m in
            m.caveat.map {
                "- **\(Self.markdownText(m.requirement))** \(Self.markdownText(m.name)): \(Self.markdownText($0))"
            }
        }
        if !caveats.isEmpty {
            lines.append("")
            lines.append("## Caveats")
            lines.append("")
            lines.append(contentsOf: caveats)
        }

        if !notMeasured.isEmpty {
            lines.append("")
            lines.append("## Not measured by this harness")
            lines.append("")
            lines.append(contentsOf: notMeasured.map { "- \(Self.markdownText($0))" })
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func normalizedRequirement(_ requirement: String) -> String {
        requirement.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Fixed-locale formatting keeps release diffs independent of host locale.
    private static func formattedNumber(_ value: Double) -> String {
        guard value.isFinite else { return "invalid" }
        return String(
            format: "%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            arguments: [value])
    }

    /// Keeps caller-provided text on one line and out of Markdown structure.
    private static func markdownText(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "`", with: "&#96;")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

/// Measures every PRF number the harness can take (SRS PRF-040).
///
/// "A reproducible benchmark harness (part of the repo) shall measure every PRF
/// number on every reference device per release; releases ship with the
/// benchmark report."
///
/// - Important: the acoustic model is currently a mock, so the throughput
///   numbers describe the pipeline as it stands and not a shipping voice. That
///   is the point of running it now: PRF-040 exists to produce a baseline, and
///   a baseline taken before the model lands is what makes the model's cost
///   measurable when it does.
public struct BenchmarkHarness: Sendable {

    /// Text used for throughput measurement.
    ///
    /// Fixed rather than generated, so runs are comparable across releases.
    public static let standardPassage = """
    The engine converts written language into speech entirely on the device. \
    It expands numbers, dates and abbreviations, resolves pronunciation from a \
    lexicon of more than one hundred thousand words, predicts the rhythm and \
    melody of each phrase, and renders the result as audio. Nothing leaves the \
    machine it runs on.
    """

    public let iterations: Int

    public init(iterations: Int = 5) {
        self.iterations = max(1, iterations)
    }

    /// Runs the benchmark and returns a report.
    public func run(
        voice: Voice = .isla,
        device: ReferenceDevice? = ReferenceDevice.current
    ) async -> BenchmarkReport {
        var measurements: [BenchmarkMeasurement] = []

        let mockCaveat = "Measured against the mock acoustic model and Griffin-Lim vocoder; not representative of a trained model."

        // PRF-011: cold start. Measured first, while nothing is loaded.
        let coldStart = await measureColdStart(voice: voice)
        measurements.append(BenchmarkMeasurement(
            requirement: "PRF-011",
            name: "Cold start to first audio",
            value: coldStart,
            unit: "s",
            target: device?.coldStartTargetSeconds,
            caveat: "Single sample by nature: a true cold start includes process launch and the first lexicon load, neither of which recurs in-process. Repeat the whole command for a distribution. \(mockCaveat)"))

        // PRF-001: batch real-time factor.
        let (rtfSamples, peakMemoryMB) = await measureBatchRTF(voice: voice)
        measurements.append(BenchmarkMeasurement(
            requirement: "PRF-001",
            name: "Batch RTF",
            value: Self.median(rtfSamples),
            unit: "RTF",
            target: device?.batchRTFTarget,
            caveat: mockCaveat,
            samples: rtfSamples.count,
            minimum: rtfSamples.min(),
            maximum: rtfSamples.max()))

        // PRF-010: time to first audio, warm.
        let ttfaSamples = await measureWarmTTFA(voice: voice)
        measurements.append(BenchmarkMeasurement(
            requirement: "PRF-010",
            name: "Warm TTFA",
            value: Self.median(ttfaSamples),
            unit: "ms",
            target: device?.streamingTTFATargetMs,
            caveat: mockCaveat,
            samples: ttfaSamples.count,
            minimum: ttfaSamples.min(),
            maximum: ttfaSamples.max()))

        // The dominant, repeatable component of cold start.
        let loadSamples = measureLexiconLoad()
        measurements.append(BenchmarkMeasurement(
            requirement: "PRF-011",
            name: "Lexicon load",
            value: Self.median(loadSamples),
            unit: "s",
            target: nil,
            caveat: "Component of cold start, not a requirement in itself. Sampled with a fresh lexicon each time; the shared instance loads once per process.",
            samples: loadSamples.count,
            minimum: loadSamples.min(),
            maximum: loadSamples.max()))

        // PRF-020: peak resident memory attributable to the process.
        measurements.append(BenchmarkMeasurement(
            requirement: "PRF-020",
            name: "Peak resident memory",
            value: peakMemoryMB,
            unit: "MB",
            target: device?.peakMemoryTargetMB,
            caveat: "Whole-process RSS, which includes the test host; the requirement asks for memory attributable to CHOIR alone."))

        // PRF-030 / PRF-032: shipped asset size. Real today, unlike the
        // throughput numbers: the lexicon is a shipping asset.
        let assetMB = Self.measureAssetSizeMB()
        measurements.append(BenchmarkMeasurement(
            requirement: device == .r4AppleWatch ? "PRF-032" : "PRF-030",
            name: "Installed asset size",
            value: assetMB,
            unit: "MB",
            target: device?.assetBudgetMB ?? 400,
            caveat: "Voice model assets do not exist yet; this is the lexicon and licence files only."))

        return BenchmarkReport(
            device: device,
            hostDescription: Self.hostDescription,
            packageVersion: Choir.version,
            measurements: measurements,
            notMeasured: [
                "PRF-021 battery: requires 60 minutes of continuous streaming on a physical R1 with playback; not measurable from a test process.",
                "PRF-010 sustained streaming RTF: requires a long-running stream on the target device.",
                "PRF-001/010/011 on R1, R2, R4 and R5: this harness measures the device it runs on. Per PRF-040 it must be run on each reference device and the reports collected.",
            ])
    }

    // MARK: - Individual measurements

    /// PRF-011: a fresh engine, including any lazy loading, to first audio.
    private func measureColdStart(voice: Voice) async -> Double {
        let start = DispatchTime.now()
        let engine = ChoirEngine()
        try? await engine.initialize()
        _ = try? await engine.synthesize(text: "Hello.", voice: voice)
        return Self.secondsSince(start)
    }

    /// PRF-001: synthesis time divided by audio duration, lower is better.
    private func measureBatchRTF(voice: Voice) async -> (samples: [Double], peakMemoryMB: Double) {
        let engine = ChoirEngine()
        try? await engine.initialize()

        // One untimed pass so the measurement excludes first-use costs, which
        // PRF-011 measures separately.
        _ = try? await engine.synthesize(text: Self.standardPassage, voice: voice)

        var samples: [Double] = []
        var peakBytes: UInt64 = 0

        for _ in 0..<iterations {
            let start = DispatchTime.now()
            let audio = try? await engine.synthesize(text: Self.standardPassage, voice: voice)
            let elapsed = Self.secondsSince(start)
            let duration = audio?.duration ?? 0
            if duration > 0 { samples.append(elapsed / duration) }
            peakBytes = max(peakBytes, Self.residentBytes() ?? 0)
        }

        return (samples, Double(peakBytes) / 1_048_576)
    }

    /// The lexicon parse, which dominates cold start and, unlike cold start
    /// itself, can be sampled repeatedly.
    ///
    /// A fresh `BuiltInLexicon` is built each time rather than using the shared
    /// instance, because the shared one is loaded once per process: repeating a
    /// measurement against it would time a dictionary lookup, not a load.
    private func measureLexiconLoad() -> [Double] {
        (0..<iterations).map { _ in
            let start = DispatchTime.now()
            let lexicon = BuiltInLexicon()
            lexicon.preload()
            return Self.secondsSince(start)
        }
    }

    /// Median of a sample set. Chosen over the mean because a single scheduler
    /// stall on a shared machine drags a mean across a target boundary.
    static func median(_ values: [Double]) -> Double {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 0
            ? safeMidpoint(sorted[middle - 1], sorted[middle])
            : sorted[middle]
    }

    /// Linearly interpolated quantile in the closed range 0...1.
    ///
    /// Non-finite samples are ignored. Invalid quantiles and sample sets with
    /// no finite values return `nil`, keeping absence distinct from zero.
    static func percentile(_ quantile: Double, of values: [Double]) -> Double? {
        guard quantile.isFinite, (0...1).contains(quantile) else { return nil }
        let sorted = values.filter(\.isFinite).sorted()
        guard let first = sorted.first else { return nil }
        guard sorted.count > 1 else { return first }

        let rank = quantile * Double(sorted.count - 1)
        let lowerIndex = Int(rank.rounded(.down))
        let upperIndex = Int(rank.rounded(.up))
        guard lowerIndex != upperIndex else { return sorted[lowerIndex] }
        return interpolate(
            from: sorted[lowerIndex],
            to: sorted[upperIndex],
            fraction: rank - Double(lowerIndex))
    }

    /// Unbiased sample standard deviation, calculated in one stable pass.
    static func sampleStandardDeviation(_ values: [Double]) -> Double? {
        let finiteValues = values.filter(\.isFinite)
        guard finiteValues.count > 1 else { return nil }

        var count = 0
        var mean = 0.0
        var sumOfSquaredDifferences = 0.0
        for value in finiteValues {
            count += 1
            let delta = value - mean
            mean += delta / Double(count)
            let adjustedDelta = value - mean
            sumOfSquaredDifferences += delta * adjustedDelta
        }

        guard sumOfSquaredDifferences.isFinite else { return nil }
        return sqrt(max(0, sumOfSquaredDifferences / Double(count - 1)))
    }

    private static func safeMidpoint(_ lower: Double, _ upper: Double) -> Double {
        if lower.sign == upper.sign {
            return lower + (upper - lower) / 2
        }
        return (lower + upper) / 2
    }

    private static func interpolate(
        from lower: Double,
        to upper: Double,
        fraction: Double
    ) -> Double {
        if lower.sign == upper.sign {
            return lower + (upper - lower) * fraction
        }
        return lower * (1 - fraction) + upper * fraction
    }

    /// PRF-010: warm engine to first audio for a typical sentence.
    private func measureWarmTTFA(voice: Voice) async -> [Double] {
        let engine = ChoirEngine()
        try? await engine.initialize()
        _ = try? await engine.synthesize(text: "Warm up.", voice: voice)

        var samples: [Double] = []
        for _ in 0..<iterations {
            let start = DispatchTime.now()
            _ = try? await engine.synthesize(text: "A typical sentence for measurement.", voice: voice)
            samples.append(Self.secondsSince(start) * 1000)
        }
        return samples
    }

    /// PRF-030: size of the assets the package ships.
    static func measureAssetSizeMB() -> Double {
        guard let resourceURL = Bundle.module.resourceURL,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: resourceURL,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles])
        else { return 0 }

        let bytes = contents.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
        return Double(bytes) / 1_048_576
    }

    // MARK: - Platform helpers

    private static func secondsSince(_ start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
    }

    /// Resident set size of this process in bytes.
    static func residentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : nil
    }

    static var hostDescription: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        #if os(macOS)
        let os = "macOS"
        #elseif os(iOS)
        let os = "iOS"
        #elseif os(watchOS)
        let os = "watchOS"
        #elseif os(tvOS)
        let os = "tvOS"
        #elseif os(visionOS)
        let os = "visionOS"
        #else
        let os = "unknown"
        #endif
        return "\(os) on \(machine)"
    }
}
