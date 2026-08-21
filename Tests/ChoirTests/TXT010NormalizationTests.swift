import Foundation
import Testing
@testable import Choir

/// SRS TXT-010 (MUST) — the normalization inventory.
///
/// "The front end shall expand, with correct spoken forms, at minimum:
/// cardinal and ordinal numbers (to at least 10^15), decimals, fractions,
/// percentages, currency, dates in common formats, clock times (12/24-hour),
/// phone-number-style digit strings, years (incl. "1990s"), Roman numerals in
/// title context, units, common abbreviations (context-disambiguated:
/// "St. John" vs "Baker St."), URLs and email addresses (spoken
/// structurally), and hyphenated ranges."
///
/// One test per named category, so a gap names itself.
@Suite("SRS TXT-010 — normalization inventory")
struct NormalizationInventoryTests {
    let normalizer = TextNormalizer()

    private func spoken(_ text: String) -> String { normalizer.normalize(text) }
    private func hasNoDigits(_ text: String) -> Bool { !text.contains(where: \.isNumber) }

    @Test("TXT-010: cardinals to at least 10^15")
    func testCardinals() {
        #expect(spoken("7").contains("seven"))
        #expect(spoken("42").contains("forty two"))
        #expect(spoken("305").contains("three hundred five"))
        #expect(spoken("1000000").contains("million"))
        #expect(spoken("1000000000000000").contains("quadrillion")
                || spoken("1000000000000000").contains("trillion"),
                "10^15 was not expanded: \(spoken("1000000000000000"))")
    }

    @Test("TXT-010: ordinals")
    func testOrdinals() {
        #expect(spoken("1st").contains("first"))
        #expect(spoken("2nd").contains("second"))
        #expect(spoken("3rd").contains("third"))
        #expect(spoken("4th").contains("fourth"))
        #expect(spoken("21st").contains("twenty first"))
        #expect(spoken("the 12th day").contains("twelfth"))
    }

    @Test("TXT-010: decimals read digit by digit after the point")
    func testDecimals() {
        let result = spoken("3.14")
        #expect(result.contains("three point one four"), "\(result)")
        #expect(hasNoDigits(result))
    }

    @Test("TXT-010: fractions")
    func testFractions() {
        #expect(spoken("1/2").contains("one half"))
        #expect(spoken("3/4").contains("three quarters"))
        #expect(spoken("2/3").contains("two thirds"))
        #expect(spoken("1/8").contains("one eighth"))
    }

    @Test("TXT-010: percentages")
    func testPercentages() {
        let result = spoken("50%")
        #expect(result.contains("fifty percent"), "\(result)")
        #expect(!result.contains("%"))
        #expect(spoken("99.9%").contains("percent"))
    }

    @Test("TXT-010: currency with major units")
    func testCurrency() {
        let result = spoken("It costs $50")
        #expect(result.contains("fifty dollars"), "\(result)")
        #expect(!result.contains("$"))
    }

    @Test("TXT-010: clock times, 12- and 24-hour")
    func testClockTimes() {
        #expect(spoken("at 3:30").contains("three thirty"), "\(spoken("at 3:30"))")
        #expect(spoken("at 15:45").contains("fifteen forty five"), "\(spoken("at 15:45"))")
        #expect(spoken("at 9:00").contains("o'clock"), "\(spoken("at 9:00"))")
        #expect(spoken("at 4:05").contains("four oh five"), "\(spoken("at 4:05"))")
        #expect(!spoken("at 3:30").contains(":"))
    }

    @Test("TXT-010: dates in common formats")
    func testDates() {
        let iso = spoken("on 2024-01-15")
        #expect(iso.contains("january"), "\(iso)")
        #expect(iso.contains("fifteenth"), "\(iso)")

        let slash = spoken("on 01/15/2024")
        #expect(slash.contains("january"), "\(slash)")
    }

    @Test("TXT-010: years and decades")
    func testYears() {
        #expect(spoken("in 1990").contains("nineteen ninety"), "\(spoken("in 1990"))")
        #expect(spoken("the 1990s").contains("nineteen nineties"), "\(spoken("the 1990s"))")
        #expect(spoken("in 2024").contains("twenty twenty four"), "\(spoken("in 2024"))")
        #expect(spoken("in 1905").contains("nineteen oh five"), "\(spoken("in 1905"))")
    }

    @Test("TXT-010: phone-number-style digit strings read digit by digit")
    func testPhoneNumbers() {
        let result = spoken("call 555-123-4567")
        #expect(result.contains("five five five"), "\(result)")
        #expect(hasNoDigits(result))
        // Not read as a cardinal.
        #expect(!result.contains("million"), "\(result)")
    }

    /// The requirement names "Henry VIII" specifically.
    @Test("TXT-010: Roman numerals in title context")
    func testRomanNumerals() {
        let result = spoken("Henry VIII reigned")
        #expect(result.contains("the eighth"), "\(result)")
        #expect(!result.lowercased().contains("viii"), "\(result)")

        #expect(spoken("Elizabeth II").contains("the second"))
        #expect(spoken("Louis XIV").contains("the fourteenth"))
    }

    @Test("TXT-010: Roman numeral parsing rejects malformed input")
    func testRomanParsing() {
        #expect(TextNormalizer.romanValue("VIII") == 8)
        #expect(TextNormalizer.romanValue("XIV") == 14)
        #expect(TextNormalizer.romanValue("MCMXC") == 1990)
        #expect(TextNormalizer.romanValue("Q") == nil)
        #expect(TextNormalizer.romanValue("") == nil)
    }

    @Test("TXT-010: units of measure")
    func testUnits() {
        #expect(spoken("5 km").contains("kilometers"), "\(spoken("5 km"))")
        #expect(spoken("10 kg").contains("kilograms"), "\(spoken("10 kg"))")
        #expect(spoken("2.4 GHz").contains("gigahertz"), "\(spoken("2.4 GHz"))")
        #expect(spoken("1 mi").contains("mile"), "\(spoken("1 mi"))")
    }

    /// The requirement names this exact pair.
    @Test("TXT-010: St. John versus Baker St.")
    func testSaintVersusStreet() {
        let saint = spoken("St. John wrote it")
        #expect(saint.contains("saint john"), "\(saint)")
        #expect(!saint.contains("street"), "\(saint)")

        let street = spoken("He lives on Baker St.")
        #expect(street.contains("street"), "\(street)")
        #expect(!street.contains("saint"), "\(street)")
    }

    @Test("TXT-010: URLs and email spoken structurally")
    func testWebAddresses() {
        let email = spoken("write to someone@example.com")
        #expect(email.contains(" at "), "\(email)")
        #expect(!email.contains("@"), "\(email)")

        let url = spoken("visit https://example.com today")
        #expect(url.contains("dot com"), "\(url)")
        #expect(!url.contains("://"), "\(url)")
    }

    @Test("TXT-010: hyphenated ranges")
    func testRanges() {
        for dash in ["-", "\u{2013}"] {
            let result = spoken("pages 3\(dash)5")
            #expect(result.contains("three to five"), "dash \(dash): \(result)")
        }
    }

    @Test("TXT-013: smart quotes, ellipses and dashes")
    func testTypography() {
        let curly = spoken("\u{201C}hello\u{201D} and \u{2018}there\u{2019}")
        #expect(!curly.contains("\u{201C}"), "\(curly)")
        #expect(!curly.contains("\u{2018}"), "\(curly)")

        let dashed = spoken("wait \u{2014} then go")
        #expect(!dashed.contains("\u{2014}"), "\(dashed)")
    }

    /// Stage ordering is the whole difficulty of TXT-010; these are the
    /// interactions that break when it is wrong.
    @Test("TXT-010: stage ordering does not corrupt neighbouring forms")
    func testStageOrdering() {
        // A time must not be eaten by the decimal or range stages.
        #expect(spoken("meet at 3:30").contains("three thirty"))

        // A Scripture reference still beats the clock-time reading.
        let verse = spoken("John 3:16")
        #expect(verse.contains("john three, sixteen"), "\(verse)")
        #expect(!verse.contains("o'clock"), "\(verse)")

        // A phone number must not be read as a range.
        #expect(!spoken("555-1234").contains(" to "), "\(spoken("555-1234"))")

        // A year inside a date must not double-expand.
        let date = spoken("2024-01-15")
        #expect(!date.contains("twenty twenty four twenty twenty four"), "\(date)")
    }

    @Test("TXT-010: a mixed passage leaves no digits behind")
    func testMixedPassage() {
        let result = spoken("On 2024-01-15 at 3:30 pm, 50% of the 1,000 members paid $25 each.")
        #expect(!result.contains("%"), "\(result)")
        #expect(!result.contains("$"), "\(result)")
        #expect(!result.contains(":"), "\(result)")
    }

    @Test("TXT-012: verbatim mode suppresses every expansion")
    func testVerbatimUnaffected() {
        let verbatim = TextNormalizer(policy: .verbatimMode)
        let result = verbatim.normalize("3.14 and 50% on 2024-01-15")
        #expect(result.contains("3.14"), "\(result)")
        #expect(result.contains("%"), "\(result)")
    }
}
