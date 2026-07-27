import Foundation

/// The complete linguistic processing pipeline for text-to-speech.
///
/// Handles normalization, phonemization, stress assignment, and SSML markup.
public struct LinguisticFrontend: Sendable {
    private let normalizer: TextNormalizer
    private let phonemizer: Phonemizer
    private let stressAssigner: StressAssigner
    private let ssmlParser: SSMLParser

    /// Creates a linguistic front end with default components.
    public init(
        normalizer: TextNormalizer = TextNormalizer(),
        phonemizer: Phonemizer = Phonemizer(),
        stressAssigner: StressAssigner = StressAssigner(),
        ssmlParser: SSMLParser = SSMLParser()
    ) {
        self.normalizer = normalizer
        self.phonemizer = phonemizer
        self.stressAssigner = stressAssigner
        self.ssmlParser = ssmlParser
    }

    /// Processes raw text into a phonetic transcription with prosodic annotation.
    ///
    /// - Parameter text: The input text, optionally with SSML markup.
    /// - Returns: A phonetic transcription ready for synthesis.
    /// - Throws: `ChoirError` if processing fails.
    public func process(_ text: String) throws -> PhoneticTranscription {
        guard !text.isEmpty else {
            throw ChoirError.textProcessingFailed(reason: "Input text is empty")
        }

        // Step 1: Parse SSML markup
        let segments = ssmlParser.parse(text)

        // Step 2: Normalize and phonemize each segment
        var allPhonemes: [Phoneme] = []
        var wordBoundaries: [Int] = []
        var ssmlMetadata: [(range: Range<Int>, segment: SSMLParser.SegmentTag)] = []

        for segment in segments {
            let startIndex = allPhonemes.count

            // Normalize text
            let normalizedText = normalizer.normalize(segment.text)

            // Split into words
            let words = normalizedText.split(separator: " ", omittingEmptySubsequences: true)

            for word in words {
                wordBoundaries.append(allPhonemes.count)

                let wordStr = String(word)
                let wordPhonemes = phonemizer.phonemize(wordStr)

                // Assign stress
                let stressedPhonemes = stressAssigner.assignStress(
                    to: wordPhonemes,
                    for: wordStr
                )

                // Apply SSML controls if present
                let controlledPhonemes = applySynthesisControls(
                    stressedPhonemes,
                    from: segment
                )

                allPhonemes.append(contentsOf: controlledPhonemes)
            }

            let endIndex = allPhonemes.count
            if startIndex < endIndex {
                ssmlMetadata.append((startIndex..<endIndex, segment))
            }
        }

        guard !allPhonemes.isEmpty else {
            throw ChoirError.textProcessingFailed(reason: "No phonemes generated from input")
        }

        return PhoneticTranscription(
            phonemes: allPhonemes,
            originalText: text,
            wordBoundaries: wordBoundaries
        )
    }

    /// Applies SSML-based synthesis controls to phonemes.
    private func applySynthesisControls(
        _ phonemes: [Phoneme],
        from segment: SSMLParser.SegmentTag
    ) -> [Phoneme] {
        var result = phonemes

        // Apply emphasis/stress modification
        if let emphasis = segment.emphasis {
            switch emphasis.lowercased() {
            case "strong":
                // Enhance stress on primary vowels
                result = enhanceStress(result, level: 2)
            case "moderate":
                result = enhanceStress(result, level: 1)
            case "reduced":
                // Reduce stress
                result = result.map { var p = $0; p.stress = 0; return p }
            default:
                break
            }
        }

        return result
    }

    /// Enhances stress on vowels in phoneme sequence.
    private func enhanceStress(_ phonemes: [Phoneme], level: Int) -> [Phoneme] {
        return phonemes.map { phoneme in
            var enhanced = phoneme
            if phoneme.isVowel && enhanced.stress == 0 {
                enhanced.stress = min(level, 2)
            }
            return enhanced
        }
    }

    /// Validates that text is suitable for synthesis.
    ///
    /// - Throws: `ChoirError` if text fails validation.
    private func validateText(_ text: String) throws {
        guard !text.isEmpty else {
            throw ChoirError.invalidParameter(
                parameter: "text",
                reason: "Text cannot be empty"
            )
        }

        guard text.count <= 5000 else {
            throw ChoirError.invalidParameter(
                parameter: "text",
                reason: "Text exceeds maximum length of 5000 characters"
            )
        }

        // Check for suspicious patterns (null bytes, etc)
        let nullBytes = text.filter { $0.unicodeScalars.allSatisfy { $0.value == 0 } }
        guard nullBytes.isEmpty else {
            throw ChoirError.textProcessingFailed(
                reason: "Text contains null bytes"
            )
        }
    }
}
