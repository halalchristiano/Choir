import Foundation

/// The reference devices all PRF targets are measured on (SRS §28.1).
public enum ReferenceDevice: String, Sendable, Equatable, Codable, CaseIterable {
    /// iPhone 13 (A15) — the floor mobile device.
    case r1iPhone13 = "R1"

    /// Current-generation iPhone Pro.
    case r2iPhonePro = "R2"

    /// MacBook (M2 or later).
    case r3MacBook = "R3"

    /// Apple Watch Series 9.
    case r4AppleWatch = "R4"

    /// Apple Vision Pro.
    case r5VisionPro = "R5"

    /// Resolves a report or command-line identifier without locale-sensitive
    /// casing. Both stable R-numbers and human-readable names are accepted.
    public init?(identifier: String) {
        let key = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        guard let device = Self.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(key) == .orderedSame
                || $0.displayName.caseInsensitiveCompare(key) == .orderedSame
        }) else { return nil }
        self = device
    }

    public var displayName: String {
        switch self {
        case .r1iPhone13: return "iPhone 13 (A15)"
        case .r2iPhonePro: return "iPhone Pro (current)"
        case .r3MacBook: return "MacBook (M2 or later)"
        case .r4AppleWatch: return "Apple Watch Series 9"
        case .r5VisionPro: return "Apple Vision Pro"
        }
    }

    // MARK: - Targets
    //
    // `nil` means the specification sets no target for that device, not that
    // the target is unlimited. A measurement without a target is reported and
    // not judged.

    /// PRF-001: batch real-time factor.
    public var batchRTFTarget: Double? {
        switch self {
        case .r1iPhone13: return 0.35
        case .r3MacBook: return 0.15
        default: return nil
        }
    }

    /// PRF-010: streaming time to first audio, warm engine, in milliseconds.
    public var streamingTTFATargetMs: Double? {
        switch self {
        case .r1iPhone13: return 350
        case .r2iPhonePro, .r3MacBook, .r5VisionPro: return 250
        case .r4AppleWatch: return nil
        }
    }

    /// PRF-010: sustained streaming real-time factor.
    public var sustainedStreamingRTFTarget: Double? {
        self == .r1iPhone13 ? 0.5 : nil
    }

    /// PRF-011: cold start, process launch to first audio, in seconds.
    public var coldStartTargetSeconds: Double? {
        switch self {
        case .r1iPhone13: return 3.0
        case .r3MacBook: return 1.5
        default: return nil
        }
    }

    /// PRF-020: peak resident memory during single-stream synthesis, in MB.
    public var peakMemoryTargetMB: Double? {
        switch self {
        case .r1iPhone13: return 350
        case .r4AppleWatch: return 180
        default: return nil
        }
    }

    /// PRF-030 / PRF-032: installed asset budget in MB.
    public var assetBudgetMB: Double {
        self == .r4AppleWatch ? 60 : 400
    }

    /// PRF-030: the size the specification says SHOULD be targeted.
    public var assetTargetMB: Double? {
        self == .r4AppleWatch ? nil : 250
    }

    /// The device this process is most likely running on.
    ///
    /// Best effort, and deliberately conservative: an unrecognized Mac is
    /// reported as R3 only when it is Apple silicon, because the M2 targets
    /// are not meaningful on Intel. `nil` means the run is not on a reference
    /// device and its numbers should not be compared against targets.
    public static var current: ReferenceDevice? {
        #if os(watchOS)
        return .r4AppleWatch
        #elseif os(visionOS)
        return .r5VisionPro
        #elseif os(iOS)
        // Distinguishing an iPhone 13 from a current Pro needs a model
        // identifier table that would go stale; callers state the device.
        return nil
        #elseif os(macOS)
        #if arch(arm64)
        return .r3MacBook
        #else
        return nil
        #endif
        #else
        return nil
        #endif
    }
}
