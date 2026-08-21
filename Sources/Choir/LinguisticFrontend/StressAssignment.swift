import Foundation

/// Assigns stress patterns to words based on linguistic rules.
///
/// Determines primary stress (ˈ) and secondary stress (ˌ) for multi-syllable words.
public struct StressAssigner: Sendable {
    /// Stress patterns for known words (primary stress index).
    private let stressPatterns: [String: [Int]]

    public init(patterns: [String: [Int]]? = nil) {
        let source = patterns ?? StressAssigner.defaultPatterns
        var normalized: [String: [Int]] = [:]

        // Sorting makes collisions such as "Word" and "word!" resolve the
        // same way on every platform after their keys are normalized.
        for key in source.keys.sorted() {
            guard let pattern = source[key], !pattern.isEmpty else { continue }
            let normalizedKey = Self.normalizedWord(key)
            guard !normalizedKey.isEmpty, normalized[normalizedKey] == nil else { continue }
            normalized[normalizedKey] = pattern.map { min(2, max(0, $0)) }
        }
        self.stressPatterns = normalized
    }

    /// Returns the sanitized syllable pattern that would be used for `word`.
    public func stressPattern(for word: String) -> [Int]? {
        stressPatterns[Self.normalizedWord(word)]
    }

    /// Assigns stress to phonemes in a word.
    ///
    /// - Parameters:
    ///   - phonemes: The phonemes of the word.
    ///   - word: The original word (for dictionary lookup).
    /// - Returns: The phonemes with stress annotations.
    public func assignStress(to phonemes: [Phoneme], for word: String) -> [Phoneme] {
        guard !phonemes.isEmpty else { return phonemes }

        // Stress is a property of vowel nuclei. Repair annotations supplied
        // on consonants even when an authoritative vowel stress is preserved.
        var sanitized = phonemes
        for index in sanitized.indices where !sanitized[index].isVowel {
            sanitized[index].stress = 0
        }

        // TXT-020: phonemes from the built-in lexicon already carry CMUdict's
        // primary and secondary stress, which is more reliable than any rule
        // here. Overwriting it discarded the very data the requirement exists
        // to supply.
        if sanitized.contains(where: { $0.isVowel && $0.stress > 0 }) {
            return sanitized
        }

        // Try dictionary lookup first
        if let stressIndices = stressPattern(for: word) {
            return applyStressPattern(sanitized, stressIndices: stressIndices)
        }

        // Fall back to rule-based stress assignment
        return assignStressByRules(sanitized)
    }

    /// Applies a known stress pattern to phonemes.
    private func applyStressPattern(_ phonemes: [Phoneme], stressIndices: [Int]) -> [Phoneme] {
        var result = phonemes
        var vowelIndex = 0

        for index in result.indices {
            guard result[index].isVowel else {
                result[index].stress = 0
                continue
            }
            result[index].stress = vowelIndex < stressIndices.count
                ? stressIndices[vowelIndex]
                : 0
            vowelIndex += 1
        }

        return result
    }

    /// Assigns stress based on linguistic rules for unknown words.
    private func assignStressByRules(_ phonemes: [Phoneme]) -> [Phoneme] {
        var result = phonemes
        var assignedPrimary = false
        for index in result.indices {
            if result[index].isVowel {
                result[index].stress = assignedPrimary ? 0 : 1
                assignedPrimary = true
            } else {
                result[index].stress = 0
            }
        }
        return result
    }

    private static func normalizedWord(_ word: String) -> String {
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return word.trimmingCharacters(in: trimSet).lowercased()
    }

    /// Default stress patterns for common English words (vowel nucleus → stress level).
    static let defaultPatterns: [String: [Int]] = [
        "hello": [0, 1],  // hel-LO
        "beautiful": [1, 0, 0],  // BEAU-ti-ful
        "important": [0, 1, 0],  // im-POR-tant
        "computer": [0, 1, 0],  // com-PU-ter
        "imagine": [0, 1, 0],  // i-MAG-ine
        "photography": [0, 1, 0, 0],  // pho-TOG-ra-phy
        "enthusiasm": [0, 1, 0, 0, 0],  // en-THU-si-asm
        "chocolate": [1, 0, 0],  // CHOC-o-late
        "cathedral": [0, 1, 0],  // ca-THE-dral
        "butterfly": [1, 0, 0],  // BUT-ter-fly
        "elephant": [1, 0, 0],  // EL-e-phant
        "energy": [1, 0, 0],  // EN-er-gy
        "memory": [1, 0, 0],  // MEM-o-ry
        "usually": [1, 0, 0, 0],  // U-su-al-ly
        "naturally": [1, 0, 0, 0],  // NAT-u-ral-ly
        "developing": [0, 1, 0, 0],  // de-VEL-op-ing
        "technology": [0, 1, 0, 0],  // tech-NOL-o-gy
        "personality": [0, 0, 1, 0, 0],  // per-son-AL-i-ty
        "information": [0, 0, 1, 0],  // in-for-MA-tion
        "communication": [0, 2, 0, 1, 0],  // com-mu-ni-CA-tion
    ]
}
