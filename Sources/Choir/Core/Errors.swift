import Foundation

/// Errors that can occur during synthesis or engine operation.
public enum ChoirError: Error, Sendable, Equatable {
    /// The model files could not be loaded.
    case modelLoadFailed(reason: String)

    /// Text processing failed.
    case textProcessingFailed(reason: String)

    /// Synthesis failed.
    case synthesisError(reason: String)

    /// Audio encoding or export failed.
    case audioEncodingFailed(reason: String)

    /// The engine is not initialized.
    case notInitialized

    /// The requested operation was cancelled.
    case cancelled

    /// An invalid parameter was provided.
    case invalidParameter(parameter: String, reason: String)

    /// Insufficient memory for the operation.
    case outOfMemory

    /// The operation timed out.
    case timeout

    /// An unknown error occurred.
    case unknown(String)
}

extension ChoirError: LocalizedError {
    /// A stable code for this error (SRS REL-001).
    ///
    /// Stable across versions so a consuming app can branch on it, log it, or
    /// map it to its own user-facing copy without matching on message text.
    public var code: String {
        switch self {
        case .modelLoadFailed: return "CHOIR-1001"
        case .textProcessingFailed: return "CHOIR-1002"
        case .synthesisError: return "CHOIR-1003"
        case .audioEncodingFailed: return "CHOIR-1004"
        case .notInitialized: return "CHOIR-1005"
        case .cancelled: return "CHOIR-1006"
        case .invalidParameter: return "CHOIR-1007"
        case .outOfMemory: return "CHOIR-1008"
        case .timeout: return "CHOIR-1009"
        case .unknown: return "CHOIR-1999"
        }
    }

    /// What the caller can do about it (SRS REL-001).
    ///
    /// Every case carries one. An error that says only what went wrong leaves
    /// the caller to guess whether it is worth retrying, and the answer differs
    /// per case: cancellation is expected, memory pressure is retryable after
    /// shedding caches, a corrupt asset is not retryable at all.
    public var recoverySuggestion: String? {
        switch self {
        case .modelLoadFailed:
            return "Verify the installation with engine.verify(). If assets are corrupt, reinstall the voice pack."
        case .textProcessingFailed:
            return "Check the input is valid UTF-8 and non-empty. In strict markup mode, malformed markup throws; use non-strict mode to degrade instead."
        case .synthesisError:
            return "Retry once. If it persists, call engine.verify() to distinguish a broken installation from a transient failure."
        case .audioEncodingFailed:
            return "Check the destination is writable and has free space, and that the requested format is supported."
        case .notInitialized:
            return "Call engine.initialize() before synthesizing, or use the warm-up API at launch."
        case .cancelled:
            return "No action needed: the task was cancelled by the caller."
        case .invalidParameter:
            return "Check the value against its documented envelope. SynthesisParameters clamps out-of-range values and reports them in its clampings property."
        case .outOfMemory:
            return "Free memory and retry. Reduce concurrent synthesis jobs, or switch to the efficient vocoder path."
        case .timeout:
            return "Retry with a shorter input, or synthesize in batches."
        case .unknown:
            return "Retry once. If it persists, report the error code and the input that produced it."
        }
    }

    /// Whether retrying the same request could plausibly succeed.
    public var isRetryable: Bool {
        switch self {
        case .synthesisError, .outOfMemory, .timeout, .unknown: return true
        case .modelLoadFailed, .textProcessingFailed, .audioEncodingFailed,
             .notInitialized, .cancelled, .invalidParameter: return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .textProcessingFailed(let reason):
            return "Text processing failed: \(reason)"
        case .synthesisError(let reason):
            return "Synthesis error: \(reason)"
        case .audioEncodingFailed(let reason):
            return "Audio encoding failed: \(reason)"
        case .notInitialized:
            return "Choir engine is not initialized"
        case .cancelled:
            return "Operation was cancelled"
        case .invalidParameter(let parameter, let reason):
            return "Invalid parameter '\(parameter)': \(reason)"
        case .outOfMemory:
            return "Insufficient memory to complete operation"
        case .timeout:
            return "Operation timed out"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}
