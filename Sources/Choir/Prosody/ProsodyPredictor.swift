import Foundation

/// Predicts prosodic features (pitch, duration, energy) from linguistic input.
///
/// Uses rule-based and statistical methods to generate realistic prosody.
public struct ProsodyPredictor: Sendable {
    /// Base fundamental frequency (F0) for neutral speech in Hz.
    private let basePitch: Double

    /// Speaker's pitch range (minimum to maximum F0).
    private let pitchRange: (min: Double, max: Double)

    /// Default speaking rate in phonemes per second.
    private let speakingRate: Double

    public init(
        basePitch: Double = 120.0,
        pitchRange: (min: Double, max: Double) = (80, 200),
        speakingRate: Double = 15.0
    ) {
        self.basePitch = basePitch
        self.pitchRange = pitchRange
        self.speakingRate = speakingRate
    }

    /// Predicts prosody for a phonetic transcription.
    ///
    /// - Parameters:
    ///   - transcript: The phonetic transcription.
    ///   - synthesisParams: Synthesis parameters affecting prosody.
    /// - Returns: A complete prosody description.
    public func predictProsody(
        for transcript: PhoneticTranscription,
        with synthesisParams: SynthesisParameters
    ) -> ProsodyDescription {
        let rate = synthesisParams.rate
        let pitchShift = synthesisParams.pitchShift
        let emotionalIntensity = synthesisParams.emotionalIntensity

        // Step 1: Predict durations for each phoneme
        let durations = predictDurations(transcript.phonemes, rate: rate)

        // Step 2: Predict pitch contour
        let pitchPoints = predictPitchContour(
            transcript.phonemes,
            durations: durations,
            pitchShift: pitchShift,
            emotionalIntensity: emotionalIntensity
        )
        let pitchContour = ProsodyContour(points: pitchPoints, interpolation: "spline")

        // Step 3: Predict energy contour
        let energyPoints = predictEnergyContour(
            transcript.phonemes,
            durations: durations,
            emotionalIntensity: emotionalIntensity
        )
        let energyContour = ProsodyContour(points: energyPoints, interpolation: "spline")

        // Step 4: Create annotated phonemes with timing
        var annotated: [AnnotatedPhoneme] = []
        var currentTime: Double = 0

        for (i, phoneme) in transcript.phonemes.enumerated() {
            let duration = durations[i]
            let timing = TimingInfo(startTime: currentTime, endTime: currentTime + duration)

            let f0 = pitchContour.valueAt(currentTime + duration / 2) ?? basePitch
            let energy = energyContour.valueAt(currentTime + duration / 2) ?? -20.0

            let prosody = ProsodyFeatures(
                fundamentalFrequency: f0,
                duration: duration,
                energy: energy,
                voicing: phoneme.isVowel ? 1.0 : 0.0,
                isVoiced: phoneme.isVowel,
                accentType: selectAccentType(phoneme, at: i, in: transcript.phonemes),
                boundaryTone: "none"
            )

            annotated.append(AnnotatedPhoneme(phoneme: phoneme, prosody: prosody, timing: timing))
            currentTime += duration
        }

        return ProsodyDescription(
            phonemes: annotated,
            pitchContour: pitchContour,
            energyContour: energyContour,
            durations: durations
        )
    }

    /// Predicts duration for each phoneme based on phonetic context.
    private func predictDurations(_ phonemes: [Phoneme], rate: Double) -> [Double] {
        var durations: [Double] = []

        for (i, phoneme) in phonemes.enumerated() {
            // Base duration: vowels are longer than consonants
            var duration: Double = phoneme.isVowel ? 100 : 50

            // Adjust for stress (stressed vowels are longer)
            if phoneme.isVowel && phoneme.stress > 0 {
                duration *= (1.0 + Double(phoneme.stress) * 0.3)
            }

            // Adjust for speaking rate
            duration /= rate

            // Context effects
            let isWordFinal = (i == phonemes.count - 1) || (i + 1 < phonemes.count && phonemes[i + 1].symbol == " ")
            if isWordFinal && phoneme.isVowel {
                duration *= 1.2  // Phrase-final lengthening
            }

            // Consonant adjustments
            if !phoneme.isVowel {
                // Obstruents (stops, fricatives) are shorter
                if isObstruent(phoneme.symbol) {
                    duration *= 0.8
                }
            }

            durations.append(max(10, min(500, duration)))
        }

        return durations
    }

