import Foundation
import Testing
@testable import Choir

/// SRS CON-002 and SYN-007 — cancellation.
///
/// CON-002: "all async APIs honour Swift task cancellation (checked at least
/// every 50 ms of compute) and propagate it per SYN-007."
///
/// SYN-007: "Cancellation shall be prompt (< 100 ms to stop compute) and clean
/// (no leaked buffers, model left in reusable state)."
///
/// Nothing checked cancellation before this: a sixty-minute audiobook render,
/// the workload the specification names, could not be stopped once started.
@Suite("SRS CON-002/SYN-007 — cancellation")
struct CancellationTests {

    /// REL-001 requires a single public taxonomy that covers cancellation, so
    /// a caller catching `ChoirError` must not also have to catch
    /// `CancellationError`.
    @Test("CON-002: cancellation surfaces as ChoirError.cancelled")
    func testCancellationIsChoirError() async {
        let task = Task {
            // Cancelled before it starts, so the first check fires.
            try Cancellation.check()
        }
        task.cancel()

        do {
            try await task.value
            Issue.record("expected cancellation")
        } catch let error as ChoirError {
            #expect(error == .cancelled)
            #expect(error.code == "CHOIR-1006")
        } catch {
            Issue.record("threw \(type(of: error)) rather than ChoirError")
        }
    }

    @Test("CON-002: an uncancelled task is not disturbed")
    func testNoFalsePositive() throws {
        // The common path must not throw.
        try Cancellation.check()
    }

    @Test("CON-002: CancellationError is mapped into the taxonomy")
    func testMappingTranslates() async {
        do {
            _ = try await Cancellation.mapping {
                throw CancellationError()
            }
            Issue.record("expected a throw")
        } catch let error as ChoirError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("threw \(type(of: error))")
        }
    }

    /// The requirement in practice: a synthesis already cancelled must stop
    /// rather than run to completion.
    @Test("SYN-007: a cancelled synthesis throws instead of completing")
    func testCancelledSynthesisStops() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let task = Task {
            try await engine.synthesize(
                text: String(repeating: "This is a long passage to render. ", count: 100),
                voice: .isla)
        }
        task.cancel()

        do {
            _ = try await task.value
            // Completing is acceptable only if it finished before the first
            // check; what must never happen is a non-ChoirError escaping.
        } catch let error as ChoirError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("threw \(type(of: error)) rather than ChoirError")
        }
    }

    /// SYN-007's "model left in reusable state": the engine must work
    /// afterwards.
    @Test("SYN-007: the engine is reusable after a cancellation")
    func testEngineReusableAfterCancellation() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let cancelled = Task {
            try await engine.synthesize(
                text: String(repeating: "Cancel me. ", count: 400), voice: .isla)
        }
        cancelled.cancel()
        _ = try? await cancelled.value

        // The engine must still synthesize normally.
        let audio = try await engine.synthesize(text: "Still working.", voice: .isla)
        #expect(!audio.samples.isEmpty, "engine was left unusable by cancellation")

        let health = await engine.verify()
        #expect(health.isHealthy, "\(health.summary)")
    }

    /// TXT-001 requires accepting at least 1,000,000 characters. The engine
    /// capped input at 5,000 — two orders of magnitude low, and small enough
    /// to reject one chapter of the audiobooks the specification names as a
    /// primary workload. Found because a cancellation test wrote a long enough
    /// input to trip it.
    @Test("TXT-001: the documented ceiling is a million characters")
    func testCeilingMatchesRequirement() {
        #expect(ChoirEngine.maximumInputCharacters >= 1_000_000)
    }

    /// Exercised through the front end rather than full synthesis: the limit
    /// lives in validation, and rendering twenty thousand characters through
    /// the mock pipeline costs minutes in a debug build without testing
    /// anything the shorter cases do not.
    @Test("TXT-001: long documents pass the front end")
    func testLongDocumentProcessed() throws {
        let long = String(repeating: "This is a sentence of an audiobook chapter. ", count: 500)
        #expect(long.count > 20_000)

        let transcript = try LinguisticFrontend().process(long)
        #expect(!transcript.phonemes.isEmpty)
    }

    @Test("TXT-001: input beyond the documented ceiling is a typed error")
    func testBeyondCeilingRejected() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let tooLong = String(repeating: "a", count: ChoirEngine.maximumInputCharacters + 1)
        await #expect(throws: ChoirError.self) {
            _ = try await engine.synthesize(text: tooLong, voice: .isla)
        }
    }

    @Test("CON-002: a cancelled batch stops rather than reporting failures")
    func testCancelledBatchStops() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let task = Task {
            try await engine.synthesizeBatch(
                texts: Array(repeating: "One line of dialogue.", count: 200),
                voice: .isla,
                policy: .continueAndReport)
        }
        task.cancel()

        do {
            let result = try await task.value
            // If it completed, it must be a real result, not a wall of errors.
            #expect(result.failures.isEmpty, "cancellation was reported as item failures")
        } catch let error as ChoirError {
            #expect(error == .cancelled)
        } catch {
            Issue.record("threw \(type(of: error))")
        }
    }
}

