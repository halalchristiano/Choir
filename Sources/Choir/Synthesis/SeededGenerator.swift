import Foundation

/// A deterministic pseudo-random generator (SRS SYN-002).
///
/// SYN-002 requires that identical `(text, voice, parameters, seed, package
/// version)` produce bit-identical audio on the same device class, so that
/// audiobook and video builds are reproducible. That rules out
/// `SystemRandomNumberGenerator`, whose output is not reproducible even within
/// one process.
///
/// The algorithm is SplitMix64: small, fast, well-distributed, and specified
/// entirely by integer arithmetic, so it yields the same stream on every
/// architecture. It is deliberately *not* cryptographic — this drives
/// micro-timing jitter, not key material.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    /// Creates a generator for `seed`.
    ///
    /// Every seed value is valid, including zero.
    public init(seed: UInt64) {
        // Offset so that seed 0 does not start from the all-zero state.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `-magnitude ... magnitude`, uniformly distributed.
    ///
    /// Used for the bounded prosodic jitter of SYN-003.
    public mutating func jitter(magnitude: Double) -> Double {
        guard magnitude > 0 else { return 0 }
        // Map to 0..<1 from the top 53 bits, the range a Double represents exactly.
        let unit = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
        return (unit * 2 - 1) * magnitude
    }
}

/// Source of prosodic variation for one synthesis request.
///
/// With a seed the stream is reproducible (SYN-002); without one it varies
/// between renders (SYN-003), so a repeated game line does not sound
/// mechanically identical each time.
public struct ProsodyVariation: Sendable {
    private var generator: SeededGenerator

    /// Whether this variation is reproducible.
    public let isDeterministic: Bool

    /// Creates a variation source.
    ///
    /// - Parameter seed: a seed for reproducible output, or `nil` to vary.
    public init(seed: UInt64?) {
        if let seed {
            self.generator = SeededGenerator(seed: seed)
            self.isDeterministic = true
        } else {
            // No seed: draw a starting point from the system generator, then
            // proceed deterministically from it. Variation is therefore still
            // bounded and well-distributed, just not reproducible.
            var system = SystemRandomNumberGenerator()
            self.generator = SeededGenerator(seed: system.next())
            self.isDeterministic = false
        }
    }

    /// Maximum proportional deviation applied to a phoneme duration.
    ///
    /// Kept small: this is the difference between two natural readings of the
    /// same line, not a different delivery.
    public static let durationJitter = 0.03

    /// Maximum proportional deviation applied to a pitch target.
    public static let pitchJitter = 0.015

    /// A duration multiplier near 1.0.
    public mutating func durationScale() -> Double {
        1.0 + generator.jitter(magnitude: Self.durationJitter)
    }

    /// A pitch multiplier near 1.0.
    public mutating func pitchScale() -> Double {
        1.0 + generator.jitter(magnitude: Self.pitchJitter)
    }
}
