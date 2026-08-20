import Foundation

/// Normalizes text for text-to-speech synthesis.
///
/// Handles numbers, abbreviations, currency, acronyms, and other special text formats.
public struct TextNormalizer: Sendable {
    /// Common abbreviations and their expansions.
    private static let abbreviations: [String: String] = [
        "mr.": "mister",
        "mrs.": "misses",
        "ms.": "miss",
        "dr.": "doctor",
        "prof.": "professor",
        "sr.": "senior",
        "jr.": "junior",
        "st.": "street",
        "ave.": "avenue",
        "blvd.": "boulevard",
        "etc.": "et cetera",
        "i.e.": "that is",
        "e.g.": "for example",
        "vs.": "versus",
        "inc.": "incorporated",
        "ltd.": "limited",
        "co.": "company",
    ]

    /// Common contractions and their expansions.
    private static let contractions: [String: String] = [
        "don't": "do not",
        "doesn't": "does not",
        "didn't": "did not",
        "won't": "will not",
        "wouldn't": "would not",
        "can't": "cannot",
        "couldn't": "could not",
        "shouldn't": "should not",
        "isn't": "is not",
        "aren't": "are not",
        "wasn't": "was not",
        "weren't": "were not",
        "hasn't": "has not",
        "haven't": "have not",
        "hadn't": "had not",
        "i'm": "i am",
        "you're": "you are",
        "he's": "he is",
        "she's": "she is",
        "it's": "it is",
        "we're": "we are",
        "they're": "they are",
        "i've": "i have",
        "you've": "you have",
        "we've": "we have",
        "they've": "they have",
        "i'll": "i will",
        "you'll": "you will",
        "he'll": "he will",
        "she'll": "she will",
        "we'll": "we will",
        "they'll": "they will",
        "d'": "of",
    ]

    /// Number words for 0-19.
    private static let numberWords = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen",
    ]

    /// Words for the tens place (index 2 == "twenty", index 9 == "ninety").
    private static let tensWords = [
        "", "", "twenty", "thirty", "forty",
        "fifty", "sixty", "seventy", "eighty", "ninety",
    ]

    /// Scale words for large numbers.
    ///
    /// Typed as `Int64` because `Int` is 32 bits on watchOS (arm64_32), where
    /// the trillion literal would not fit.
    private static let scaleWords: [(Int64, String)] = [
        (1_000_000_000_000, "trillion"),
        (1_000_000_000, "billion"),
        (1_000_000, "million"),
        (1000, "thousand"),
        (100, "hundred"),
    ]

    // MARK: - Cached Regex Patterns
    private static let dollarRegex = try! NSRegularExpression(pattern: #"\$(\d+(?:\.\d{2})?)"#)
    private static let multiSpaceRegex = try! NSRegularExpression(pattern: " +")
    private static let hyphenRegex = try! NSRegularExpression(pattern: "([a-z])-([a-z])")
    private static let multiPunctuationRegex = try! NSRegularExpression(pattern: "[.!?]{2,}")

    public init() {}

    /// Normalizes text for synthesis, expanding numbers, abbreviations, etc.
    public func normalize(_ text: String) -> String {
        var result = text.lowercased()

        // Expand contractions and abbreviations
        result = expandDictionary(result, Self.contractions)

        // Currency must expand before bare numbers, otherwise "$50" becomes
        // "$fifty" and the currency pattern no longer matches.
        result = expandCurrency(result)
        result = expandNumbers(result)
        result = expandDictionary(result, Self.abbreviations)

        result = cleanPunctuation(result)

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Expands a dictionary of text replacements.
    private func expandDictionary(_ text: String, _ expansions: [String: String]) -> String {
        var result = text
        for (original, replacement) in expansions {
            result = result.replacingOccurrences(
                of: original,
                with: replacement,
                options: .caseInsensitive
            )
        }
        return result
    }

    /// Expands numbers to words (e.g., "123" → "one hundred twenty three").
    private func expandNumbers(_ text: String) -> String {
        var result = ""
        var currentNumber = ""

        for char in text {
            if char.isNumber {
                currentNumber.append(char)
            } else {
                if !currentNumber.isEmpty {
                    result += numberToWords(currentNumber)
                    currentNumber = ""
                }
                result.append(char)
            }
        }

        if !currentNumber.isEmpty {
            result += numberToWords(currentNumber)
        }

        return result
    }

    /// Converts a numeric string to English words.
    private func numberToWords(_ numStr: String) -> String {
        guard let num = Int64(numStr), num >= 0 else { return numStr }

        if num == 0 { return "zero" }

        var parts: [String] = []
        var remaining = num

        for (scale, scaleWord) in Self.scaleWords {
            if remaining >= scale {
                let quotient = remaining / scale
                remaining = remaining % scale

                if scale == 100 {
                    parts.append("\(wordsBelowHundred(quotient)) \(scaleWord)")
                } else {
                    parts.append(
                        "\(numberToWords(String(quotient))) \(scaleWord)"
                    )
                }
            }
        }

        if remaining > 0 {
            parts.append(wordsBelowHundred(remaining))
        }

        return parts.joined(separator: " ")
    }

    /// Converts a value in 0..<100 to words, e.g. 50 -> "fifty", 42 -> "forty two".
    private func wordsBelowHundred(_ n: Int64) -> String {
        guard n > 0 else { return Self.numberWords[0] }
        if n < Int64(Self.numberWords.count) { return Self.numberWords[Int(n)] }

        let tens = Int(n / 10)
        let ones = Int(n % 10)
        guard tens < Self.tensWords.count else { return String(n) }

        let tensWord = Self.tensWords[tens]
        return ones == 0 ? tensWord : "\(tensWord) \(Self.numberWords[ones])"
    }

    /// Expands currency notation (e.g., "$50" → "fifty dollars").
    private func expandCurrency(_ text: String) -> String {
        var result = text
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = Self.dollarRegex.matches(in: result, range: range)

        for match in matches.reversed() {
            if let matchRange = Range(match.range(at: 1), in: result) {
                let numberStr = String(result[matchRange])
                let expanded = numberToWords(numberStr) + " dollars"
                if let fullRange = Range(match.range, in: result) {
                    result.replaceSubrange(fullRange, with: expanded)
                }
            }
        }

        return result
    }

    /// Cleans and normalizes punctuation.
    private func cleanPunctuation(_ text: String) -> String {
        var result = text
        let range = NSRange(result.startIndex..<result.endIndex, in: result)

        // Replace multiple spaces with single space
        result = Self.multiSpaceRegex.stringByReplacingMatches(
            in: result,
            range: range,
            withTemplate: " "
        )

        // Remove hyphens between letters (e-mail → email)
        var rangeAfterFirst = NSRange(result.startIndex..<result.endIndex, in: result)
        result = Self.hyphenRegex.stringByReplacingMatches(
            in: result,
            range: rangeAfterFirst,
            withTemplate: "$1$2"
        )

        // Keep sentence-ending punctuation but handle multiple
        rangeAfterFirst = NSRange(result.startIndex..<result.endIndex, in: result)
        result = Self.multiPunctuationRegex.stringByReplacingMatches(
            in: result,
            range: rangeAfterFirst,
            withTemplate: "."
        )

        return result
    }
}
