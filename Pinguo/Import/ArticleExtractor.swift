import Foundation

/// Readability-style extraction: keeps the main run of text paragraphs and drops navigation, ads and boilerplate.
nonisolated enum ArticleExtractor {
    enum ArticleError: LocalizedError {
        case badURL, noContent

        var errorDescription: String? {
            switch self {
            case .badURL: "That doesn't look like a web address."
            case .noContent: "No Chinese article text was found on that page."
            }
        }
    }

    static func fetch(_ address: String) async throws -> ParsedBook {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"), url.host != nil else {
            throw ArticleError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.5", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        let html = decode(data, declaredEncoding: response.textEncodingName)
        return try extract(html: html, url: url)
    }

    static func extract(html: String, url: URL?) throws -> ParsedBook {
        let title = metaContent("og:title", in: html) ?? HTMLText.title(in: html) ?? HTMLText.firstHeading(in: html) ?? url?.host ?? "Article"
        let author = metaContent("author", in: html) ?? metaContent("og:site_name", in: html)
        let body = mainText(in: html)
        guard ChineseText.hanCharacterCount(body) >= 20 else { throw ArticleError.noContent }
        return ParsedBook(title: cleanTitle(title), author: author, coverImage: nil, chapters: [.init(title: cleanTitle(title), text: body)])
    }

    static func mainText(in html: String) -> String {
        var cleaned = html.replacingOccurrences(
            of: #"<(script|style|noscript|nav|header|footer|aside|form|iframe|svg|button)\b[^>]*>[\s\S]*?</\1>"#,
            with: "", options: [.regularExpression, .caseInsensitive]
        )
        if let article = firstMatch(#"<article\b[^>]*>([\s\S]*?)</article>"#, in: cleaned)
            ?? firstMatch(#"<div[^>]+id=["']js_content["'][^>]*>([\s\S]*)"#, in: cleaned) {
            cleaned = article
        }
        let blocks = matches(#"<(p|h[1-4]|li|blockquote|section)\b[^>]*>([\s\S]*?)</\1>"#, in: cleaned, group: 2)
        let paragraphs = blocks.compactMap { block -> String? in
            let linkText = matches(#"<a\b[^>]*>([\s\S]*?)</a>"#, in: block, group: 1).map(HTMLText.plainText).joined()
            let text = HTMLText.plainText(from: block).replacingOccurrences(of: "\n", with: "")
            let han = ChineseText.hanCharacterCount(text)
            guard han >= 8, Double(linkText.count) < Double(text.count) * 0.5 else { return nil }
            return text
        }
        var seen = Set<String>()
        let unique = paragraphs.filter { seen.insert($0).inserted }
        if unique.count >= 2 { return unique.joined(separator: "\n") }
        return HTMLText.plainText(from: cleaned)
            .components(separatedBy: .newlines)
            .filter { ChineseText.hanCharacterCount($0) >= 8 }
            .joined(separator: "\n")
    }

    private static func cleanTitle(_ title: String) -> String {
        let separators = [" | ", " - ", "_", " – ", " — "]
        for separator in separators {
            if let range = title.range(of: separator), title.distance(from: title.startIndex, to: range.lowerBound) >= 4 {
                return String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        return title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decode(_ data: Data, declaredEncoding: String?) -> String {
        let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
        let charset = declaredEncoding?.lowercased()
            ?? head.range(of: #"charset=["']?([a-z0-9_-]+)"#, options: .regularExpression).map { String(head[$0]).replacingOccurrences(of: #"charset=["']?"#, with: "", options: .regularExpression) }
        if let charset, ["gbk", "gb2312", "gb18030"].contains(charset) {
            let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            if let text = String(data: data, encoding: gb18030) { return text }
        }
        if let charset, charset == "big5" {
            let big5 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5_HKSCS_1999.rawValue)))
            if let text = String(data: data, encoding: big5) { return text }
        }
        return DocumentImporter.decodeText(data)
    }

    private static func metaContent(_ name: String, in html: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = #"<meta[^>]+(?:property|name)=["']"# + escaped + #"["'][^>]*content=["']([^"']+)["']"#
        return firstMatch(pattern, in: html).map(HTMLText.decodeEntities)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        matches(pattern, in: text, group: 1).first
    }

    private static func matches(_ pattern: String, in text: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: group), in: text).map { String(text[$0]) }
        }
    }
}
