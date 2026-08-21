import Foundation

/// Emphasis level (SRS TXT-040).
public enum SSMLEmphasis: String, Sendable, Equatable, Codable, CaseIterable {
    case none
    case reduced
    case moderate
    case strong
}

/// `say-as` interpretation (SRS TXT-040).
public enum SSMLInterpretAs: String, Sendable, Equatable, Codable, CaseIterable {
    case characters
    case number
    case ordinal
    case date
    case scripture
}

/// A `<break>` (SRS TXT-040).
public struct SSMLBreak: Sendable, Equatable, Codable {
    public enum Strength: String, Sendable, Equatable, Codable, CaseIterable {
        case none
        case weak
        case medium
        case strong
        case paragraph

        /// Nominal duration in milliseconds when no explicit time is given.
        public var nominalMs: Double {
            switch self {
            case .none: return 0
            case .weak: return 100
            case .medium: return 300
            case .strong: return 600
            case .paragraph: return 1000
            }
        }
    }

    /// Explicit duration, which takes precedence over ``strength``.
    public var timeMs: Double?

    /// Symbolic strength, used when no explicit time is given.
    public var strength: Strength?

    public init(timeMs: Double? = nil, strength: Strength? = nil) {
        self.timeMs = timeMs
        self.strength = strength
    }

    /// The duration this break represents.
    public var resolvedMs: Double {
        let candidate = timeMs ?? strength?.nominalMs ?? Strength.medium.nominalMs
        return candidate.isFinite ? max(0, candidate) : Strength.medium.nominalMs
    }
}

/// The resolved styling applied to a run of text.
///
/// Produced by flattening the nest of enclosing tags, so a segment carries the
/// combined effect of every tag it sits inside.
public struct SSMLStyle: Sendable, Equatable, Codable {
    /// Pitch offset in semitones, summed across nested `prosody` tags.
    public var pitchSemitones: Double = 0

    /// Rate as a percentage, multiplied across nested `prosody` tags.
    public var ratePercent: Double = 100

    /// Volume offset in decibels, summed across nested `prosody` tags.
    public var volumeDb: Double = 0

    public var emphasis: SSMLEmphasis = .none

    /// Voice selected by an enclosing `<voice id="...">` (TXT-042).
    public var voiceID: String?

    /// Pronunciation forced by an enclosing `<phoneme ph="...">`.
    public var phonemeOverride: String?

    /// Interpretation forced by an enclosing `<say-as>`.
    public var interpretAs: SSMLInterpretAs?

    public init() {}
}

/// One item in the parsed stream.
public enum SSMLEvent: Sendable, Equatable {
    /// Text to be spoken with the given styling.
    case speech(text: String, style: SSMLStyle)

    /// A pause.
    case pause(SSMLBreak)

    /// A timing marker, reported in synthesis metadata (SYN-005).
    case mark(name: String)
}

/// The outcome of parsing SSML-C.
public struct SSMLParseResult: Sendable {
    public let events: [SSMLEvent]

    /// Markup warnings, returned alongside the result rather than thrown
    /// (SRS TXT-041).
    public let diagnostics: [SynthesisDiagnostic]

    public init(events: [SSMLEvent], diagnostics: [SynthesisDiagnostic] = []) {
        self.events = events
        self.diagnostics = diagnostics
    }

    /// The plain text of the stream, with markup removed.
    public var plainText: String {
        events.compactMap { event in
            if case .speech(let text, _) = event { return text }
            return nil
        }.joined()
    }

    /// The names of every mark, in order.
    public var markNames: [String] {
        events.compactMap { event in
            if case .mark(let name) = event { return name }
            return nil
        }
    }
}