    /// Predicts pitch contour based on stress, emotion, and phrase structure.
    private func predictPitchContour(
        _ phonemes: [Phoneme],
        durations: [Double],
        pitchShift: Double,
        emotionalIntensity: Double
    ) -> [(time: Double, value: Double)] {
        var contour: [(time: Double, value: Double)] = []
        var currentTime: Double = 0

        // Base pitch with shift
        var basePitch = self.basePitch + (pitchShift * 5.0)  // ~5 Hz per semitone
        basePitch = max(pitchRange.min, min(pitchRange.max, basePitch))

        for (i, phoneme) in phonemes.enumerated() {
            let duration = durations[i]
            let midpoint = currentTime + duration / 2

            // Determine pitch based on stress and emotional intensity
            var f0 = basePitch

            // Stressed syllables get higher pitch
            if phoneme.stress > 0 {
                let stressBoost = Double(phoneme.stress) * 15.0  // Hz boost
                f0 += stressBoost
            }

            // Emotional intensity affects pitch range
            let emotionalBoost = emotionalIntensity * 20.0
            f0 += emotionalBoost

            // Add declination (gradual pitch drop over utterance)
            let declinationFactor = Double(i) / Double(max(1, phonemes.count))
            f0 -= declinationFactor * 10.0

            // Phrase-final lowering
            if i == phonemes.count - 1 {
                f0 -= 15.0
            }

            f0 = max(pitchRange.min, min(pitchRange.max, f0))

            if phoneme.isVowel {
                contour.append((time: midpoint, value: f0))
            }

            currentTime += duration
        }

        // Ensure we have at least start and end points
        if contour.isEmpty {
            contour.append((time: 0, value: basePitch))
            contour.append((time: currentTime, value: basePitch - 15))
        }

        return contour
    }

    /// Predicts energy (loudness) contour.
    private func predictEnergyContour(
        _ phonemes: [Phoneme],
        durations: [Double],
        emotionalIntensity: Double
    ) -> [(time: Double, value: Double)] {
        var contour: [(time: Double, value: Double)] = []
        var currentTime: Double = 0

        // Base energy
        let baseEnergy = -20.0 + emotionalIntensity * 10.0

        for (i, phoneme) in phonemes.enumerated() {
            let duration = durations[i]
            let midpoint = currentTime + duration / 2

            var energy = baseEnergy

            // Vowels are louder than consonants
            if phoneme.isVowel {
                energy += 10.0
            }

            // Stressed syllables are louder
            if phoneme.stress > 0 {
                energy += Double(phoneme.stress) * 5.0
            }

            // Word-initial consonants are often louder
            if i > 0 && !phonemes[i - 1].isVowel {
                if phoneme.isVowel {
                    energy += 3.0
                }
            }

            // Emotional intensity affects overall loudness
            energy += emotionalIntensity * 5.0

            energy = max(-60, min(0, energy))

            if phoneme.isVowel {
                contour.append((time: midpoint, value: energy))
            }

            currentTime += duration
        }

        // Fallback if no vowels
        if contour.isEmpty {
            contour.append((time: 0, value: baseEnergy))
            contour.append((time: currentTime, value: baseEnergy))
        }

        return contour
    }

    /// Selects appropriate pitch accent based on position and stress.
    private func selectAccentType(_ phoneme: Phoneme, at index: Int, in phonemes: [Phoneme]) -> String {
        guard phoneme.isVowel && phoneme.stress > 0 else { return "none" }

        // Simple accent selection based on position in word
        let accentTypes = ["H*", "L+H*", "H+L*"]
        let selection = index % accentTypes.count
        return accentTypes[selection]
    }

    /// Checks if a phoneme is an obstruent (stop or fricative).
    private func isObstruent(_ phoneme: String) -> Bool {
        let obstruents = Set(["p", "b", "t", "d", "k", "g", "f", "v", "θ", "ð", "s", "z", "ʃ", "ʒ", "tʃ", "dʒ"])
        return obstruents.contains(phoneme)
    }
}
