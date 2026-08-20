import Foundation

/// How a Scripture reference is spoken (SRS TXT-011).
public enum ScriptureStyle: String, Sendable, CaseIterable, Codable {
    /// "John 3:16" -> "john three, sixteen"
    case chapterVerse

    /// "John 3:16" -> "john three colon sixteen"
    ///
    /// Included because the specification names it as a selectable style. The
    /// rationale for TXT-011 explicitly rejects it as a *default*, not as an
    /// option.
    case chapterColonVerse

    /// "John 3:16" -> "john chapter three, verse sixteen"
    case spokenFull
}

/// Expands Scripture references into spoken form.
///
/// Implements SRS TXT-011 (MUST), which requires Scripture reference formats
/// to be handled as a first-class category: chapter and verse, verse ranges,
/// abbreviations for all 66 Protestant canonical books, and multi-reference
/// lists.
///
/// The rationale is quoted in the specification: THE ONE is a primary
/// consumer, and verse references must never be spoken as
/// "john three colon sixteen".
public struct ScriptureNormalizer: Sendable {
    /// Written surface forms mapped to spoken book names, longest first so the
    /// most specific form wins ("song of songs" before "song", "1 john"
    /// before "john").
    static let bookForms: [(written: String, spoken: String)] = [
        ("ii thessalonians", "second thessalonians"),
        ("1 thessalonians", "first thessalonians"),
        ("2 thessalonians", "second thessalonians"),
        ("i thessalonians", "first thessalonians"),
        ("song of solomon", "song of solomon"),
        ("1thessalonians", "first thessalonians"),
        ("2thessalonians", "second thessalonians"),
        ("ii corinthians", "second corinthians"),
        ("1 corinthians", "first corinthians"),
        ("2 corinthians", "second corinthians"),
        ("i corinthians", "first corinthians"),
        ("ii chronicles", "second chronicles"),
        ("song of songs", "song of solomon"),
        ("1 chronicles", "first chronicles"),
        ("1corinthians", "first corinthians"),
        ("2 chronicles", "second chronicles"),
        ("2corinthians", "second corinthians"),
        ("ecclesiastes", "ecclesiastes"),
        ("i chronicles", "first chronicles"),
        ("lamentations", "lamentations"),
        ("1chronicles", "first chronicles"),
        ("2chronicles", "second chronicles"),
        ("deuteronomy", "deuteronomy"),
        ("philippians", "philippians"),
        ("revelations", "revelation"),
        ("colossians", "colossians"),
        ("ii timothy", "second timothy"),
        ("revelation", "revelation"),
        ("1 timothy", "first timothy"),
        ("2 timothy", "second timothy"),
        ("canticles", "song of solomon"),
        ("ephesians", "ephesians"),
        ("galatians", "galatians"),
        ("i timothy", "first timothy"),
        ("ii samuel", "second samuel"),
        ("leviticus", "leviticus"),
        ("zechariah", "zechariah"),
        ("zephaniah", "zephaniah"),
        ("1 samuel", "first samuel"),
        ("1timothy", "first timothy"),
        ("2 samuel", "second samuel"),
        ("2timothy", "second timothy"),
        ("habakkuk", "habakkuk"),
        ("i samuel", "first samuel"),
        ("ii chron", "second chronicles"),
        ("ii kings", "second kings"),
        ("ii peter", "second peter"),
        ("ii thess", "second thessalonians"),
        ("iii john", "third john"),
        ("jeremiah", "jeremiah"),
        ("nehemiah", "nehemiah"),
        ("philemon", "philemon"),
        ("proverbs", "proverbs"),
        ("1 chron", "first chronicles"),
        ("1 kings", "first kings"),
        ("1 peter", "first peter"),
        ("1 thess", "first thessalonians"),
        ("1samuel", "first samuel"),
        ("2 chron", "second chronicles"),
        ("2 kings", "second kings"),
        ("2 peter", "second peter"),
        ("2 thess", "second thessalonians"),
        ("2samuel", "second samuel"),
        ("ezekiel", "ezekiel"),
        ("genesis", "genesis"),
        ("hebrews", "hebrews"),
        ("i chron", "first chronicles"),
        ("i kings", "first kings"),
        ("i peter", "first peter"),
        ("i thess", "first thessalonians"),
        ("ii john", "second john"),
        ("ii thes", "second thessalonians"),
        ("iii jhn", "third john"),
        ("malachi", "malachi"),
        ("matthew", "matthew"),
        ("numbers", "numbers"),
        ("obadiah", "obadiah"),
        ("1 john", "first john"),
        ("1 thes", "first thessalonians"),
        ("1chron", "first chronicles"),
        ("1kings", "first kings"),
        ("1peter", "first peter"),
        ("1thess", "first thessalonians"),
        ("2 john", "second john"),
        ("2 thes", "second thessalonians"),
        ("2chron", "second chronicles"),
        ("2kings", "second kings"),
        ("2peter", "second peter"),
        ("2thess", "second thessalonians"),
        ("3 john", "third john"),
        ("daniel", "daniel"),
        ("eccles", "ecclesiastes"),
        ("esther", "esther"),
        ("exodus", "exodus"),
        ("haggai", "haggai"),
        ("i john", "first john"),
        ("i thes", "first thessalonians"),
        ("ii chr", "second chronicles"),
        ("ii cor", "second corinthians"),
        ("ii jhn", "second john"),
        ("ii kgs", "second kings"),
        ("ii kin", "second kings"),
        ("ii pet", "second peter"),
        ("ii sam", "second samuel"),
        ("ii tim", "second timothy"),
        ("iii jn", "third john"),
        ("isaiah", "isaiah"),
        ("joshua", "joshua"),
        ("judges", "judges"),
        ("philem", "philemon"),
        ("psalms", "psalms"),
        ("romans", "romans"),
        ("1 chr", "first chronicles"),
        ("1 cor", "first corinthians"),
        ("1 jhn", "first john"),
        ("1 kgs", "first kings"),
        ("1 kin", "first kings"),
        ("1 pet", "first peter"),
        ("1 sam", "first samuel"),
        ("1 tim", "first timothy"),
        ("1john", "first john"),
        ("1thes", "first thessalonians"),
        ("2 chr", "second chronicles"),
        ("2 cor", "second corinthians"),
        ("2 jhn", "second john"),
        ("2 kgs", "second kings"),
        ("2 kin", "second kings"),
        ("2 pet", "second peter"),
        ("2 sam", "second samuel"),
        ("2 tim", "second timothy"),
        ("2john", "second john"),
        ("2thes", "second thessalonians"),
        ("3 jhn", "third john"),
        ("3john", "third john"),
        ("hosea", "hosea"),
        ("i chr", "first chronicles"),
        ("i cor", "first corinthians"),
        ("i jhn", "first john"),
        ("i kgs", "first kings"),
        ("i kin", "first kings"),
        ("i pet", "first peter"),
        ("i sam", "first samuel"),
        ("i tim", "first timothy"),
        ("ii ch", "second chronicles"),
        ("ii co", "second corinthians"),
        ("ii jn", "second john"),
        ("ii kg", "second kings"),
        ("ii ki", "second kings"),
        ("ii pe", "second peter"),
        ("ii pt", "second peter"),
        ("ii sa", "second samuel"),
        ("ii sm", "second samuel"),
        ("ii th", "second thessalonians"),
        ("ii ti", "second timothy"),
        ("james", "james"),
        ("jonah", "jonah"),
        ("micah", "micah"),
        ("nahum", "nahum"),
        ("psalm", "psalms"),
        ("titus", "titus"),
        ("1 ch", "first chronicles"),
        ("1 co", "first corinthians"),
        ("1 jn", "first john"),
        ("1 kg", "first kings"),
        ("1 ki", "first kings"),
        ("1 pe", "first peter"),
        ("1 pt", "first peter"),
        ("1 sa", "first samuel"),
        ("1 sm", "first samuel"),
        ("1 th", "first thessalonians"),
        ("1 ti", "first timothy"),
        ("1chr", "first chronicles"),
        ("1cor", "first corinthians"),
        ("1jhn", "first john"),
        ("1kgs", "first kings"),
        ("1kin", "first kings"),
        ("1pet", "first peter"),
        ("1sam", "first samuel"),
        ("1tim", "first timothy"),
        ("2 ch", "second chronicles"),
        ("2 co", "second corinthians"),
        ("2 jn", "second john"),
        ("2 kg", "second kings"),
        ("2 ki", "second kings"),
        ("2 pe", "second peter"),
        ("2 pt", "second peter"),
        ("2 sa", "second samuel"),
        ("2 sm", "second samuel"),
        ("2 th", "second thessalonians"),
        ("2 ti", "second timothy"),
        ("2chr", "second chronicles"),
        ("2cor", "second corinthians"),
        ("2jhn", "second john"),
        ("2kgs", "second kings"),
        ("2kin", "second kings"),
        ("2pet", "second peter"),
        ("2sam", "second samuel"),
        ("2tim", "second timothy"),
        ("3 jn", "third john"),
        ("3jhn", "third john"),
        ("acts", "acts"),
        ("amos", "amos"),
        ("deut", "deuteronomy"),
        ("eccl", "ecclesiastes"),
        ("esth", "esther"),
        ("exod", "exodus"),
        ("ezek", "ezekiel"),
        ("ezra", "ezra"),
        ("i ch", "first chronicles"),
        ("i co", "first corinthians"),
        ("i jn", "first john"),
        ("i kg", "first kings"),
        ("i ki", "first kings"),
        ("i pe", "first peter"),
        ("i pt", "first peter"),
        ("i sa", "first samuel"),
        ("i sm", "first samuel"),
        ("i th", "first thessalonians"),
        ("i ti", "first timothy"),
        ("joel", "joel"),
        ("john", "john"),
        ("josh", "joshua"),
        ("jude", "jude"),
        ("judg", "judges"),
        ("luke", "luke"),
        ("mark", "mark"),
        ("matt", "matthew"),
        ("obad", "obadiah"),
        ("phil", "philippians"),
        ("phlm", "philemon"),
        ("prov", "proverbs"),
        ("ruth", "ruth"),
        ("song", "song of solomon"),
        ("zech", "zechariah"),
        ("zeph", "zephaniah"),
        ("1ch", "first chronicles"),
        ("1co", "first corinthians"),
        ("1jn", "first john"),
        ("1kg", "first kings"),
        ("1ki", "first kings"),
        ("1pe", "first peter"),
        ("1pt", "first peter"),
        ("1sa", "first samuel"),
        ("1sm", "first samuel"),
        ("1th", "first thessalonians"),
        ("1ti", "first timothy"),
        ("2ch", "second chronicles"),
        ("2co", "second corinthians"),
        ("2jn", "second john"),
        ("2kg", "second kings"),
        ("2ki", "second kings"),
        ("2pe", "second peter"),
        ("2pt", "second peter"),
        ("2sa", "second samuel"),
        ("2sm", "second samuel"),
        ("2th", "second thessalonians"),
        ("2ti", "second timothy"),
        ("3jn", "third john"),
        ("act", "acts"),
        ("amo", "amos"),
        ("col", "colossians"),
        ("dan", "daniel"),
        ("deu", "deuteronomy"),
        ("ecc", "ecclesiastes"),
        ("eph", "ephesians"),
        ("est", "esther"),
        ("exo", "exodus"),
        ("eze", "ezekiel"),
        ("ezk", "ezekiel"),
        ("ezr", "ezra"),
        ("gal", "galatians"),
        ("gen", "genesis"),
        ("hab", "habakkuk"),
        ("hag", "haggai"),
        ("heb", "hebrews"),
        ("hos", "hosea"),
        ("isa", "isaiah"),
        ("jas", "james"),
        ("jdg", "judges"),
        ("jer", "jeremiah"),
        ("jhn", "john"),
        ("jnh", "jonah"),
        ("job", "job"),
        ("joe", "joel"),
        ("jon", "jonah"),
        ("jos", "joshua"),
        ("jsh", "joshua"),
        ("jud", "jude"),
        ("lam", "lamentations"),
        ("lev", "leviticus"),
        ("luk", "luke"),
        ("mal", "malachi"),
        ("mar", "mark"),
        ("mat", "matthew"),
        ("mic", "micah"),
        ("mrk", "mark"),
        ("nah", "nahum"),
        ("neh", "nehemiah"),
        ("num", "numbers"),
        ("oba", "obadiah"),
        ("phm", "philemon"),
        ("php", "philippians"),
        ("pro", "proverbs"),
        ("prv", "proverbs"),
        ("psa", "psalms"),
        ("pss", "psalms"),
        ("qoh", "ecclesiastes"),
        ("rev", "revelation"),
        ("rom", "romans"),
        ("rth", "ruth"),
        ("sos", "song of solomon"),
        ("tit", "titus"),
        ("zec", "zechariah"),
        ("zep", "zephaniah"),
        ("ac", "acts"),
        ("am", "amos"),
        ("da", "daniel"),
        ("de", "deuteronomy"),
        ("dn", "daniel"),
        ("dt", "deuteronomy"),
        ("ec", "ecclesiastes"),
        ("es", "esther"),
        ("ex", "exodus"),
        ("ga", "galatians"),
        ("ge", "genesis"),
        ("gn", "genesis"),
        ("hb", "habakkuk"),
        ("hg", "haggai"),
        ("ho", "hosea"),
        ("is", "isaiah"),
        ("jb", "job"),
        ("jd", "jude"),
        ("je", "jeremiah"),
        ("jg", "judges"),
        ("jl", "joel"),
        ("jm", "james"),
        ("jn", "john"),
        ("jr", "jeremiah"),
        ("la", "lamentations"),
        ("le", "leviticus"),
        ("lk", "luke"),
        ("lv", "leviticus"),
        ("mc", "micah"),
        ("mk", "mark"),
        ("ml", "malachi"),
        ("mt", "matthew"),
        ("na", "nahum"),
        ("nb", "numbers"),
        ("ne", "nehemiah"),
        ("nm", "numbers"),
        ("nu", "numbers"),
        ("ob", "obadiah"),
        ("pp", "philippians"),
        ("pr", "proverbs"),
        ("ps", "psalms"),
        ("re", "revelation"),
        ("rm", "romans"),
        ("ro", "romans"),
        ("ru", "ruth"),
        ("ss", "song of solomon"),
        ("ti", "titus"),
        ("zc", "zechariah"),
        ("zp", "zephaniah")
    ]

