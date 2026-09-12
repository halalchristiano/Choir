import Foundation

extension SynthesisPipeline {
    /// A pipeline that renders audible speech with no trained model and no
    /// bundled voice assets.
    ///
    /// The default pipeline pairs ``MockAcousticModel`` with ``MockVocoder``
    /// and emits a test tone, which exercises the API but never produces
    /// speech. This factory swaps in the rule-based formant path instead, so
    /// that the front end, prosody, timing and audio stages can be heard
    /// working end to end.
    ///
    /// ```swift
    /// let engine = ChoirEngine(pipeline: .formant())
    /// try await engine.initialize()
    /// let audio = try await engine.synthesize(text: "Hello world.", voice: .orion)
    /// ```
    ///
    /// - Important: This is a development and demonstration path. It produces
    ///   speech-structured, unmistakably synthetic audio, and it satisfies no
    ///   SRS quality gate. Measured intelligibility is 8.2% word accuracy
    ///   against a 98% target (QUA-004), so it should not be described as
    ///   intelligible without that number beside it.
    public static func formant(
        linguisticFrontend: LinguisticFrontend = LinguisticFrontend(),
        prosodyPredictor: ProsodyPredictor = ProsodyPredictor(),
        audioFormat: AudioFormat = AudioFormat()
    ) -> SynthesisPipeline {
        SynthesisPipeline(
            linguisticFrontend: linguisticFrontend,
            prosodyPredictor: prosodyPredictor,
            acousticModel: FormantAcousticModel(),
            vocoder: FormantVocoder(),
            audioFormat: audioFormat)
    }
}
