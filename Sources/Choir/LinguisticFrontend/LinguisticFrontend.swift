import Foundation

/// The complete linguistic processing pipeline for text-to-speech.
///
/// Handles normalization, phonemization, stress assignment, and SSML markup.
public struct LinguisticFrontend: Sendable {
    private let normalizer: TextNormalizer
    private let phonemizer: Phonemizer
    private let stressAssigner: StressAssigner
    private let ssmlParser: SSMLCParser

    /// Creates a linguistic front end with default components.
    public init(
        normalizer: TextNormalizer = TextNormalizer(),
        phonemizer: Phonemizer = Phonemizer(),
        stressAssigner: StressAssigner = StressAssigner(),
        ssmlParser: SSMLCParser = SSMLCParser()
    ) {
        self.normalizer = normalizer
        self.phonemizer = phonemizer
        self.stressAssigner = stressAssigner
        self.ssmlParser = ssmlParser
    }

    /// Returns a copy of this front end whose phonemizer honours `lexicon`
    /// (SRS TXT-022).
    public func withUserLexicon(_ lexicon: UserLexiconSnapshot) -> LinguisticFrontend {
        LinguisticFrontend(
            normalizer: normalizer,
            phonemizer: phonemizer.withUserLexicon(lexicon),
            stressAssigner: stressAssigner,
            ssmlParser: ssmlParser
        )
    }

    /// Processes input whose interpretation the caller has stated (TXT-003).
    ///
    /// The engine never infers the mode. `.plainText` speaks markup characters
    /// literally, `.markup` parses them, and `.phonemes` bypasses the front end
    /// entirely (TXT-050).
    public func process(_ input: SynthesisInput) throws -> PhoneticTranscription {
        guard !input.isEmpty else {
            throw ChoirError.textProcessingFailed(reason: "Input is empty")
        }

        switch input {
        case .markup(let text):
            return try process(text)

        case .plainText(let text):
            // Escape markup characters so the parser cannot claim them, which
            // is what distinguishes this mode from .markup.
            let escaped = text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return try process(escaped)

        case .phonemes(let phonemes):
            let unknown = input.unknownPhonemeSymbols
            guard unknown.isEmpty else {
                throw ChoirError.textProcessingFailed(
                    reason: "Phonemes outside the documented inventory: \(unknown.joined(separator: ", "))")
            }
            return PhoneticTranscription(
                phonemes: phonemes,
                originalText: phonemes.map(\.symbol).joined(),
                wordBoundaries: [0],
                wordTexts: [phonemes.map(\.symbol).joined()]
            )
        }
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

        // TXT-013: ALL-CAPS words become emphasis. This must happen *before*
        // markup parsing, not during normalization: normalization runs per
        // segment after parsing, so markup introduced there would never be
        // parsed and would be spoken aloud as the words "emphasis level
        // strong".
        let prepared = normalizer.policy.treatsAllCapsAsEmphasis
            ? normalizer.markAllCapsEmphasis(text)
            : text

        // Step 1: Parse SSML-C markup (TXT-040). Non-strict, so malformed
        // markup degrades and its warnings surface in the result rather than
        // failing the request (TXT-041).
        let parsed = (try? ssmlParser.parse(prepared)) ?? SSMLParseResult(events: [])
        let segments: [(text: String, style: SSMLStyle)] = parsed.events.compactMap { event in
            if case .speech(let segmentText, let style) = event { return (segmentText, style) }
            return nil
        }

        // Step 2: Normalize and phonemize each segment
        var allPhonemes: [Phoneme] = []
        var wordBoundaries: [Int] = []
        var wordTexts: [String] = []
        var segmentStyles: [(range: Range<Int>, style: SSMLStyle)] = []

        for segment in segments {
            let startIndex = allPhonemes.count

            // TXT-040: <say-as> selects how the segment is read.
            let policyForSegment = Self.policy(for: segment.style, base: normalizer.policy)
            let segmentNormalizer = policyForSegment == normalizer.policy
                ? normalizer
                : TextNormalizer(policy: policyForSegment)

            let normalizedText = segmentNormalizer.normalize(segment.text)

            // Split into words
            let words = normalizedText.split(separator: " ", omittingEmptySubsequences: true)

            for word in words {
                wordBoundaries.append(allPhonemes.count)

                let wordStr = String(word)
                wordTexts.append(wordStr)

                // TXT-040: <phoneme ph="..."> overrides pronunciation for the
                // words it encloses.
                let wordPhonemes: [Phoneme]
                if let override = segment.style.phonemeOverride {
                    wordPhonemes = phonemizer.phonemize(override)
                } else {
                    wordPhonemes = phonemizer.phonemize(wordStr)
                }

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
                segmentStyles.append((startIndex..<endIndex, segment.style))
            }
        }

        guard !allPhonemes.isEmpty else {
            throw ChoirError.textProcessingFailed(reason: "No phonemes generated from input")
        }

        return PhoneticTranscription(
            phonemes: allPhonemes,
            originalText: text,
            wordBoundaries: wordBoundaries,
            wordTexts: wordTexts
        )
    }

    /// Applies SSML-based synthesis controls to phonemes.
    private func applySynthesisControls(
        _ phonemes: [Phoneme],
        from segment: (text: String, style: SSMLStyle)
    ) -> [Phoneme] {
        switch segment.style.emphasis {
        case .strong:
            return enhanceStress(phonemes, level: 2)
        case .moderate:
            return enhanceStress(phonemes, level: 1)
        case .reduced:
            return phonemes.map { var p = $0; p.stress = 0; return p }
        case .none:
            return phonemes
        }
    }

    /// Derives the normalization policy a `<say-as>` segment requires.
    ///
    /// `interpret-as="characters"` and `"number"` change how the same digits
    /// are read, so they are expressed as a policy rather than a special case
    /// inside the normalizer.
    static func policy(for style: SSMLStyle, base: NormalizationPolicy) -> NormalizationPolicy {
        guard let interpretAs = style.interpretAs else { return base }
        var policy = base
        switch interpretAs {
        case .scripture:
            policy.expandsScriptureReferences = true
        case .characters:
            // Spoken letter by letter: suppress the expansions that would
            // group digits into words.
            policy.verbatim = true
        case .number, .ordinal, .date:
            policy.expandsScriptureReferences = false
        }
        return policy
    }

    /// Enhances stress on vowels in phoneme sequence.
    /// Raises stress on the vowels of an emphasised run.
    ///
    /// Adds to the existing level rather than only filling zeros: with the
    /// built-in lexicon supplying stress, most vowels arrive already marked,
    /// and a fill-only rule made emphasis a no-op on exactly the words that
    /// carry the sentence.
    private func enhanceStress(_ phonemes: [Phoneme], level: Int) -> [Phoneme] {
        phonemes.map { phoneme in
            guard phoneme.isVowel else { return phoneme }
            var enhanced = phoneme
            enhanced.stress = min(2, phoneme.stress + level)
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
