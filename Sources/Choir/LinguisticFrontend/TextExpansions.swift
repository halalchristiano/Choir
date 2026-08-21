import Foundation

/// The expansion stages required by SRS TXT-010, plus the typography handling
/// of TXT-013.
///
/// Stage order is load-bearing and is documented at each call site in
/// ``TextNormalizer/normalize(_:)``. The recurring hazard is that a later
/// stage destroys the pattern an earlier one needs: once "3:30" has become
/// "three:thirty" it is no longer a clock time, and once "$5" has become
/// "$five" it is no longer currency.
extension TextNormalizer {

    // MARK: - TXT-013 Typography

    /// A single scan recording which expansion stages can possibly match.
    ///
    /// Each `replacingOccurrences` or regex call is one complete Unicode-aware
    /// traversal of the string. At the 1,000,000 characters TXT-001 requires
    /// the engine to accept, a dozen such traversals dominate the cost, so the
    /// pipeline establishes what is present once and skips what cannot match.
    struct ContentFlags {
        var hasDigit = false
        var hasUppercase = false
        var hasDot = false
        var hasAt = false
        var hasColon = false
        var hasFancyPunctuation = false
        var hasWideDash = false

        init(_ text: String) {
            for character in text {
                switch character {
                case "0"..."9": hasDigit = true
                case ".": hasDot = true
                case "@": hasAt = true
                case ":": hasColon = true
                case "\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}", "\u{2026}", "\u{00A0}":
                    hasFancyPunctuation = true
                case "\u{2014}", "\u{2013}":
                    hasWideDash = true
                default:
                    if character.isUppercase { hasUppercase = true }
                }
            }
        }
    }