/// Parses the SSML-C inline markup dialect (SRS TXT-040).
///
/// Supports, per the specification:
///
/// - `<break time="500ms"/>` and `<break strength="weak|medium|strong|paragraph"/>`
/// - `<emphasis level="reduced|moderate|strong">`
/// - `<prosody pitch="±Nst" rate="N%" volume="±NdB">`, nestable
/// - `<phoneme ph="...">` inline pronunciation override
/// - `<say-as interpret-as="characters|number|ordinal|date|scripture">`
/// - `<voice id="...">` for mid-text voice switching (TXT-042)
/// - `<mark name="..."/>` timing markers, surfaced in synthesis metadata
///
/// Malformed markup degrades gracefully (TXT-041): an unparseable tag is
/// stripped and its text content is still spoken, with a diagnostic recorded.
/// In strict mode the parser throws instead.
public struct SSMLCParser: Sendable {
    /// Whether malformed markup throws rather than being reported (TXT-041).
    public let strict: Bool

    public init(strict: Bool = false) {
        self.strict = strict
    }

    private static let voidTags: Set<String> = ["break", "mark"]
    private static let knownTags: Set<String> = [
        "break", "mark", "emphasis", "prosody", "phoneme", "say-as", "voice", "speak",
    ]

    /// Parses `text`, returning the event stream and any diagnostics.
    ///
    /// - Throws: ``ChoirError/textProcessingFailed(reason:)`` in strict mode
    ///   when the markup is malformed.
    public func parse(_ text: String) throws -> SSMLParseResult {
        var events: [SSMLEvent] = []
        var diagnostics: [SynthesisDiagnostic] = []
        var styleStack: [SSMLStyle] = [SSMLStyle()]
        var openTags: [String] = []

        var index = text.startIndex
        var pending = ""

        func flushText() {
            guard !pending.isEmpty else { return }
            events.append(.speech(text: pending, style: styleStack[styleStack.count - 1]))
            pending = ""
        }

        func report(_ message: String) throws {
            if strict {
                throw ChoirError.textProcessingFailed(reason: message)
            }
            diagnostics.append(SynthesisDiagnostic(message: message))
        }

        while index < text.endIndex {
            guard text[index] == "<" else {
                pending.append(text[index])
                index = text.index(after: index)
                continue
            }

            // A '<' with no '>' after it is literal text, not a tag.
            guard let close = text[index...].firstIndex(of: ">") else {
                try report("Unterminated tag: no '>' after '<'")
                pending.append(contentsOf: text[index...])
                index = text.endIndex
                continue
            }

            let raw = String(text[text.index(after: index)..<close])
            index = text.index(after: close)

            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                try report("Empty tag '<>'")
                continue
            }

            flushText()

            if trimmed.hasPrefix("/") {
                // Closing tag.
                let closingBody = String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                let name = closingBody.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
                guard !name.isEmpty else {
                    try report("Closing tag has no name")
                    continue
                }
                if closingBody != name {
                    try report("Closing tag </\(name)> must not contain attributes")
                }
                guard let matchingIndex = openTags.lastIndex(of: name) else {
                    try report("Closing tag </\(name)> with no matching opening tag")
                    continue
                }
                if matchingIndex != openTags.index(before: openTags.endIndex) {
                    let implicitlyClosed = openTags[(matchingIndex + 1)...].reversed().joined(separator: ", ")
                    try report("Mismatched closing tag </\(name)>; implicitly closed \(implicitlyClosed)")
                }
                let removalCount = openTags.count - matchingIndex
                openTags.removeSubrange(matchingIndex...)
                for _ in 0..<removalCount {
                    if styleStack.count > 1 { styleStack.removeLast() }
                }
                continue
            }

            let selfClosing = trimmed.hasSuffix("/")
            let body = selfClosing ? String(trimmed.dropLast()) : trimmed
            let (name, attributes) = Self.splitTag(body)

            guard Self.knownTags.contains(name) else {
                try report("Unknown tag <\(name)>; its content will still be spoken")
                continue
            }

            if name == "speak" {
                // Document wrapper: no styling of its own.
                if !selfClosing { openTags.append(name); styleStack.append(styleStack[styleStack.count - 1]) }
                continue
            }

            if Self.voidTags.contains(name) {
                switch name {
                case "break":
                    let parsed = try Self.parseBreak(attributes) { message in
                        try report(message)
                    }
                    events.append(.pause(parsed))
                case "mark":
                    if let rawName = attributes["name"] {
                        let markName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if markName.isEmpty {
                            try report("<mark> has an empty name attribute")
                        } else {
                            events.append(.mark(name: markName))
                        }
                    } else {
                        try report("<mark> is missing a name attribute")
                    }
                default:
                    break
                }
                if !selfClosing {
                    try report("<\(name)> should be self-closing")
                }
                continue
            }

            // A container tag: push a style derived from the enclosing one.
            var style = styleStack[styleStack.count - 1]
            try Self.apply(name: name, attributes: attributes, to: &style) { message in
                try report(message)
            }

            if selfClosing {
                // Self-closing container has no content; nothing to style.
                continue
            }
            styleStack.append(style)
            openTags.append(name)
        }

