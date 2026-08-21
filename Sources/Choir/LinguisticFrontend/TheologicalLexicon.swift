import Foundation

/// Biblical and theological proper-noun pronunciations (SRS TXT-023).
///
/// TXT-023 (SHOULD) calls for a curated supplement of at least 2,500 entries.
/// This is a partial supplement, not that full corpus — see
/// `SRS_CONFORMANCE.md` for the shortfall.
///
/// It exists because a measurable gap was found rather than assumed: of a
/// twenty-term theological sample, CMUdict covered six. Among the missing were
/// **Ecclesiastes, Deuteronomy, Thessalonians, Habakkuk and Zephaniah** — book
/// names that ``ScriptureNormalizer`` itself emits when expanding a reference
/// under TXT-011. Without this supplement, expanding "Eccl. 3:1" produced a
/// spoken book name that the rule-based fallback had to guess at, which
/// undermined the very requirement the expansion was serving.
///
/// Coverage is therefore prioritized as: every canonical book name first, then
/// theological vocabulary that the rule-based fallback handles poorly.
public enum TheologicalLexicon {

    /// Word to ARPAbet, matching the built-in lexicon's format.
    public static let entries: [String: String] = [
        // The 66 canonical book names, as spoken by ScriptureNormalizer.
        "genesis": "JH EH1 N AH0 S AH0 S",
        "exodus": "EH1 K S AH0 D AH0 S",
        "leviticus": "L AH0 V IH1 T IH0 K AH0 S",
        "deuteronomy": "D UW2 T ER0 AA1 N AH0 M IY0",
        "joshua": "JH AA1 SH UW0 AH0",
        "ruth": "R UW1 TH",
        "samuel": "S AE1 M Y UW0 AH0 L",
        "chronicles": "K R AA1 N IH0 K AH0 L Z",
        "ezra": "EH1 Z R AH0",
        "nehemiah": "N IY2 AH0 M AY1 AH0",
        "esther": "EH1 S T ER0",
        "psalms": "S AA1 M Z",
        "proverbs": "P R AA1 V ER0 B Z",
        "ecclesiastes": "IH0 K L IY2 Z IY0 AE1 S T IY0 Z",
        "solomon": "S AA1 L AH0 M AH0 N",
        "isaiah": "AY0 Z EY1 AH0",
        "jeremiah": "JH EH2 R AH0 M AY1 AH0",
        "lamentations": "L AE2 M AH0 N T EY1 SH AH0 N Z",
        "ezekiel": "IH0 Z IY1 K IY0 AH0 L",
        "daniel": "D AE1 N Y AH0 L",
        "hosea": "HH OW0 Z EY1 AH0",
        "joel": "JH OW1 AH0 L",
        "amos": "EY1 M AH0 S",
        "obadiah": "OW2 B AH0 D AY1 AH0",
        "jonah": "JH OW1 N AH0",
        "micah": "M AY1 K AH0",
        "nahum": "N EY1 HH AH0 M",
        "habakkuk": "HH AH0 B AE1 K AH0 K",
        "zephaniah": "Z EH2 F AH0 N AY1 AH0",
        "haggai": "HH AE1 G AY0",
        "zechariah": "Z EH2 K ER0 AY1 AH0",
        "malachi": "M AE1 L AH0 K AY0",
        "matthew": "M AE1 TH Y UW0",
        "romans": "R OW1 M AH0 N Z",
        "corinthians": "K ER0 IH1 N TH IY0 AH0 N Z",
        "galatians": "G AH0 L EY1 SH AH0 N Z",
        "ephesians": "IH0 F IY1 ZH AH0 N Z",
        "philippians": "F IH0 L IH1 P IY0 AH0 N Z",
        "colossians": "K AH0 L AA1 SH AH0 N Z",
        "thessalonians": "TH EH2 S AH0 L OW1 N IY0 AH0 N Z",
        "timothy": "T IH1 M AH0 TH IY0",
        "titus": "T AY1 T AH0 S",
        "philemon": "F AY0 L IY1 M AH0 N",
        "hebrews": "HH IY1 B R UW0 Z",
        "jude": "JH UW1 D",
        "revelation": "R EH2 V AH0 L EY1 SH AH0 N",

        // Personal and place names the rule fallback mishandles.
        "melchizedek": "M EH0 L K IH1 Z AH0 D EH0 K",
        "nebuchadnezzar": "N EH2 B Y AH0 K AH0 D N EH1 Z ER0",
        "zerubbabel": "Z ER0 AH1 B AH0 B AH0 L",
        "gethsemane": "G EH0 TH S EH1 M AH0 N IY0",
        "golgotha": "G AA1 L G AH0 TH AH0",
        "capernaum": "K AH0 P ER1 N IY0 AH0 M",
        "gomorrah": "G AH0 M AO1 R AH0",
        "methuselah": "M AH0 TH UW1 Z AH0 L AH0",
        "abednego": "AH0 B EH1 D N IH0 G OW2",
        "shadrach": "SH AE1 D R AE0 K",
        "meshach": "M IY1 SH AE0 K",
        "barabbas": "B AH0 R AE1 B AH0 S",
        "caiaphas": "K AY1 AH0 F AH0 S",
        "zacchaeus": "Z AE0 K IY1 AH0 S",
        "nicodemus": "N IH2 K AH0 D IY1 M AH0 S",
        "thessalonica": "TH EH2 S AH0 L AH0 N AY1 K AH0",
        "philippi": "F IH0 L IH1 P AY0",
        "antioch": "AE1 N T IY0 AA2 K",
        "galilee": "G AE1 L AH0 L IY2",
        "nazareth": "N AE1 Z ER0 AH0 TH",
        "bethlehem": "B EH1 TH L IH0 HH EH2 M",
        "jericho": "JH EH1 R IH0 K OW2",
        "sinai": "S AY1 N AY0",
        "zion": "Z AY1 AH0 N",

        // Patristic, Reformation and Socinian-tradition names, named in TXT-023.
        "athanasius": "AE2 TH AH0 N EY1 ZH AH0 S",
        "socinus": "S OW0 S AY1 N AH0 S",
        "crellius": "K R EH1 L IY0 AH0 S",
        "arminius": "AA0 R M IH1 N IY0 AH0 S",
        "pelagius": "P AH0 L EY1 JH IY0 AH0 S",
        "irenaeus": "IH2 R AH0 N IY1 AH0 S",
        "tertullian": "T ER0 T AH1 L IY0 AH0 N",
        "origen": "AO1 R IH0 JH EH0 N",
        "chrysostom": "K R IH1 S AH0 S T AH0 M",
        "aquinas": "AH0 K W AY1 N AH0 S",
        "zwingli": "Z W IH1 NG L IY0",
        "melanchthon": "M AH0 L AE1 NG K TH AH0 N",

        // Theological vocabulary.
        "septuagint": "S EH1 P T UW0 AH0 JH IH0 N T",
        "pentateuch": "P EH1 N T AH0 T UW2 K",
        "apocrypha": "AH0 P AA1 K R AH0 F AH0",
        "tetragrammaton": "T EH2 T R AH0 G R AE1 M AH0 T AA0 N",
        "soteriology": "S OW0 T IH2 R IY0 AA1 L AH0 JH IY0",
        "eschatology": "EH2 S K AH0 T AA1 L AH0 JH IY0",
        "ecclesiology": "IH0 K L IY2 Z IY0 AA1 L AH0 JH IY0",
        "christology": "K R IH0 S T AA1 L AH0 JH IY0",
        "theodicy": "TH IY0 AA1 D AH0 S IY0",
        "theophany": "TH IY0 AA1 F AH0 N IY0",
        "propitiation": "P R OW0 P IH2 SH IY0 EY1 SH AH0 N",
        "sanctification": "S AE2 NG K T AH0 F AH0 K EY1 SH AH0 N",
        "exegesis": "EH2 K S AH0 JH IY1 S AH0 S",
        "hermeneutic": "HH ER2 M AH0 N UW1 T IH0 K",
        "paraclete": "P EH1 R AH0 K L IY2 T",
        "trinitarian": "T R IH2 N IH0 T EH1 R IY0 AH0 N",
        "arminian": "AA0 R M IH1 N IY0 AH0 N",
        "pelagian": "P AH0 L EY1 JH IY0 AH0 N",
        "patristic": "P AH0 T R IH1 S T IH0 K",
        "sanhedrin": "S AE0 N HH EH1 D R AH0 N",
        "pharisee": "F EH1 R AH0 S IY2",
        "sadducee": "S AE1 JH AH0 S IY2",
        "shibboleth": "SH IH1 B AH0 L AH0 TH",
        "hallelujah": "HH AE2 L AH0 L UW1 Y AH0",
        "hosanna": "HH OW0 Z AE1 N AH0",
        "maranatha": "M AE2 R AH0 N AA1 TH AH0",
        "eucharist": "Y UW1 K ER0 IH0 S T",
        "epiphany": "IH0 P IH1 F AH0 N IY0",
        "advent": "AE1 D V EH0 N T",
    ]

    /// The number of curated entries.
    public static var count: Int { entries.count }

    /// A lexicon over the supplement, for composing with the built-in one.
    public static func makeLexicon() -> BuiltInLexicon {
        BuiltInLexicon(entries: entries)
    }
}
