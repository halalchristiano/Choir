import Foundation

/// Assigns stress patterns to words based on linguistic rules.
///
/// Determines primary stress (ˈ) and secondary stress (ˌ) for multi-syllable words.
public struct StressAssigner: Sendable {
    /// Stress patterns for known words (primary stress index).
    private let stressPatterns: [String: [Int]]

    public init(patterns: [String: [Int]]? = nil) {
        self.stressPatterns = patterns ?? StressAssigner.defaultPatterns
    }

    /// Assigns stress to phonemes in a word.
    ///
    /// - Parameters:
    ///   - phonemes: The phonemes of the word.
    ///   - word: The original word (for dictionary lookup).
    /// - Returns: The phonemes with stress annotations.
    public func assignStress(to phonemes: [Phoneme], for word: String) -> [Phoneme] {
        guard !phonemes.isEmpty else { return phonemes }

        // Try dictionary lookup first
        let normalized = word.lowercased()
        if let stressIndices = stressPatterns[normalized] {
            return applyStressPattern(phonemes, stressIndices: stressIndices)
        }

        // Fall back to rule-based stress assignment
        return assignStressByRules(phonemes, word: word)
    }

    /// Applies a known stress pattern to phonemes.
    private func applyStressPattern(_ phonemes: [Phoneme], stressIndices: [Int]) -> [Phoneme] {
        var result = phonemes

        for (index, stress) in stressIndices.enumerated() {
            if index < result.count {
                result[index].stress = stress
            }
        }

        return result
    }

    /// Assigns stress based on linguistic rules for unknown words.
    private func assignStressByRules(_ phonemes: [Phoneme], word: String) -> [Phoneme] {
        var result = phonemes
        let syllables = splitIntoSyllables(phonemes)

        guard !syllables.isEmpty else { return result }

        // Simple rule: stress first syllable (can be overridden by patterns)
        var phoneticIndex = 0
        for (syllableIndex, syllable) in syllables.enumerated() {
            let stress = syllableIndex == 0 ? 1 : 0

            for _ in 0..<syllable.count {
                if phoneticIndex < result.count {
                    result[phoneticIndex].stress = stress
                    phoneticIndex += 1
                }
            }
        }

        return result
    }

    /// Splits phonemes into syllables based on vowel nuclei.
    private func splitIntoSyllables(_ phonemes: [Phoneme]) -> [[Phoneme]] {
        var syllables: [[Phoneme]] = []
        var currentSyllable: [Phoneme] = []

        for phoneme in phonemes {
            currentSyllable.append(phoneme)

            // Syllable typically ends with or after a vowel
            if phoneme.isVowel {
                syllables.append(currentSyllable)
                currentSyllable = []
            }
        }

        if !currentSyllable.isEmpty {
            if !syllables.isEmpty {
                syllables[syllables.count - 1].append(contentsOf: currentSyllable)
            } else {
                syllables.append(currentSyllable)
            }
        }

        return syllables.filter { !$0.isEmpty }
    }

    /// Default stress patterns for common English words (phoneme index → stress level).
    static let defaultPatterns: [String: [Int]] = [
        "hello": [1, 0],  // HEL-lo
        "beautiful": [1, 0, 0, 0],  // BEAU-ti-ful
        "important": [0, 1, 0, 0],  // im-POR-tant
        "computer": [0, 1, 0, 0],  // com-PU-ter
        "imagine": [0, 1, 0, 0],  // i-MAG-ine
        "photography": [0, 1, 0, 0, 0],  // pho-TOG-ra-phy
        "enthusiasm": [0, 1, 0, 0, 0],  // en-THU-si-asm
        "chocolate": [1, 0, 0],  // CHOC-o-late
        "cathedral": [0, 1, 0, 0],  // ca-THRAL
        "butterfly": [1, 0, 0],  // BUT-ter-fly
        "elephant": [1, 0, 0],  // EL-e-phant
        "energy": [1, 0, 0],  // EN-er-gy
        "memory": [1, 0, 0],  // MEM-o-ry
        "usually": [1, 0, 0, 0],  // U-su-al-ly
        "naturally": [1, 0, 0, 0, 0],  // NAT-u-ral-ly
        "developing": [0, 1, 0, 0, 0],  // de-VEL-op-ing
        "technology": [0, 1, 0, 0, 0],  // tech-NOL-o-gy
        "personality": [0, 0, 1, 0, 0],  // per-son-AL-i-ty
        "information": [0, 0, 1, 0, 0],  // in-for-MA-tion
        "communication": [0, 0, 1, 0, 0, 0],  // com-mu-ni-CA-tion
    ]
}
