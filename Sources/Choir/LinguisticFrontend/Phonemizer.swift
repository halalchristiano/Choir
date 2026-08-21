import Foundation

/// Converts graphemes (letters) to phonemes (sounds) for English text.
///
/// Uses a dictionary-based approach with grapheme-to-phoneme (G2P) rules as fallback.
public struct Phonemizer: Sendable {
    /// A dictionary of known word pronunciations (simplified CMU-like format).
    private let pronunciationDictionary: [String: [Phoneme]]

    /// Runtime overrides registered by the consuming app (SRS TXT-022).
    ///
    /// A snapshot rather than the actor itself, because phonemization is
    /// synchronous and runs per word.
    private let userLexicon: UserLexiconSnapshot

    /// The 135,000-entry built-in lexicon (SRS TXT-020), or `nil` to rely on
    /// the compact dictionary and G2P rules alone.
    private let builtInLexicon: BuiltInLexicon?

    /// Heteronym disambiguation (SRS TXT-021).
    private let heteronyms = HeteronymResolver()

    public init(
        dictionary: [String: [Phoneme]]? = nil,
        userLexicon: UserLexiconSnapshot = .empty,
        builtInLexicon: BuiltInLexicon? = .shared
    ) {
        self.pronunciationDictionary = dictionary ?? Phonemizer.defaultDictionary
        self.userLexicon = userLexicon
        self.builtInLexicon = builtInLexicon
    }

    /// Returns a copy of this phonemizer using `lexicon` for overrides.
    public func withUserLexicon(_ lexicon: UserLexiconSnapshot) -> Phonemizer {
        Phonemizer(
            dictionary: pronunciationDictionary,
            userLexicon: lexicon,
            builtInLexicon: builtInLexicon
        )
    }

    /// Converts a word to its phonetic transcription.
    ///
    /// - Parameter word: The word to phonemize (case-insensitive).
    /// - Returns: An array of phonemes representing the word.
    public func phonemize(_ word: String) -> [Phoneme] {
        phonemize(word, partOfSpeech: .unknown)
    }

    /// Converts a word to phonemes, using part of speech to disambiguate
    /// heteronyms (SRS TXT-021).
    ///
    /// Resolution order, highest precedence first:
    ///
    /// 1. the app's user lexicon (TXT-022),
    /// 2. heteronym readings when the part of speech is known (TXT-021),
    /// 3. the built-in 135,000-entry lexicon (TXT-020),
    /// 4. the compact fallback dictionary,
    /// 5. rule-based grapheme-to-phoneme conversion.
    public func phonemize(_ word: String, partOfSpeech: PartOfSpeech) -> [Phoneme] {
        let normalized = word.lowercased()
            .trimmingCharacters(in: .punctuationCharacters)

        guard !normalized.isEmpty else { return [] }

        // TXT-022: user registrations take precedence over the built-in lexicon.
        if let override = userLexicon.pronunciation(for: normalized) {
            switch override {
            case .phonemes(let symbols):
                return symbols.map { Phoneme($0) }
            case .respelling(let respelling):
                // Phonemize the respelling by the normal rules. Syllables are
                // written whitespace-separated, so each is converted and the
                // results concatenated.
                return respelling
                    .lowercased()
                    .split(whereSeparator: \.isWhitespace)
                    .flatMap { graphemeToPhonemeRules(String($0)) }
            }
        }

        // TXT-021: a known part of speech settles heteronyms before any
        // lexicon is consulted, because the lexicon holds only one reading.
        if partOfSpeech != .unknown,
           let disambiguated = heteronyms.phonemes(for: normalized, partOfSpeech: partOfSpeech) {
            return disambiguated
        }

        // TXT-020: the built-in lexicon.
        if let phonemes = builtInLexicon?.phonemes(for: normalized), !phonemes.isEmpty {
            return phonemes
        }

        // Compact fallback dictionary
        if let phonemes = pronunciationDictionary[normalized] {
            return phonemes
        }

        // Fall back to rule-based G2P
        return graphemeToPhonemeRules(normalized)
    }