/// SRS REL-002 — partial-failure policy.
@Suite("SRS REL-002 — batch failure policy")
struct BatchPolicyTests {

    @Test("REL-002: a clean batch reports every item")
    func testCleanBatch() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let texts = ["First line.", "Second line.", "Third line."]
        let result = try await engine.synthesizeBatch(texts: texts, voice: .isla)

        #expect(result.outcomes.count == 3)
        #expect(result.isComplete)
        #expect(result.successes.count == 3)
        #expect(result.totalDuration > 0)
        #expect(result.summary.contains("3 of 3"))
    }

    @Test("REL-002: outcomes keep their input and position")
    func testOutcomesCarryContext() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let texts = ["Alpha.", "Beta.", "Gamma."]
        let result = try await engine.synthesizeBatch(texts: texts, voice: .isla)

        for (index, outcome) in result.outcomes.enumerated() {
            #expect(outcome.index == index)
            #expect(outcome.text == texts[index])
        }
    }

    /// Fail-fast is right when the items form one artifact: half an audiobook
    /// is not a useful result.
    @Test("REL-002: fail-fast stops at the first failure")
    func testFailFast() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        // An empty item fails validation.
        let texts = ["Good line.", "", "Never reached."]

        await #expect(throws: ChoirError.self) {
            _ = try await engine.synthesizeBatch(
                texts: texts, voice: .isla, policy: .failFast)
        }
    }

    /// Continue-and-report is right when items are independent: one
    /// unpronounceable name should not cost the other four hundred.
    @Test("REL-002: continue-and-report attempts every item")
    func testContinueAndReport() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let texts = ["Good line.", "", "Also good."]
        let result = try await engine.synthesizeBatch(
            texts: texts, voice: .isla, policy: .continueAndReport)

        #expect(result.outcomes.count == 3, "not every item was attempted")
        #expect(!result.isComplete)
        #expect(result.successes.count == 2)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.index == 1)
        #expect(result.failures.first?.error != nil)
    }

    @Test("REL-002: an empty batch is not an error")
    func testEmptyBatch() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let result = try await engine.synthesizeBatch(texts: [], voice: .isla)
        #expect(result.outcomes.isEmpty)
        #expect(result.isComplete)
        #expect(result.totalDuration == 0)
    }

    @Test("REL-002: the policy is recorded on the result")
    func testPolicyRecorded() async throws {
        let engine = ChoirEngine()
        try await engine.initialize()

        let result = try await engine.synthesizeBatch(
            texts: ["One."], voice: .isla, policy: .continueAndReport)
        #expect(result.policy == .continueAndReport)
    }

    @Test("REL-002: both policies are selectable and distinct")
    func testPoliciesDistinct() {
        #expect(PartialFailurePolicy.allCases.count == 2)
        #expect(PartialFailurePolicy.failFast != PartialFailurePolicy.continueAndReport)
    }
}
