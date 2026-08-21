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
        with synthesisParams: SynthesisParameters,
        voiceProfile: VoiceProfile? = nil
    ) -> ProsodyDescription {
        let rate = synthesisParams.rate
        let pitchShift = synthesisParams.pitchShift
        let emotionalIntensity = synthesisParams.emotionalIntensity
        // Age and gender shifts are continuous conditioning controls rather
        // than metadata-only values. Positive age trends older/lower; positive
        // gender trends masculine/lower. The acoustic model receives the raw
        // controls as well, where production formant/timbre changes belong.
        let identityPitchRatio = pow(
            2,
            (-1.5 * synthesisParams.ageShift - 3 * synthesisParams.genderShift) / 12)
        let effectiveBasePitch = (voiceProfile?.medianF0 ?? basePitch) * identityPitchRatio
        let effectivePitchRange = voiceProfile.map {
            (
                min: $0.f0Range.lowerBound * identityPitchRatio,
                max: $0.f0Range.upperBound * identityPitchRatio)
        } ?? pitchRange
        let articulationPrecision = voiceProfile?.articulationPrecision ?? 0.9
        let pauseStyle = voiceProfile?.pauseStyle ?? VoicePauseStyle()

        // SYN-002/SYN-003: a seed makes the variation reproducible; without
        // one it differs per render, so a repeated line is not mechanically
        // identical. The generator is threaded through every varied quantity so
        // that a given seed fixes all of them together.
        var variation = ProsodyVariation(seed: synthesisParams.seed)

        // Step 1: Predict durations for each phoneme
        var durations = predictDurations(
            transcript.phonemes,
            rate: rate,
            articulationPrecision: articulationPrecision,
            emotionalIntensity: emotionalIntensity)
        for index in durations.indices {
            durations[index] *= variation.durationScale()
        }

        // TXT-032: a boundary lengthens the last phoneme before it, by the
        // pause its strength implies and scaled by the voice's rate. Without
        // this a paragraph break reads exactly like a comma, and a chapter
        // sounds like a run-on sentence.
        Self.applyBoundaryPauses(
            to: &durations,
            transcript: transcript,
            rate: rate,
            pauseStyle: pauseStyle,
            emotionalIntensity: emotionalIntensity)

        // Step 2: Predict pitch contour
        let pitchPoints = predictPitchContour(
            transcript.phonemes,
            durations: durations,
            pitchShift: pitchShift,
            emotionalIntensity: emotionalIntensity,
            basePitch: effectiveBasePitch,
            pitchRange: effectivePitchRange
        )
        var variedPitchPoints = pitchPoints.map { point in
            (time: point.time, value: point.value * variation.pitchScale())
        }

        // TXT-032: paragraph and section breaks reset the pitch baseline.
        // Declination lowers pitch steadily through a passage; without a reset
        // a long document drifts ever downward and a new paragraph begins
        // wherever the previous one happened to end.
        Self.applyPitchResets(
            to: &variedPitchPoints,
            transcript: transcript,
            durations: durations,
            // The contour has already been transposed. Reset against the
            // equally transposed baseline or a paragraph would partially
            // erase the caller's requested semitone interval.
            basePitch: effectiveBasePitch * pow(2, pitchShift / 12))
        let pitchContour = ProsodyContour(points: variedPitchPoints, interpolation: "spline")

        // Step 3: Predict energy contour
        let energyPoints = predictEnergyContour(
            transcript.phonemes,
            durations: durations,
            emotionalIntensity: emotionalIntensity,
            breathiness: synthesisParams.breathiness
        )
        let energyContour = ProsodyContour(points: energyPoints, interpolation: "spline")

        // Step 4: Create annotated phonemes with timing
        var annotated: [AnnotatedPhoneme] = []
        var currentTime: Double = 0

        for (i, phoneme) in transcript.phonemes.enumerated() {
            let duration = durations[i]
            let timing = TimingInfo(startTime: currentTime, endTime: currentTime + duration)

            let f0 = pitchContour.valueAt(currentTime + duration / 2) ?? effectiveBasePitch
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
    /// Lengthens the phoneme preceding each boundary by its pause (TXT-032).
    static func applyBoundaryPauses(
        to durations: inout [Double],
        transcript: PhoneticTranscription,
        rate: Double,
        pauseStyle: VoicePauseStyle = VoicePauseStyle(),
        emotionalIntensity: Double = 0
    ) {
        guard !transcript.phraseBoundaries.isEmpty else { return }
        let wordStarts = transcript.wordBoundaries

        for (wordIndex, boundary) in transcript.phraseBoundaries {
            guard wordIndex < wordStarts.count else { continue }

            // The last phoneme of that word is the one before the next word
            // begins, or the final phoneme of the utterance.
            let end = wordIndex + 1 < wordStarts.count
                ? wordStarts[wordIndex + 1]
                : durations.count
            let last = end - 1
            guard last >= 0, last < durations.count else { continue }

            // Pauses shorten as speech speeds up, as they do in natural speech.
            let voiceMultiplier: Double
            switch boundary {
            case .minor:
                voiceMultiplier = pauseStyle.comma
            case .major:
                voiceMultiplier = pauseStyle.period
            case .paragraph, .section:
                voiceMultiplier = pauseStyle.paragraph
            }
            // Strong emotion tightens small pauses while preserving structural
            // paragraph/section space. This makes intensity affect phrasing,
            // not merely pitch and gain (PRO-003).
            let expressionMultiplier = boundary < .paragraph
                ? 1 - min(1, max(0, emotionalIntensity)) * 0.12
                : 1
            durations[last] += boundary.nominalPauseMs
                * voiceMultiplier
                * expressionMultiplier
                / max(0.1, rate)
        }
    }

    /// Restores the pitch baseline at structural breaks (TXT-032).
    static func applyPitchResets(
        to points: inout [(time: Double, value: Double)],
        transcript: PhoneticTranscription,
        durations: [Double],
        basePitch: Double
    ) {
        let resets = transcript.phraseBoundaries.filter { $0.value.resetsPitch }
        guard !resets.isEmpty, !points.isEmpty else { return }

        // Convert each resetting boundary to a time offset.
        let wordStarts = transcript.wordBoundaries
        var resetTimes: [Double] = []
        for (wordIndex, _) in resets {
            guard wordIndex < wordStarts.count else { continue }
            let end = wordIndex + 1 < wordStarts.count ? wordStarts[wordIndex + 1] : durations.count
            let elapsed = durations.prefix(max(0, end)).reduce(0, +)
            resetTimes.append(elapsed)
        }
        guard !resetTimes.isEmpty else { return }
        resetTimes.sort()

        // After each reset the contour returns to the voice's baseline, so
        // declination starts again rather than continuing to fall.
        for index in points.indices {
            guard let mostRecent = resetTimes.last(where: { $0 <= points[index].time }) else {
                continue
            }
            _ = mostRecent
            let drift = points[index].value - basePitch
            points[index].value = basePitch + drift * 0.5
        }
    }

    private func predictDurations(
        _ phonemes: [Phoneme],
        rate: Double,
        articulationPrecision: Double,
        emotionalIntensity: Double
    ) -> [Double] {
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

                // More precise articulation preserves additional consonant
                // closure/release time; a softer profile shortens it slightly.
                duration *= 0.85 + min(1, max(0, articulationPrecision)) * 0.3
            }

            // Expressive delivery introduces small, bounded tempo movement.
            // The caller's explicit rate remains the dominant control.
            duration *= 1 - min(1, max(0, emotionalIntensity)) * 0.04

            durations.append(max(10, min(500, duration)))
        }

        return durations
    }

    /// Predicts pitch contour based on stress, emotion, and phrase structure.
    private func predictPitchContour(
        _ phonemes: [Phoneme],
        durations: [Double],
        pitchShift: Double,
        emotionalIntensity: Double,
        basePitch: Double,
        pitchRange: (min: Double, max: Double)
    ) -> [(time: Double, value: Double)] {
        var contour: [(time: Double, value: Double)] = []
        var currentTime: Double = 0

        // A semitone is a frequency ratio, not a fixed number of hertz. Apply
        // the ratio to the completed contour so stress, emotion, declination,
        // and phrase-final movement transpose with the requested interval too.
        let pitchRatio = pow(2, pitchShift / 12)

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

            f0 *= pitchRatio
            f0 = max(pitchRange.min, min(pitchRange.max, f0))

            if phoneme.isVowel {
                contour.append((time: midpoint, value: f0))
            }

            currentTime += duration
        }

        // Ensure we have at least start and end points
        if contour.isEmpty {
            let startPitch = max(pitchRange.min, min(pitchRange.max, basePitch * pitchRatio))
            let endPitch = max(
                pitchRange.min,
                min(pitchRange.max, (basePitch - 15) * pitchRatio))
            contour.append((time: 0, value: startPitch))
            contour.append((time: currentTime, value: endPitch))
        }

        return contour
    }

    /// Predicts energy (loudness) contour.
    private func predictEnergyContour(
        _ phonemes: [Phoneme],
        durations: [Double],
        emotionalIntensity: Double,
        breathiness: Double
    ) -> [(time: Double, value: Double)] {
        var contour: [(time: Double, value: Double)] = []
        var currentTime: Double = 0

        // Base energy
        let boundedBreathiness = min(1, max(0, breathiness))
        let baseEnergy = -20.0 + emotionalIntensity * 10.0 - boundedBreathiness * 2.5

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
