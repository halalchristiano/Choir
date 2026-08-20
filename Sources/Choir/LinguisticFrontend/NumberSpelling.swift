import Foundation

/// Converts integers to their spoken English form.
///
/// Shared by ``TextNormalizer`` and ``ScriptureNormalizer`` so that a number
/// is spoken identically wherever it appears. Values are carried as `Int64`
/// because `Int` is 32-bit on watchOS (arm64_32), where the trillion scale
/// would not fit.
enum NumberSpelling {
    /// Number words for 0-19.
    static let units = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen",
        "seventeen", "eighteen", "nineteen",
    ]

    /// Words for the tens place (index 2 == "twenty", index 9 == "ninety").
    static let tens = [
        "", "", "twenty", "thirty", "forty",
        "fifty", "sixty", "seventy", "eighty", "ninety",
    ]

    /// Scale words for large numbers.
    static let scales: [(Int64, String)] = [
        (1_000_000_000_000, "trillion"),
        (1_000_000_000, "billion"),
        (1_000_000, "million"),
        (1000, "thousand"),
        (100, "hundred"),
    ]

    /// Irregular spoken ordinals. Everything else takes a "th" suffix, with
    /// a "y" ending becoming "ie" first ("twenty" -> "twentieth").
    private static let irregularOrdinals: [String: String] = [
        "one": "first", "two": "second", "three": "third", "five": "fifth",
        "eight": "eighth", "nine": "ninth", "twelve": "twelfth",
    ]

    /// Spells a numeric string, returning it unchanged if it is not an integer.
    static func words(for numString: String) -> String {
        guard let value = Int64(numString), value >= 0 else { return numString }
        return words(for: value)
    }

    /// Spells a non-negative integer, e.g. 316 -> "three hundred sixteen".
    static func words(for value: Int64) -> String {
        guard value > 0 else { return units[0] }

        var parts: [String] = []
        var remaining = value

        for (scale, scaleWord) in scales where remaining >= scale {
            let quotient = remaining / scale
            remaining %= scale

            if scale == 100 {
                parts.append("\(belowHundred(quotient)) \(scaleWord)")
            } else {
                parts.append("\(words(for: quotient)) \(scaleWord)")
            }
        }

        if remaining > 0 {
            parts.append(belowHundred(remaining))
        }

        return parts.joined(separator: " ")
    }

    /// Spells a value in 0..<100, e.g. 42 -> "forty two".
    static func belowHundred(_ n: Int64) -> String {
        guard n > 0 else { return units[0] }
        if n < Int64(units.count) { return units[Int(n)] }

        let tensPlace = Int(n / 10)
        let onesPlace = Int(n % 10)
        guard tensPlace < tens.count else { return String(n) }

        let tensWord = tens[tensPlace]
        return onesPlace == 0 ? tensWord : "\(tensWord) \(units[onesPlace])"
    }

    /// Spells an ordinal, e.g. 1 -> "first", 23 -> "twenty third".
    static func ordinal(for value: Int64) -> String {
        let cardinal = words(for: value)
        guard let lastSpace = cardinal.lastIndex(of: " ") else {
            return ordinalizeWord(cardinal)
        }
        let head = cardinal[..<lastSpace]
        let tail = String(cardinal[cardinal.index(after: lastSpace)...])
        return "\(head) \(ordinalizeWord(tail))"
    }

    private static func ordinalizeWord(_ word: String) -> String {
        if let irregular = irregularOrdinals[word] { return irregular }
        if word.hasSuffix("y") { return String(word.dropLast()) + "ieth" }
        return word + "th"
    }
}