    /// Applies grapheme-to-phoneme conversion rules for unknown words.
    private func graphemeToPhonemeRules(_ word: String) -> [Phoneme] {
        var phonemes: [Phoneme] = []
        let chars = Array(word)
        var i = 0

        while i < chars.count {
            let char = chars[i]
            let nextChar = i + 1 < chars.count ? chars[i + 1] : nil

            // Vowels
            if isCharVowel(char) {
                if char == "a" {
                    if nextChar == "i" {
                        phonemes.append(Phoneme("aɪ"))
                        i += 2
                        continue
                    } else if nextChar == "u" {
                        phonemes.append(Phoneme("ɔ"))
                        i += 2
                        continue
                    }
                    phonemes.append(Phoneme(isVowelLong(chars, at: i) ? "eɪ" : "æ"))
                } else if char == "e" {
                    if nextChar == "y" {
                        phonemes.append(Phoneme("iː"))
                        i += 2
                        continue
                    }
                    phonemes.append(Phoneme(isVowelLong(chars, at: i) ? "iː" : "ɛ"))
                } else if char == "i" {
                    phonemes.append(Phoneme(isVowelLong(chars, at: i) ? "iː" : "ɪ"))
                } else if char == "o" {
                    if nextChar == "i" {
                        phonemes.append(Phoneme("ɔɪ"))
                        i += 2
                        continue
                    }
                    phonemes.append(Phoneme(isVowelLong(chars, at: i) ? "oʊ" : "ɑ"))
                } else if char == "u" {
                    phonemes.append(Phoneme(isVowelLong(chars, at: i) ? "uː" : "ʊ"))
                } else if char == "y" {
                    phonemes.append(Phoneme(i == 0 ? "j" : "ɪ"))
                }
                i += 1
            }
            // Consonant digraphs
            else if char == "c" && nextChar == "h" {
                phonemes.append(Phoneme("tʃ"))
                i += 2
            } else if char == "s" && nextChar == "h" {
                phonemes.append(Phoneme("ʃ"))
                i += 2
            } else if char == "t" && nextChar == "h" {
                phonemes.append(Phoneme("θ"))
                i += 2
            } else if char == "d" && nextChar == "h" {
                phonemes.append(Phoneme("ð"))
                i += 2
            } else if char == "z" && nextChar == "h" {
                phonemes.append(Phoneme("ʒ"))
                i += 2
            } else if char == "n" && nextChar == "g" {
                phonemes.append(Phoneme("ŋ"))
                i += 2
            } else if char == "j" {
                phonemes.append(Phoneme("dʒ"))
                i += 1
            }
            // Single consonants
            else if let phoneme = consonantPhoneme(char) {
                phonemes.append(Phoneme(phoneme))
                i += 1
            } else {
                i += 1
            }
        }

        return phonemes
    }

    /// Determines if a vowel should be pronounced as a long vowel.
    /// Whether the vowel at `index` is realized long.
    ///
    /// Takes the caller's existing character array rather than a `String`.
    /// Rebuilding `Array(word)` here made the function O(n) per call, and it is
    /// called once per vowel, so grapheme-to-phoneme conversion was O(n^2) in
    /// word length — a 100,000-character word (which TXT-002 requires the
    /// engine to survive) meant on the order of 10^10 character copies.
    private func isVowelLong(_ chars: [Character], at index: Int) -> Bool {

        // Vowel at end of word is often long
        if index == chars.count - 1 {
            return true
        }

        // Vowel followed by silent 'e'
        if index + 1 < chars.count && chars[index + 1] == "e" {
            if index + 2 >= chars.count {
                return true
            }
        }

        // Vowel followed by single consonant and vowel (open syllable)
        if index + 2 < chars.count {
            let nextChar = chars[index + 1]
            let nextNextChar = chars[index + 2]
            if !isCharVowel(nextChar) && isCharVowel(nextNextChar) {
                return true
            }
        }

        return false
    }

