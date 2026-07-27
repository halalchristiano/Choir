import Foundation

/// SSML (Speech Synthesis Markup Language)-like markup for controlling synthesis.
///
/// Supports a subset of SSML tags for controlling pitch, rate, volume, and prosody.
public struct SSMLParser: Sendable {
    /// A text segment with associated markup control.
    public struct SegmentTag: Sendable {
        /// The text content of this segment.
        public let text: String

        /// Pitch adjustment in semitones.
        public var pitch: Int? = nil

        /// Rate multiplier (0.5 to 2.0).
        public var rate: Double? = nil

        /// Volume adjustment in dB.
        public var volume: Double? = nil

        /// Emphasis level: "strong", "moderate", "reduced", or "none".
        public var emphasis: String? = nil

        /// Pause duration in milliseconds.
        public var pause: Int? = nil

        /// Whether to apply emphasis/stress.
        public var stressed: Bool = false

        public init(text: String) {
            self.text = text
        }
    }

    public init() {}

    /// Parses SSML markup and extracts segments with control tags.
    ///
    /// Supported tags:
    /// - `<prosody pitch="+5" rate="1.2">text</prosody>` — Pitch/rate control
    /// - `<emphasis level="strong">text</emphasis>` — Emphasis
    /// - `<pause time="500ms" />` — Silence
    ///
    /// - Parameter text: SSML text with markup.
    /// - Returns: An array of segments with control information.
    public func parse(_ text: String) -> [SegmentTag] {
        var segments: [SegmentTag] = []
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "<" {
                // Find end of tag
                if let tagEnd = text[i...].firstIndex(of: ">") {
                    let tagContent = String(text[text.index(after: i)..<tagEnd])

                    // Skip self-closing and closing tags
                    if !tagContent.hasSuffix("/") && !tagContent.hasPrefix("/") {
                        let parts = tagContent.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                        if let tagName = parts.first {
                            let attrs = parts.count > 1 ? String(parts[1]) : ""

                            // Find matching closing tag
                            let closingTag = "</\(tagName)>"
                            let searchStart = text.index(after: tagEnd)
                            if let closingStart = text[searchStart...].range(of: closingTag) {
                                let contentStart = searchStart
                                let content = String(text[contentStart..<closingStart.lowerBound])

                                var segment = SegmentTag(text: content)
                                segment = parseAttributes(attrs, into: segment)
                                if !content.isEmpty {
                                    segments.append(segment)
                                }

                                i = closingStart.upperBound
                                continue
                            }
                        }
                    }

                    i = text.index(after: tagEnd)
                } else {
                    i = text.index(after: i)
                }
            } else {
                // Accumulate non-tag text
                var plainText = ""
                while i < text.endIndex && text[i] != "<" {
                    plainText.append(text[i])
                    i = text.index(after: i)
                }

                let cleaned = plainText.trimmingCharacters(in: .whitespaces)
                if !cleaned.isEmpty {
                    segments.append(SegmentTag(text: cleaned))
                }
            }
        }

        return segments.filter { !$0.text.isEmpty }
    }

    /// Extracts plain text from SSML markup.
    public func extractPlainText(from ssml: String) -> String {
        var text = ssml

        // Remove all tags
        while let tagStart = text.firstIndex(of: "<"), let tagEnd = text[tagStart...].firstIndex(of: ">") {
            text.removeSubrange(tagStart...tagEnd)
        }

        // Unescape HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")

        return text
    }

    /// Parses attributes from a tag string and applies them to a segment.
    private func parseAttributes(_ attrStr: String, into segment: SegmentTag) -> SegmentTag {
        var result = segment

        // Simple attribute parsing
        if let pitchMatch = extractQuotedValue(attrStr, for: "pitch") {
            result.pitch = parsePitchValue(pitchMatch)
        }

        if let rateMatch = extractQuotedValue(attrStr, for: "rate") {
            result.rate = parseRateValue(rateMatch)
        }

        if let levelMatch = extractQuotedValue(attrStr, for: "level") {
            result.emphasis = levelMatch
            result.stressed = levelMatch == "strong"
        }

        return result
    }

    /// Extracts the value of a quoted attribute (e.g., pitch="5" → "5").
    private func extractQuotedValue(_ attrStr: String, for attr: String) -> String? {
        let pattern = "\(attr)=\"([^\"]*)\""
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: attrStr, range: NSRange(attrStr.startIndex..<attrStr.endIndex, in: attrStr)),
           let valueRange = Range(match.range(at: 1), in: attrStr) {
            return String(attrStr[valueRange])
        }
        return nil
    }

    /// Parses pitch value (e.g., "+5", "high", "-3").
    private func parsePitchValue(_ value: String) -> Int? {
        if let num = Int(value) {
            return num
        }
        switch value.lowercased() {
        case "high": return 5
        case "medium": return 0
        case "low": return -5
        case "x-high": return 10
        case "x-low": return -10
        default: return nil
        }
    }

    /// Parses rate value (e.g., "1.2", "slow", "fast").
    private func parseRateValue(_ value: String) -> Double? {
        if let rate = Double(value) {
            return max(0.5, min(2.0, rate))
        }
        switch value.lowercased() {
        case "slow": return 0.8
        case "medium": return 1.0
        case "fast": return 1.2
        case "x-slow": return 0.6
        case "x-fast": return 1.5
        default: return nil
        }
    }
}
