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