    /// Matches "<chapter>:<verse>" with an optional verse range.
    ///
    /// Deliberately cheap. An earlier design alternated all 363 book surface
    /// forms inside one pattern, which took 28 seconds to scan a
    /// 200,000-character input and would have taken roughly two minutes at
    /// the 1,000,000 characters TXT-001 requires the engine to accept.
    /// Matching the numeric shape first and looking backwards for a book name
    /// keeps the scan linear and the alternation out of the hot path.
    private static let numericRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: "\\b(\\d{1,3}):(\\d{1,3})(?:\\s*[-–—]\\s*(\\d{1,3}))?")
    }()

    /// The most whitespace-separated tokens any book surface form spans
    /// ("song of songs" is three).
    private static let maxBookTokens = 3

    public let style: ScriptureStyle

    public init(style: ScriptureStyle = .chapterVerse) {
        self.style = style
    }

    /// Expands every Scripture reference in `text`.
    ///
    /// Text that is not a reference is returned untouched, so this is safe to
    /// run ahead of general number expansion.
    public func normalize(_ text: String) -> String {
        // A reference always has a colon between two numbers, so colon-free
        // text can skip all regex work.
        guard text.contains(":") else { return text }

        let matches = Self.numericRegex.matches(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        guard !matches.isEmpty else { return text }

        var result = text
        // Rewrite back-to-front so earlier match ranges stay valid.
        for match in matches.reversed() {
            guard let numericRange = Range(match.range, in: result),
                  let chapter = Self.group(match, 1, in: text).flatMap({ Int64($0) }),
                  let verse = Self.group(match, 2, in: text).flatMap({ Int64($0) })
            else { continue }

            guard let (bookStart, spokenBook) =
                    Self.precedingBook(in: result, before: numericRange.lowerBound)
            else { continue }

            let verseEnd = Self.group(match, 3, in: text).flatMap { Int64($0) }

            result.replaceSubrange(
                bookStart..<numericRange.upperBound,
                with: spoken(book: spokenBook, chapter: chapter, verse: verse, verseEnd: verseEnd)
            )
        }
        return result
    }

    /// Finds a book name ending immediately before `index`, returning where it
    /// starts and how it is spoken.
    ///
    /// Tries the longest span first, so "1 john" wins over "john" and
    /// "song of songs" over "songs".
    private static func precedingBook(
        in text: String,
        before index: String.Index
    ) -> (String.Index, String)? {
        // Walk back over at most `maxBookTokens` whitespace-separated tokens,
        // recording where each begins.
        var tokenStarts: [String.Index] = []
        var cursor = index

        while tokenStarts.count < maxBookTokens, cursor > text.startIndex {
            var end = cursor
            while end > text.startIndex, text[text.index(before: end)].isWhitespace {
                end = text.index(before: end)
            }
            guard end > text.startIndex else { break }

            var begin = end
            while begin > text.startIndex, !text[text.index(before: begin)].isWhitespace {
                begin = text.index(before: begin)
            }
            tokenStarts.append(begin)
            cursor = begin
        }

        // Longest span first: the last recorded start reaches furthest back.
        for begin in tokenStarts.reversed() where begin < index {
            if let spoken = spokenBook(for: String(text[begin..<index])) {
                return (begin, spoken)
            }
        }
        return nil
    }

    /// Renders one reference in the configured style.
    private func spoken(book: String, chapter: Int64, verse: Int64, verseEnd: Int64?) -> String {
        let chapterWords = NumberSpelling.words(for: chapter)
        let verseWords = NumberSpelling.words(for: verse)

        let verses: String
        if let verseEnd {
            let endWords = NumberSpelling.words(for: verseEnd)
            verses = "\(verseWords) through \(endWords)"
        } else {
            verses = verseWords
        }

        switch style {
        case .chapterVerse:
            return "\(book) \(chapterWords), \(verses)"
        case .chapterColonVerse:
            return "\(book) \(chapterWords) colon \(verses)"
        case .spokenFull:
            let verseNoun = verseEnd == nil ? "verse" : "verses"
            return "\(book) chapter \(chapterWords), \(verseNoun) \(verses)"
        }
    }

    /// Resolves a written surface form to its spoken book name.
    static func spokenBook(for written: String) -> String? {
        let key = written
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .lowercased()
        // Collapse internal whitespace so "1  John" resolves like "1 John".
        let collapsed = key.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return lookup[collapsed] ?? lookup[collapsed.replacingOccurrences(of: " ", with: "")]
    }

    private static let lookup: [String: String] = {
        var map: [String: String] = [:]
        // Insert in reverse so that longest-first ordering leaves the most
        // specific form as the surviving entry for duplicate keys.
        for entry in bookForms.reversed() {
            map[entry.written] = entry.spoken
        }
        return map
    }()

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    /// Every distinct spoken book name, for testing and documentation.
    public static var canonicalBookNames: [String] {
        Array(Set(bookForms.map(\.spoken))).sorted()
    }
}
