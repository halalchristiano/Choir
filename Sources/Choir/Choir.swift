/// CHOIR's pre-alpha on-device voice-synthesis infrastructure for Apple platforms.
///
/// The package currently ships a mock-backed development engine, public API,
/// linguistic front end, timing, streaming, caching, and verification tools.
/// It does not yet bundle the trained models required for production speech.
public struct Choir {
    /// The current version of the Choir package.
    ///
    /// Kept in step with the released tag. It had drifted to 0.1.0 across
    /// eleven releases before the benchmark harness printed it into a report
    /// and made the drift visible.
    public static let version = "0.16.0"

    /// Audio-output compatibility version used by persistent synthesis caches.
    ///
    /// Increment this only when identical seeded inputs intentionally produce
    /// different audio. Ordinary source, API, or documentation releases do
    /// not invalidate cached renders (DST-001).
    public static let engineVersion: UInt64 = 1
}
