import Foundation

/// Cancellation support (SRS CON-002, SYN-007).
///
/// CON-002 requires all async APIs to honour Swift task cancellation, "checked
/// at least every 50 ms of compute", and SYN-007 requires cancellation to be
/// "prompt (< 100 ms to stop compute) and clean (no leaked buffers, model left
/// in reusable state)".
///
/// Nothing checked cancellation before this. A sixty-minute audiobook render,
/// which is exactly the workload the specification names, could not be stopped
/// once started.
enum Cancellation {

    /// Throws ``ChoirError/cancelled`` if the current task has been cancelled.
    ///
    /// Maps Swift's `CancellationError` into the package's own taxonomy,
    /// because REL-001 requires "a single public `ChoirError` taxonomy" that
    /// covers cancellation. A caller catching `ChoirError` should not also have
    /// to catch a second error type for the one outcome the taxonomy already
    /// names.
    @inline(__always)
    static func check() throws {
        if Task.isCancelled { throw ChoirError.cancelled }
    }

    /// Runs `work`, translating any `CancellationError` it throws.
    ///
    /// For calls into code that cancels in Swift's idiom rather than this one.
    static func mapping<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch is CancellationError {
            throw ChoirError.cancelled
        }
    }
}

/// How a batch job responds to an item failing (SRS REL-002).
///
/// "Partial-failure policy for batch/multi-item jobs shall be
/// caller-selectable: fail-fast, or continue-and-report (result carries
/// per-item success/error list)."
public enum PartialFailurePolicy: String, Sendable, Equatable, Codable, CaseIterable {
    /// Stop at the first failure and throw.
    ///
    /// Right when the items form one artifact: half an audiobook is not a
    /// useful result.
    case failFast

    /// Attempt every item and report per-item outcomes.
    ///
    /// Right when items are independent, such as a table of game lines, where
    /// one unpronounceable name should not cost the other four hundred.
    case continueAndReport
}

/// The outcome of one item in a batch.
public struct BatchItemOutcome: Sendable {
    public let index: Int
    public let text: String
    public let audio: AudioBuffer?
    public let error: ChoirError?

    public var succeeded: Bool { audio != nil }

    init(index: Int, text: String, audio: AudioBuffer) {
        self.index = index
        self.text = text
        self.audio = audio
        self.error = nil
    }

    init(index: Int, text: String, error: ChoirError) {
        self.index = index
        self.text = text
        self.audio = nil
        self.error = error
    }
}

/// The result of a batch synthesis job (SRS REL-002).
public struct BatchResult: Sendable {
    public let outcomes: [BatchItemOutcome]
    public let policy: PartialFailurePolicy

    public init(outcomes: [BatchItemOutcome], policy: PartialFailurePolicy) {
        self.outcomes = outcomes
        self.policy = policy
    }

    public var successes: [BatchItemOutcome] { outcomes.filter(\.succeeded) }
    public var failures: [BatchItemOutcome] { outcomes.filter { !$0.succeeded } }

    /// Whether every item succeeded.
    public var isComplete: Bool { failures.isEmpty }

    /// Total duration of the successfully synthesized audio, in seconds.
    public var totalDuration: Double {
        successes.compactMap(\.audio?.duration).reduce(0, +)
    }

    public var summary: String {
        "\(successes.count) of \(outcomes.count) items synthesized"
            + (failures.isEmpty ? "" : "; \(failures.count) failed")
    }
}
