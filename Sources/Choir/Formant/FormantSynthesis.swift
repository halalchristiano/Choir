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
    /// - Important: This is a development and demonstration path. It is
    ///   intelligible and unmistakably synthetic, and it does not satisfy the
    ///   naturalness, distinctness or listening-fatigue gates in the SRS. Those
    ///   still require trained models.
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