    /// Maps a consonant character to its phoneme.
    private func consonantPhoneme(_ char: Character) -> String? {
        switch char {
        case "b": return "b"
        case "c": return "k"
        case "d": return "d"
        case "f": return "f"
        // U+0261 script g, the inventory's symbol. ASCII "g" is a different
        // character and is not part of the documented inventory (TXT-024).
        case "g": return "\u{0261}"
        case "h": return "h"
        case "j": return "dʒ"
        case "k": return "k"
        case "l": return "l"
        case "m": return "m"
        case "n": return "n"
        case "p": return "p"
        case "q": return "k"
        case "r": return "r"
        // English "s" is /s/ in the great majority of positions. This
        // previously returned /z/, so every word beginning with "s" was
        // mispronounced by the fallback.
        case "s": return "s"
        case "t": return "t"
        case "v": return "v"
        case "w": return "w"
        // "x" is two phonemes; the single-symbol path cannot express it, so
        // the nearer single symbol is used rather than emitting "ks", which is
        // not an inventory symbol at all.
        case "x": return "k"
        case "z": return "z"
        default: return nil
        }
    }

    /// Checks if a character is a vowel.
    private func isCharVowel(_ char: Character) -> Bool {
        "aeiouAEIOU".contains(char)
    }

    /// Default pronunciation dictionary with common English words.
    private static let defaultDictionary: [String: [Phoneme]] = [
        "the": [Phoneme("ð"), Phoneme("ə")],
        "a": [Phoneme("ə")],
        "and": [Phoneme("æ"), Phoneme("n"), Phoneme("d")],
        "to": [Phoneme("t"), Phoneme("uː")],
        "of": [Phoneme("ə"), Phoneme("v")],
        "in": [Phoneme("ɪ"), Phoneme("n")],
        "is": [Phoneme("ɪ"), Phoneme("z")],
        "you": [Phoneme("j"), Phoneme("uː")],
        "that": [Phoneme("ð"), Phoneme("æ"), Phoneme("t")],
        "hello": [Phoneme("h"), Phoneme("ə"), Phoneme("l"), Phoneme("oʊ")],
        "world": [Phoneme("w"), Phoneme("ə"), Phoneme("l"), Phoneme("d")],
        "beautiful": [Phoneme("b"), Phoneme("j"), Phoneme("uː"), Phoneme("t"), Phoneme("ə"), Phoneme("f"), Phoneme("ə"), Phoneme("l")],
        "choir": [Phoneme("k"), Phoneme("w"), Phoneme("aɪ"), Phoneme("ə"), Phoneme("r")],
        "synthesis": [Phoneme("s"), Phoneme("ɪ"), Phoneme("n"), Phoneme("θ"), Phoneme("ə"), Phoneme("s"), Phoneme("ɪ"), Phoneme("s")],
        "voice": [Phoneme("v"), Phoneme("ɔɪ"), Phoneme("s")],
        "speech": [Phoneme("s"), Phoneme("p"), Phoneme("iː"), Phoneme("tʃ")],
        "synthesize": [Phoneme("s"), Phoneme("ɪ"), Phoneme("n"), Phoneme("θ"), Phoneme("ə"), Phoneme("s"), Phoneme("aɪ"), Phoneme("z")],
        "music": [Phoneme("m"), Phoneme("j"), Phoneme("uː"), Phoneme("z"), Phoneme("ɪ"), Phoneme("k")],
        "read": [Phoneme("r"), Phoneme("ɛ"), Phoneme("d")],
        "through": [Phoneme("θ"), Phoneme("r"), Phoneme("uː")],
        "important": [Phoneme("ɪ"), Phoneme("m"), Phoneme("p"), Phoneme("ɔ"), Phoneme("r"), Phoneme("t"), Phoneme("ə"), Phoneme("n"), Phoneme("t")],
    ]
}