    /// Normalizes typography so later stages see ASCII forms (TXT-013).
    ///
    /// Folded in one pass rather than one `replacingOccurrences` per character
    /// class, which would be six full traversals of the input.
    func normalizeTypography(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "\u{201C}", "\u{201D}": result.append("\"")
            case "\u{2018}", "\u{2019}": result.append("'")
            case "\u{2026}": result.append("...")
            case "\u{00A0}": result.append(" ")
            default: result.append(character)
            }
        }
        return result
    }

    /// Renders em and en dashes as pauses (TXT-013).
    ///
    /// Deliberately late. Dash characters are how ranges are written -- both
    /// numeric ("3–5") and Scripture ("Rom. 8:28–30") -- so folding them into
    /// a pause marker before those stages run destroys the pattern they match
    /// on. This runs once every range has already been expanded.
    func foldDashPauses(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{2014}", with: " -- ")
            .replacingOccurrences(of: "\u{2013}", with: " -- ")
    }

    // MARK: - TXT-010 URLs and email

    /// Speaks URLs and email addresses structurally.
    ///
    /// Runs before any numeric stage: an address contains dots and digits that
    /// the decimal and date stages would otherwise claim.
    func expandWebAddresses(_ text: String) -> String {
        var result = text

        result = Self.emailRegex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result),
            withTemplate: "$1 at $2")

        result = Self.urlRegex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result),
            withTemplate: "$1")

        // Spell the dots inside what remains of a hostname.
        result = Self.hostnameRegex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result),
            withTemplate: "$1 dot $2")

        return result
    }

    // MARK: - TXT-010 Roman numerals

    /// Expands Roman numerals in title context, e.g. "Henry VIII" -> "Henry the eighth".
    ///
    /// Requires the original casing, so it runs before the text is lowercased:
    /// lowercase "i", "x", "c", "l", "d" and "m" are ordinary English words and
    /// cannot be told apart from numerals once case is gone.
    func expandRomanNumerals(_ text: String) -> String {
        let ns = text as NSString
        let matches = Self.romanRegex.matches(
            in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3,
                  let full = Range(match.range, in: result),
                  let numeralRange = Range(match.range(at: 2), in: text) else { continue }

            let numeral = String(text[numeralRange])
            guard let value = Self.romanValue(numeral), value > 0, value <= 3999 else { continue }

            let name = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            result.replaceSubrange(
                full,
                with: "\(name) the \(NumberSpelling.ordinal(for: Int64(value)))")
        }
        return result
    }

    /// Parses a Roman numeral, rejecting malformed sequences.
    static func romanValue(_ numeral: String) -> Int? {
        let values: [Character: Int] = ["I": 1, "V": 5, "X": 10, "L": 50,
                                        "C": 100, "D": 500, "M": 1000]
        var total = 0
        var previous = 0
        for character in numeral.uppercased().reversed() {
            guard let value = values[character] else { return nil }
            if value < previous {
                total -= value
            } else {
                total += value
                previous = value
            }
        }
        return total > 0 ? total : nil
    }

    // MARK: - TXT-010 Abbreviation disambiguation

    /// Distinguishes "St. John" (Saint) from "Baker St." (Street).
    ///
    /// The requirement names this pair specifically. A following capitalized
    /// word means a name and so "saint"; anything else means "street". Needs
    /// original casing, so it runs before lowercasing.
    func disambiguateSaint(_ text: String) -> String {
        Self.saintRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: "saint $1")
    }

    // MARK: - TXT-010 Dates and times

    /// Expands clock times, 12- and 24-hour.
    ///
    /// Runs after Scripture expansion, which claims "book 3:16" first, and
    /// before bare number expansion, which would destroy the colon form.
    func expandClockTimes(_ text: String) -> String {
        Self.replacing(Self.timeRegex, in: text) { groups in
            guard let hour = groups[1].flatMap({ Int64($0) }),
                  let minute = groups[2].flatMap({ Int64($0) }),
                  hour <= 23, minute <= 59 else { return nil }

            let hourWords = NumberSpelling.words(for: hour == 0 ? 12 : hour)
            var spoken: String
            if minute == 0 {
                spoken = "\(hourWords) o'clock"
            } else if minute < 10 {
                spoken = "\(hourWords) oh \(NumberSpelling.words(for: minute))"
            } else {
                spoken = "\(hourWords) \(NumberSpelling.words(for: minute))"
            }
            if let suffix = groups[3]?.lowercased(), !suffix.isEmpty {
                spoken += suffix.contains("p") ? " p m" : " a m"
            }
            return spoken
        }
    }

    /// Expands ISO and slash-separated dates.
    func expandDates(_ text: String) -> String {
        var result = Self.replacing(Self.isoDateRegex, in: text) { groups in
            guard let year = groups[1].flatMap({ Int64($0) }),
                  let month = groups[2].flatMap({ Int($0) }),
                  let day = groups[3].flatMap({ Int64($0) }),
                  (1...12).contains(month), (1...31).contains(Int(day)) else { return nil }
            return "\(Self.monthNames[month - 1]) \(NumberSpelling.ordinal(for: day)) \(Self.spokenYear(year))"
        }

        result = Self.replacing(Self.slashDateRegex, in: result) { groups in
            guard let month = groups[1].flatMap({ Int($0) }),
                  let day = groups[2].flatMap({ Int64($0) }),
                  let year = groups[3].flatMap({ Int64($0) }),
                  (1...12).contains(month), (1...31).contains(Int(day)) else { return nil }
            return "\(Self.monthNames[month - 1]) \(NumberSpelling.ordinal(for: day)) \(Self.spokenYear(year))"
        }
        return result
    }

    static let monthNames = ["january", "february", "march", "april", "may", "june",
                             "july", "august", "september", "october", "november", "december"]

    /// Speaks a year in the conventional paired form: 1990 as "nineteen ninety".
    static func spokenYear(_ year: Int64) -> String {
        // Years outside the paired range, and round centuries, read as cardinals.
        guard (1100...2099).contains(year) else { return NumberSpelling.words(for: year) }
        let century = year / 100
        let remainder = year % 100
        if remainder == 0 { return "\(NumberSpelling.words(for: century)) hundred" }
        if remainder < 10 {
            return "\(NumberSpelling.words(for: century)) oh \(NumberSpelling.words(for: remainder))"
        }
        return "\(NumberSpelling.words(for: century)) \(NumberSpelling.belowHundred(remainder))"
    }

    /// Expands decades: "1990s" -> "nineteen nineties".
    ///
    /// Runs *before* the unit stage. "1990s" otherwise matches the unit
    /// pattern as 1990 followed by the seconds symbol, yielding "one thousand
    /// nine hundred ninety seconds" -- the decade never reaches its own stage.
    /// A four-digit requirement keeps it clear of genuine unit forms like
    /// "10s".
    func expandDecades(_ text: String) -> String {
        Self.replacing(Self.decadeRegex, in: text) { groups in
            guard let year = groups[1].flatMap({ Int64($0) }), (1100...2099).contains(year) else {
                return nil
            }
            let spoken = Self.spokenYear(year)
            // "nineteen ninety" -> "nineteen nineties"
            guard let last = spoken.split(separator: " ").last else { return nil }
            let pluralized: String
            if last.hasSuffix("y") {
                pluralized = String(last.dropLast()) + "ies"
            } else {
                pluralized = last + "s"
            }
            return spoken.split(separator: " ").dropLast().joined(separator: " ")
                + (spoken.contains(" ") ? " " : "") + pluralized
        }
    }

    /// Expands bare four-digit years: "1990" -> "nineteen ninety".
    func expandYears(_ text: String) -> String {
        Self.replacing(Self.yearRegex, in: text) { groups in
            guard let year = groups[1].flatMap({ Int64($0) }), (1100...2099).contains(year) else {
                return nil
            }
            return Self.spokenYear(year)
        }
    }

    // MARK: - TXT-010 Numeric forms

    /// Expands ordinals written with a suffix: "1st" -> "first".
    func expandOrdinals(_ text: String) -> String {
        Self.replacing(Self.ordinalRegex, in: text) { groups in
            groups[1].flatMap { Int64($0) }.map { NumberSpelling.ordinal(for: $0) }
        }
    }

    /// Expands percentages.
    func expandPercentages(_ text: String) -> String {
        Self.replacing(Self.percentRegex, in: text) { groups in
            guard let whole = groups[1] else { return nil }
            let spoken = Self.spokenDecimal(whole)
            return "\(spoken) percent"
        }
    }

    /// Expands fractions: "1/2" -> "one half", "3/4" -> "three quarters".
    func expandFractions(_ text: String) -> String {
        Self.replacing(Self.fractionRegex, in: text) { groups in
            guard let numerator = groups[1].flatMap({ Int64($0) }),
                  let denominator = groups[2].flatMap({ Int64($0) }),
                  denominator > 0 else { return nil }

            let numeratorWords = NumberSpelling.words(for: numerator)
            let denominatorWords: String
            switch denominator {
            case 2: denominatorWords = numerator == 1 ? "half" : "halves"
            case 4: denominatorWords = numerator == 1 ? "quarter" : "quarters"
            default:
                let base = NumberSpelling.ordinal(for: denominator)
                denominatorWords = numerator == 1 ? base : base + "s"
            }
            return "\(numeratorWords) \(denominatorWords)"
        }
    }

    /// Expands decimals: "3.14" -> "three point one four".
    func expandDecimals(_ text: String) -> String {
        Self.replacing(Self.decimalRegex, in: text) { groups in
            groups[0].map { Self.spokenDecimal($0) }
        }
    }

    /// Speaks a possibly-decimal number. Digits after the point are read
    /// individually, as English does: 3.14 is "three point one four".
    static func spokenDecimal(_ token: String) -> String {
        let parts = token.split(separator: ".", maxSplits: 1)
        guard let whole = parts.first, let wholeValue = Int64(whole) else { return token }
        let wholeWords = NumberSpelling.words(for: wholeValue)
        guard parts.count == 2 else { return wholeWords }

        let digits = parts[1].compactMap { character -> String? in
            guard let digit = character.wholeNumberValue else { return nil }
            return NumberSpelling.words(for: Int64(digit))
        }
        guard !digits.isEmpty else { return wholeWords }
        return "\(wholeWords) point \(digits.joined(separator: " "))"
    }

    /// Expands hyphenated ranges: "3-5" -> "three to five".
    func expandRanges(_ text: String) -> String {
        Self.replacing(Self.rangeRegex, in: text) { groups in
            guard let low = groups[1].flatMap({ Int64($0) }),
                  let high = groups[2].flatMap({ Int64($0) }) else { return nil }
            return "\(NumberSpelling.words(for: low)) to \(NumberSpelling.words(for: high))"
        }
    }

    /// Expands phone-number-style digit strings, read digit by digit.
    func expandPhoneNumbers(_ text: String) -> String {
        Self.replacing(Self.phoneRegex, in: text) { groups in
            guard let token = groups[0] else { return nil }
            let digits = token.compactMap { character -> String? in
                guard let digit = character.wholeNumberValue else { return nil }
                return NumberSpelling.words(for: Int64(digit))
            }
            guard digits.count >= 7 else { return nil }
            return digits.joined(separator: " ")
        }
    }

    /// Expands units of measure: "5 km" -> "five kilometers".
    func expandUnits(_ text: String) -> String {
        Self.replacing(Self.unitRegex, in: text) { groups in
            guard let value = groups[1], let symbol = groups[2] else { return nil }
            guard let unit = Self.units[symbol] else { return nil }
            let spokenValue = Self.spokenDecimal(value)
            let plural = (Double(value) ?? 0) == 1 ? unit.singular : unit.plural
            return "\(spokenValue) \(plural)"
        }
    }

    static let units: [String: (singular: String, plural: String)] = [
        "km": ("kilometer", "kilometers"),
        "m": ("meter", "meters"),
        "cm": ("centimeter", "centimeters"),
        "mm": ("millimeter", "millimeters"),
        "kg": ("kilogram", "kilograms"),
        "g": ("gram", "grams"),
        "mg": ("milligram", "milligrams"),
        "lb": ("pound", "pounds"),
        "oz": ("ounce", "ounces"),
        "mi": ("mile", "miles"),
        "ft": ("foot", "feet"),
        "in": ("inch", "inches"),
        "hz": ("hertz", "hertz"),
        "khz": ("kilohertz", "kilohertz"),
        "mhz": ("megahertz", "megahertz"),
        "ghz": ("gigahertz", "gigahertz"),
        "kb": ("kilobyte", "kilobytes"),
        "mb": ("megabyte", "megabytes"),
        "gb": ("gigabyte", "gigabytes"),
        "tb": ("terabyte", "terabytes"),
        "ms": ("millisecond", "milliseconds"),
        "s": ("second", "seconds"),
        "hr": ("hour", "hours"),
        "min": ("minute", "minutes"),
    ]

    // MARK: - Regex helpers

    /// Applies `transform` to each match, rewriting back-to-front so that
    /// earlier match ranges stay valid.
    static func replacing(
        _ regex: NSRegularExpression,
        in text: String,
        _ transform: ([String?]) -> String?
    ) -> String {
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            var groups: [String?] = []
            for index in 0..<match.numberOfRanges {
                groups.append(Range(match.range(at: index), in: text).map { String(text[$0]) })
            }
            guard let replacement = transform(groups),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    // MARK: - Patterns

    static let emailRegex = try! NSRegularExpression(
        pattern: #"\b([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b"#)
    static let urlRegex = try! NSRegularExpression(
        pattern: #"\bhttps?://(?:www\.)?([^\s/]+)(?:/\S*)?"#)
    static let hostnameRegex = try! NSRegularExpression(
        pattern: #"\b([A-Za-z0-9-]+)\.(com|org|net|edu|gov|io|co|uk|dev|app)\b"#,
        options: [.caseInsensitive])
    static let romanRegex = try! NSRegularExpression(
        pattern: #"\b([A-Z][a-z]+)\s+((?=[MDCLXVI])M{0,3}(?:CM|CD|D?C{0,3})(?:XC|XL|L?X{0,3})(?:IX|IV|V?I{0,3}))\b"#)
    static let saintRegex = try! NSRegularExpression(
        pattern: #"\bSt\.\s+([A-Z][a-z]+)"#)
    static let timeRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,2}):(\d{2})(?::\d{2})?\s*([ap]\.?m\.?)?"#, options: [.caseInsensitive])
    static let isoDateRegex = try! NSRegularExpression(
        pattern: #"\b(\d{4})-(\d{1,2})-(\d{1,2})\b"#)
    static let slashDateRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,2})/(\d{1,2})/(\d{4})\b"#)
    static let decadeRegex = try! NSRegularExpression(
        pattern: #"\b(\d{4})'?s\b"#)
    static let yearRegex = try! NSRegularExpression(
        pattern: #"\b(\d{4})\b"#)
    static let ordinalRegex = try! NSRegularExpression(
        pattern: #"\b(\d+)(?:st|nd|rd|th)\b"#, options: [.caseInsensitive])
    static let percentRegex = try! NSRegularExpression(
        pattern: #"\b(\d+(?:\.\d+)?)\s*%"#)
    static let fractionRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,3})/(\d{1,3})\b"#)
    static let decimalRegex = try! NSRegularExpression(
        pattern: #"\b\d+\.\d+\b"#)
    static let rangeRegex = try! NSRegularExpression(
        pattern: #"\b(\d+)\s*[-–—]\s*(\d+)\b"#)
    static let phoneRegex = try! NSRegularExpression(
        pattern: #"\b\d{3}[-.\s]\d{3}[-.\s]\d{4}\b|\b\d{3}[-.\s]\d{4}\b"#)
    static let unitRegex = try! NSRegularExpression(
        pattern: #"\b(\d+(?:\.\d+)?)\s*(km|cm|mm|kg|mg|lb|oz|mi|ft|in|khz|mhz|ghz|hz|kb|mb|gb|tb|ms|hr|min|m|g|s)\b"#,
        options: [.caseInsensitive])
}
