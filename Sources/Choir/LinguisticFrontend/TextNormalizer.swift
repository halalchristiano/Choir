import Foundation

/// Configures normalization behaviour (SRS TXT-012).
public struct NormalizationPolicy: Sendable, Equatable {
    /// Whether Scripture references are expanded as a first-class category
    /// (TXT-011). When false they fall through to ordinary number handling.
    public var expandsScriptureReferences: Bool

    /// How an expanded Scripture reference is spoken.
    public var scriptureStyle: ScriptureStyle

    /// Verbatim mode for code and identifiers: suppresses the expansion of
    /// numbers, currency, contractions, abbreviations and Scripture, leaving
    /// the text to be spoken as written.
    public var verbatim: Bool

    public init(
        expandsScriptureReferences: Bool = true,
        scriptureStyle: ScriptureStyle = .chapterVerse,
        verbatim: Bool = false
    ) {
        self.expandsScriptureReferences = expandsScriptureReferences
        self.scriptureStyle = scriptureStyle
        self.verbatim = verbatim
    }

    /// Natural prose reading: everything expanded, Scripture spoken as
    /// "book chapter, verse".
    public static let `default` = NormalizationPolicy()

    /// Code and identifier reading.
    public static let verbatimMode = NormalizationPolicy(verbatim: true)
}

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

    /// Behaviour configuration (TXT-012).
    public let policy: NormalizationPolicy

    public init(policy: NormalizationPolicy = .default) {
        self.policy = policy
    }

    /// Normalizes text for synthesis, expanding numbers, abbreviations, etc.
    /// Normalizes text for synthesis (SRS TXT-010, TXT-012, TXT-013).
    ///
    /// Stage order is deliberate throughout. The recurring hazard is that a
    /// later stage destroys the pattern an earlier one needs: once "3:30" has
    /// become "three:thirty" it is no longer recognizable as a clock time, and
    /// once "$5" has become "$five" it is no longer currency. Each stage below
    /// records why it sits where it does.
    public func normalize(_ text: String) -> String {
        // Verbatim mode speaks the text as written (TXT-012).
        guard !policy.verbatim else {
            return cleanPunctuation(text.lowercased()).trimmingCharacters(in: .whitespaces)
        }

        // --- Case-sensitive stages, before the text is folded to lowercase ---

        // One scan establishes what the input contains; every stage below is
        // gated on it, so a stage that cannot possibly match costs nothing.
        let flags = ContentFlags(text)

        // TXT-013: fold smart quotes and ellipses so later patterns see ASCII.
        var result = flags.hasFancyPunctuation ? normalizeTypography(text) : text

        // Addresses hold dots and digits the decimal and date stages would
        // otherwise claim, so they are spoken structurally first.
        if flags.hasAt || flags.hasDot {
            result = expandWebAddresses(result)
        }

        // Roman numerals and the Saint/Street distinction both depend on
        // capitalization: lowercase "i", "x" and "c" are ordinary words, and
        // "St. John" versus "Baker St." is decided by the following capital.
        if flags.hasUppercase {
            result = expandRomanNumerals(result)
            result = disambiguateSaint(result)
        }

        result = result.lowercased()

        // --- Case-insensitive stages ---

        result = expandDictionary(result, Self.contractions)

        // Scripture claims "book 3:16" before the clock-time stage can read it
        // as half past three (TXT-011).
        if policy.expandsScriptureReferences, flags.hasColon {
            result = ScriptureNormalizer(style: policy.scriptureStyle).normalize(result)
        }

        // Every stage below matches on a digit. One O(n) scan to establish
        // there are none is far cheaper than running a dozen regexes over the
        // whole input to discover the same thing -- which matters at the
        // 1,000,000 characters TXT-001 requires the engine to accept.
        guard flags.hasDigit else {
            result = expandDictionary(result, Self.abbreviations)
            if flags.hasWideDash { result = foldDashPauses(result) }
            return cleanPunctuation(result).trimmingCharacters(in: .whitespaces)
        }

        // Dates before times: an ISO date contains no colon, but a slash date
        // and a time can both appear in one sentence, and dates are the more
        // specific pattern.
        result = expandDates(result)
        result = expandClockTimes(result)

        // Phone numbers before ranges: "555-1234" is a number read digit by
        // digit, not the range five hundred fifty five to one thousand.
        result = expandPhoneNumbers(result)

        // Currency before bare numbers, or "$50" becomes "$fifty".
        result = expandCurrency(result)

        // Decades before units: "1990s" would otherwise match the unit pattern
        // as 1990 plus the seconds symbol.
        result = expandDecades(result)

        // Units and percentages carry a trailing symbol that number expansion
        // would strand.
        result = expandUnits(result)
        result = expandPercentages(result)

        // Fractions before decimals and ranges, since "1/2" contains neither
        // a point nor a dash but does contain two bare integers.
        result = expandFractions(result)
        result = expandRanges(result)
        result = expandDecimals(result)

        // Ordinals before years: "1st" must not be read as a cardinal, and
        // four-digit years must not be read as plain thousands.
        result = expandOrdinals(result)
        result = expandYears(result)

        // Whatever integers remain are cardinals.
        result = expandNumbers(result)

        result = expandDictionary(result, Self.abbreviations)

        // TXT-013: dashes become pauses only now that every range pattern
        // that needed the dash character has already matched.
        if flags.hasWideDash { result = foldDashPauses(result) }
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
    ///
    /// Delegates to ``NumberSpelling`` so that numbers are spoken identically
    /// here and in ``ScriptureNormalizer``.
    private func numberToWords(_ numStr: String) -> String {
        NumberSpelling.words(for: numStr)
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
