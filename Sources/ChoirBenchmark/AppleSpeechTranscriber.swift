import Foundation
import Choir

// Selective imports rather than qualification. Apple's Speech framework
// declares its own `SpeechTranscriber`, and `AudioBuffer` comes from
// CoreAudioTypes, so both names are ambiguous once Speech is imported. Writing
// `Choir.AudioBuffer` does not help either: the library also exports a type
// named `Choir`, which shadows the module in a qualified lookup.
import protocol Choir.SpeechTranscriber
import struct Choir.AudioBuffer
import struct Choir.AudioEncoder
import enum Choir.ChoirError

#if canImport(Speech)
import Speech
#endif

/// Transcribes synthesized audio with Apple's Speech framework (SRS QUA-004).
///
/// Lives in the benchmark tool rather than the library on purpose. `SEC-001`
/// requires the runtime to make zero network connections, and a consuming app
/// should not link a speech framework, request speech-recognition
/// authorization, or face a privacy prompt because CHOIR is able to test
/// itself. Nothing here is reachable from the shipped library.
///
/// The protocol and buffer types are qualified with `Choir.` because Apple's
/// Speech framework declares its own `SpeechTranscriber`, and `AudioBuffer`
/// comes from CoreAudioTypes; importing Speech makes both names ambiguous.
///
/// Recognition is forced on-device. That is partly about honouring the spirit
/// of `SEC-001` even in a test tool, and partly about the measurement: a
/// server-side recognizer may apply language-model correction strong enough to
/// repair speech a listener could not actually understand, which would flatter
/// the score.
struct AppleSpeechTranscriber: SpeechTranscriber {
    let identifier = "Apple Speech (on-device)"

    private let locale: Locale

    init(locale: Locale = Locale(identifier: "en-US")) {
        self.locale = locale
    }

    var isAvailable: Bool {
        get async {
            #if canImport(Speech)
            guard let recognizer = SFSpeechRecognizer(locale: locale),
                  recognizer.isAvailable else { return false }
            guard recognizer.supportsOnDeviceRecognition else { return false }
            return await Self.requestAuthorization()
            #else
            return false
            #endif
        }
    }

    func transcribe(_ audio: AudioBuffer) async throws -> String {
        #if canImport(Speech)
        // The recognizer reads a file, so the buffer is written as WAV using
        // the package's own encoder rather than a second audio path.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("choir-asr-\(UUID().uuidString).wav")
        let wav = AudioEncoder().encodeWAV(audio)
        try wav.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw ChoirError.synthesisError(reason: "Speech recognizer unavailable")
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            // The callback fires more than once for partial results even when
            // they are disabled, so completion is guarded.
            let hasResumed = Resumed()
            recognizer.recognitionTask(with: request) { result, error in
                guard hasResumed.claim() else { return }
                if let result, result.isFinal || error == nil {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else {
                    continuation.resume(
                        throwing: error ?? ChoirError.synthesisError(reason: "Recognition produced no result"))
                }
            }
        }
        #else
        throw ChoirError.synthesisError(reason: "Speech framework unavailable on this platform")
        #endif
    }

    #if canImport(Speech)
    private static func requestAuthorization() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            return false
        }
    }
    #endif
}

/// One-shot guard for a callback that may fire more than once.
private final class Resumed: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