        flushText()

        // Decode XML entities in the spoken text. Doing this after tag
        // scanning rather than before is deliberate: decoding "&lt;" early
        // would manufacture an angle bracket the tag scanner then mistakes
        // for markup.
        events = events.map { event in
            if case .speech(let text, let style) = event {
                return .speech(text: Self.decodingEntities(text), style: style)
            }
            return event
        }

        // Unclosed containers are tolerated: their styling simply ends here.
        for open in openTags.reversed() {
            try report("Unclosed tag <\(open)>; styling applied to end of input")
        }

        return SSMLParseResult(events: events, diagnostics: diagnostics)
    }

    /// Decodes the XML entities SSML documents carry.
    static func decodingEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = decodingNumericEntities(text)
        // Ampersand last, so "&amp;lt;" decodes to "&lt;" and not to "<".
        for (entity, character) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&apos;", "'"), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&"),
        ] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    /// Decodes decimal and hexadecimal XML numeric character references.
    private static func decodingNumericEntities(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&",
                  let semicolon = text[index...].prefix(14).firstIndex(of: ";")
            else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let bodyStart = text.index(after: index)
            let body = String(text[bodyStart..<semicolon])
            let scalarValue: UInt32?
            if body.hasPrefix("#x") || body.hasPrefix("#X") {
                scalarValue = UInt32(body.dropFirst(2), radix: 16)
            } else if body.hasPrefix("#") {
                scalarValue = UInt32(body.dropFirst(), radix: 10)
            } else {
                scalarValue = nil
            }

            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                result.unicodeScalars.append(scalar)
                index = text.index(after: semicolon)
            } else {
                result.append(text[index])
                index = text.index(after: index)
            }
        }
        return result
    }

    // MARK: - Tag handling

    private static func apply(
        name: String,
        attributes: [String: String],
        to style: inout SSMLStyle,
        report: (String) throws -> Void
    ) rethrows {
        switch name {
        case "emphasis":
            let level = attributes["level"]?.lowercased() ?? "moderate"
            if let parsed = SSMLEmphasis(rawValue: level) {
                style.emphasis = parsed
            } else {
                try report("Unknown emphasis level '\(level)'; using moderate")
                style.emphasis = .moderate
            }

        case "prosody":
            if let pitch = attributes["pitch"] {
                if let semitones = parseSemitones(pitch) {
                    style.pitchSemitones += semitones
                } else {
                    try report("Unparseable prosody pitch '\(pitch)'")
                }
            }
            if let rate = attributes["rate"] {
                if let percent = parsePercent(rate) {
                    // Nested rates compound rather than replace.
                    style.ratePercent = style.ratePercent * percent / 100
                } else {
                    try report("Unparseable prosody rate '\(rate)'")
                }
            }
            if let volume = attributes["volume"] {
                if let db = parseDecibels(volume) {
                    style.volumeDb += db
                } else {
                    try report("Unparseable prosody volume '\(volume)'")
                }
            }

        case "phoneme":
            if let ph = attributes["ph"], !ph.isEmpty {
                style.phonemeOverride = ph
            } else {
                try report("<phoneme> is missing a ph attribute")
            }

        case "say-as":
            let value = attributes["interpret-as"]?.lowercased() ?? ""
            if let parsed = SSMLInterpretAs(rawValue: value) {
                style.interpretAs = parsed
            } else {
                try report("Unknown say-as interpret-as '\(value)'")
            }

        case "voice":
            if let id = attributes["id"], !id.isEmpty {
                style.voiceID = id
            } else {
                try report("<voice> is missing an id attribute")
            }

        default:
            break
        }
    }

    private static func parseBreak(
        _ attributes: [String: String],
        report: (String) throws -> Void
    ) rethrows -> SSMLBreak {
        var result = SSMLBreak()
        if let time = attributes["time"] {
            if let duration = parseDuration(time) {
                result.timeMs = duration
            } else {
                try report("Unparseable break time '\(time)'; using strength or medium default")
            }
        }
        if let strength = attributes["strength"]?.lowercased() {
            if let parsed = SSMLBreak.Strength(rawValue: strength) {
                result.strength = parsed
            } else {
                try report("Unknown break strength '\(strength)'; using medium default")
            }
        }
        return result
    }

    // MARK: - Attribute scalars

    /// "500ms", "1.5s", "500" (milliseconds assumed).
    static func parseDuration(_ value: String) -> Double? {
        let text = value.trimmingCharacters(in: .whitespaces).lowercased()
        let parsed: Double?
        if text.hasSuffix("ms") {
            parsed = Double(text.dropLast(2))
        } else if text.hasSuffix("s") {
            parsed = Double(text.dropLast(1)).map { $0 * 1000 }
        } else {
            parsed = Double(text)
        }
        guard let parsed, parsed.isFinite, parsed >= 0 else { return nil }
        return parsed
    }

    /// "+5st", "-3st", "+5", "5".
    static func parseSemitones(_ value: String) -> Double? {
        var text = value.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasSuffix("st") { text = String(text.dropLast(2)) }
        if text.hasPrefix("+") { text = String(text.dropFirst()) }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// "120%", "1.2" (a bare multiplier), "120".
    static func parsePercent(_ value: String) -> Double? {
        var text = value.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasSuffix("%") {
            text = String(text.dropLast())
            guard let value = Double(text), value.isFinite, value > 0 else { return nil }
            return value
        }
        guard let raw = Double(text), raw.isFinite, raw > 0 else { return nil }
        // A bare value at or below 3 reads as a multiplier, as SSML authors write.
        return raw <= 3 ? raw * 100 : raw
    }

    /// "+6dB", "-3db", "+6".
    static func parseDecibels(_ value: String) -> Double? {
        var text = value.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasSuffix("db") { text = String(text.dropLast(2)) }
        if text.hasPrefix("+") { text = String(text.dropFirst()) }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// Splits "prosody pitch=\"+5st\" rate=\"120%\"" into its name and attributes.
    static func splitTag(_ body: String) -> (name: String, attributes: [String: String]) {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard let firstSpace = trimmed.firstIndex(where: { $0.isWhitespace }) else {
            return (trimmed.lowercased(), [:])
        }
        let name = String(trimmed[..<firstSpace]).lowercased()
        let rest = String(trimmed[firstSpace...])
        return (name, parseAttributes(rest))
    }

    /// Parses `key="value"` pairs, tolerating single quotes and missing quotes.
    static func parseAttributes(_ text: String) -> [String: String] {
        var attributes: [String: String] = [:]
        var index = text.startIndex

        while index < text.endIndex {
            // Skip to the next key.
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }

            var key = ""
            while index < text.endIndex, text[index] != "=", !text[index].isWhitespace {
                key.append(text[index])
                index = text.index(after: index)
            }
            // Skip whitespace before '='.
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex, text[index] == "=" else {
                if !key.isEmpty { attributes[key.lowercased()] = "" }
                continue
            }
            index = text.index(after: index)  // consume '='
            while index < text.endIndex, text[index].isWhitespace {
                index = text.index(after: index)
            }
            guard index < text.endIndex else { break }

            var value = ""
            if text[index] == "\"" || text[index] == "'" {
                let quote = text[index]
                index = text.index(after: index)
                while index < text.endIndex, text[index] != quote {
                    value.append(text[index])
                    index = text.index(after: index)
                }
                if index < text.endIndex { index = text.index(after: index) }
            } else {
                while index < text.endIndex, !text[index].isWhitespace {
                    value.append(text[index])
                    index = text.index(after: index)
                }
            }

            if !key.isEmpty { attributes[key.lowercased()] = value }
        }
        return attributes
    }
}
