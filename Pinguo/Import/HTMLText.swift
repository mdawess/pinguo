import Foundation

/// Turns XHTML/HTML into plain text with one paragraph per line. Regex-based on purpose: EPUB XHTML is often
/// not well-formed enough for XMLParser (undeclared entities, stray tags).
nonisolated enum HTMLText {
    static func plainText(from html: String) -> String {
        var text = html
        text = replace(#"<!--[\s\S]*?-->"#, in: text, with: "")
        text = replace(#"<(head|script|style|rt|rp|nav)\b[^>]*>[\s\S]*?</\1>"#, in: text, with: "")
        text = replace(#"<br\s*/?>"#, in: text, with: "\n")
        text = replace(#"</?(p|div|h[1-6]|li|blockquote|tr|section|article|header|footer|figure|figcaption|dt|dd)\b[^>]*>"#, in: text, with: "\n")
        text = replace(#"<[^>]+>"#, in: text, with: "")
        text = decodeEntities(text)
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{3000}\u{00A0}"))) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    static func firstHeading(in html: String) -> String? {
        guard let match = html.range(of: #"<h[1-3]\b[^>]*>([\s\S]*?)</h[1-3]>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let heading = plainText(from: String(html[match])).replacingOccurrences(of: "\n", with: " ")
        return heading.isEmpty ? nil : heading
    }

    static func title(in html: String) -> String? {
        guard let match = html.range(of: #"<title\b[^>]*>([\s\S]*?)</title>"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let title = decodeEntities(replace(#"<[^>]+>"#, in: String(html[match]), with: "")).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
            "&ldquo;": "“", "&rdquo;": "”", "&lsquo;": "‘", "&rsquo;": "’", "&hellip;": "…", "&mdash;": "—",
            "&ndash;": "–", "&middot;": "·", "&bull;": "•", "&ensp;": " ", "&emsp;": " ", "&thinsp;": " ",
        ]
        var result = text
        for (entity, replacement) in named where entity != "&amp;" {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        let pattern = try! NSRegularExpression(pattern: #"&#(x?)([0-9a-fA-F]+);"#)
        let matches = pattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
        for match in matches {
            guard let whole = Range(match.range, in: result),
                  let radixRange = Range(match.range(at: 1), in: result),
                  let digitsRange = Range(match.range(at: 2), in: result) else { continue }
            let radix = result[radixRange].isEmpty ? 10 : 16
            if let value = UInt32(result[digitsRange], radix: radix), let scalar = Unicode.Scalar(value) {
                result.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return result.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        text.replacingOccurrences(of: pattern, with: template, options: [.regularExpression, .caseInsensitive])
    }
}
