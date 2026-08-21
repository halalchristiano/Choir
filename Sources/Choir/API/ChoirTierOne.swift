import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// Tier 1 of the public API (SRS API-001).
///
/// "The API shall offer three concentric tiers, each complete for its use
/// level: **Tier 1 (one-liner):** `try await Choir.speak("text", voice: .maeve)`
/// — synthesize and play."
///
/// The point of a concentric API is that the simplest use costs one line and no
/// ceremony, while nothing is hidden: Tier 2 (``ChoirEngine``) and Tier 3
/// (streaming, metadata, phoneme input) stay directly available, and Tier 1 is
/// written in terms of them rather than beside them.
extension Choir {

    /// Synthesizes `text` and plays it.
    ///
    /// Creates and initializes an engine per call, so this is the convenient
    /// path rather than the efficient one. An app speaking repeatedly should
    /// hold a ``ChoirEngine`` and reuse it — that is Tier 2.
    ///
    /// - Returns: the synthesized audio, once playback has finished.
    @discardableResult
    public static func speak(
        _ text: String,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters()
    ) async throws -> AudioBuffer {
        let audio = try await synthesize(text, voice: voice, parameters: parameters)
        try await play(audio)
        return audio
    }

    /// Synthesizes `text` without playing it.
    ///
    /// The same one-line shape for callers that want the buffer — to write a
    /// file, or feed a mixer — rather than immediate playback.
    public static func synthesize(
        _ text: String,
        voice: Voice,
        parameters: SynthesisParameters = SynthesisParameters()
    ) async throws -> AudioBuffer {
        let engine = ChoirEngine()
        try await engine.initialize()
        return try await engine.synthesize(text: text, voice: voice, parameters: parameters)
    }

    /// Plays a synthesized buffer, returning when playback finishes.
    public static func play(_ audio: AudioBuffer) async throws {
        #if canImport(AVFoundation)
        guard !audio.samples.isEmpty else { return }

        // Played from encoded WAV rather than an AVAudioPCMBuffer so playback
        // goes through the package's own encoder: one audio format path rather
        // than two that can drift apart.
        let data = try AudioEncoder().encodeWAV(audio)
        let player: AVAudioPlayer
        do {
            player = try AVAudioPlayer(data: data)
        } catch {
            throw ChoirError.audioEncodingFailed(
                reason: "Could not prepare audio for playback: \(error.localizedDescription)")
        }

        let completion = PlaybackCompletion()
        player.delegate = completion
        guard player.play() else {
            throw ChoirError.synthesisError(reason: "Audio playback failed to start")
        }
        await completion.wait()
        #else
        throw ChoirError.synthesisError(
            reason: "Playback is unavailable on this platform; use Choir.synthesize(_:voice:) instead")
        #endif
    }
}

#if canImport(AVFoundation)
/// Bridges `AVAudioPlayer`'s delegate callback to an `await`.
private final class PlaybackCompletion: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        complete()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        complete()
    }

    /// Resumes at most once: the delegate may fire either callback, and a
    /// continuation resumed twice traps.
    private func complete() {
        lock.lock()
        finished = true
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume()
    }
}
#endif
