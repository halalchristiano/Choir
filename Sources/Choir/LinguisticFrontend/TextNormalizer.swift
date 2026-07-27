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

    /// Scale words for large numbers.
    private static let scaleWords = [
        (1_000_000_000_000, "trillion"),
        (1_000_000_000, "billion"),
        (1_000_000, "million"),
        (1000, "thousand"),
        (100, "hundred"),
    ]

    public init() {}

    /// Normalizes text for synthesis, expanding numbers, abbreviations, etc.
    public func normalize(_ text: String) -> String {
        var result = text.lowercased()

        // Expand contractions
        for (contraction, expansion) in Self.contractions {
            result = result.replacingOccurrences(
                of: contraction,
                with: expansion,
                options: .caseInsensitive
            )
        }

        // Process numbers (basic: 123 → "one hundred twenty three")
        result = expandNumbers(result)

        // Expand abbreviations
        for (abbr, expansion) in Self.abbreviations {
            result = result.replacingOccurrences(
                of: abbr,
                with: expansion,
                options: .caseInsensitive
            )
        }

        // Handle currency (basic: $50 → "fifty dollars")
        result = expandCurrency(result)

        // Remove or replace problematic punctuation
        result = cleanPunctuation(result)

        return result.trimmingCharacters(in: .whitespaces)
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
        guard let num = Int(numStr), num >= 0 else { return numStr }

        if num == 0 { return "zero" }

        var parts: [String] = []
        var remaining = num

        for (scale, scaleWord) in Self.scaleWords {
            if remaining >= scale {
                let quotient = remaining / scale
                remaining = remaining % scale

                if scale == 100 {
                    parts.append("\(Self.numberWords[quotient]) \(scaleWord)")
                } else {
                    parts.append(
                        "\(numberToWords(String(quotient))) \(scaleWord)"
                    )
                }
            }
        }

        if remaining > 0 {
            parts.append(Self.numberWords[remaining])
        }

        return parts.joined(separator: " ")
    }

    /// Expands currency notation (e.g., "$50" → "fifty dollars").
    private func expandCurrency(_ text: String) -> String {
        var result = text

        // Dollar amounts: $50 → fifty dollars
        let dollarPattern = #"\$(\d+(?:\.\d{2})?)"#
        if let regex = try? NSRegularExpression(pattern: dollarPattern) {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, range: range)

            for match in matches.reversed() {
                if let matchRange = Range(match.range(at: 1), in: result) {
                    let numberStr = String(result[matchRange])
                    let expanded = numberToWords(numberStr) + " dollars"
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: expanded)
                    }
                }
            }
        }

        return result
    }

    /// Cleans and normalizes punctuation.
    private func cleanPunctuation(_ text: String) -> String {
        var result = text

        // Replace multiple spaces with single space
        result = result.replacingOccurrences(
            of: " +",
            with: " ",
            options: .regularExpression
        )

        // Remove hyphens between letters (e-mail → email)
        result = result.replacingOccurrences(
            of: "([a-z])-([a-z])",
            with: "$1$2",
            options: .regularExpression
        )

        // Keep sentence-ending punctuation but handle multiple
        result = result.replacingOccurrences(
            of: "[.!?]{2,}",
            with: ".",
            options: .regularExpression
        )

        return result
    }
}
