import Foundation

nonisolated struct ParsedBook {
    struct Chapter {
        let title: String
        let text: String
    }

    var title: String
    var author: String?
    var coverImage: Data?
    var chapters: [Chapter]
}

/// Reads an EPUB (2 or 3): container.xml → OPF manifest and spine → XHTML chapters, keeping the cover image
/// and chapter titles from the navigation document or NCX where available.
nonisolated enum EPUBParser {
    enum EPUBError: LocalizedError {
        case missingPackage, emptyBook

        var errorDescription: String? {
            switch self {
            case .missingPackage: "This EPUB has no package document."
            case .emptyBook: "No readable text was found in this EPUB."
            }
        }
    }

    static func parse(url: URL) throws -> ParsedBook {
        let archive = try ZipArchive(url: url)
        let container = String(decoding: try archive.contents(of: "META-INF/container.xml"), as: UTF8.self)
        guard let packagePath = firstAttribute("full-path", inTag: "rootfile", of: container) else {
            throw EPUBError.missingPackage
        }
        let package = String(decoding: try archive.contents(of: packagePath), as: UTF8.self)
        let baseDirectory = (packagePath as NSString).deletingLastPathComponent

        let manifest = manifestItems(in: package)
        let spine = spineReferences(in: package)
        let navigationTitles = chapterTitles(archive: archive, package: package, manifest: manifest, baseDirectory: baseDirectory)

        var chapters: [ParsedBook.Chapter] = []
        for idref in spine {
            guard let item = manifest[idref], item.mediaType.contains("html") else { continue }
            let path = resolve(item.href, relativeTo: baseDirectory)
            guard let data = try? archive.contents(of: path) else { continue }
            let html = String(decoding: data, as: UTF8.self)
            let text = HTMLText.plainText(from: html)
            guard ChineseText.hanCharacterCount(text) > 0 || text.count > 40 else { continue }
            let fileName = (path as NSString).lastPathComponent
            let title = navigationTitles[path] ?? navigationTitles[fileName]
                ?? HTMLText.firstHeading(in: html)
                ?? HTMLText.title(in: html)
                ?? "Chapter \(chapters.count + 1)"
            chapters.append(.init(title: title, text: text))
        }
        guard !chapters.isEmpty else { throw EPUBError.emptyBook }

        let title = HTMLText.decodeEntities(elementText("dc:title", in: package) ?? url.deletingPathExtension().lastPathComponent)
        let author = elementText("dc:creator", in: package).map(HTMLText.decodeEntities)
        let cover = coverImage(archive: archive, package: package, manifest: manifest, baseDirectory: baseDirectory)
        return ParsedBook(title: title, author: author, coverImage: cover, chapters: chapters)
    }

    struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: String
    }

    static func manifestItems(in package: String) -> [String: ManifestItem] {
        var items: [String: ManifestItem] = [:]
        for tag in tags(named: "item", in: package) {
            guard let id = attribute("id", in: tag), let href = attribute("href", in: tag) else { continue }
            items[id] = ManifestItem(
                id: id,
                href: href,
                mediaType: attribute("media-type", in: tag) ?? "",
                properties: attribute("properties", in: tag) ?? ""
            )
        }
        return items
    }

    static func spineReferences(in package: String) -> [String] {
        tags(named: "itemref", in: package).compactMap { attribute("idref", in: $0) }
    }

    private static func chapterTitles(
        archive: ZipArchive, package: String, manifest: [String: ManifestItem], baseDirectory: String
    ) -> [String: String] {
        var titles: [String: String] = [:]
        if let nav = manifest.values.first(where: { $0.properties.contains("nav") }) {
            let navPath = resolve(nav.href, relativeTo: baseDirectory)
            if let data = try? archive.contents(of: navPath) {
                let html = String(decoding: data, as: UTF8.self)
                let navDirectory = (navPath as NSString).deletingLastPathComponent
                let pattern = try! NSRegularExpression(pattern: #"<a\b[^>]*href\s*=\s*["']([^"'#]+)[^"']*["'][^>]*>([\s\S]*?)</a>"#, options: .caseInsensitive)
                for match in pattern.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
                    guard let hrefRange = Range(match.range(at: 1), in: html), let textRange = Range(match.range(at: 2), in: html) else { continue }
                    let path = resolve(String(html[hrefRange]), relativeTo: navDirectory)
                    let title = HTMLText.plainText(from: String(html[textRange])).replacingOccurrences(of: "\n", with: " ")
                    if titles[path] == nil, !title.isEmpty { titles[path] = title }
                }
            }
        }
        if titles.isEmpty, let ncx = manifest.values.first(where: { $0.mediaType == "application/x-dtbncx+xml" }) {
            let ncxPath = resolve(ncx.href, relativeTo: baseDirectory)
            if let data = try? archive.contents(of: ncxPath) {
                let xml = String(decoding: data, as: UTF8.self)
                let ncxDirectory = (ncxPath as NSString).deletingLastPathComponent
                let pattern = try! NSRegularExpression(pattern: #"<navLabel>\s*<text>([\s\S]*?)</text>\s*</navLabel>\s*<content\s+src\s*=\s*["']([^"'#]+)"#, options: .caseInsensitive)
                for match in pattern.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)) {
                    guard let textRange = Range(match.range(at: 1), in: xml), let srcRange = Range(match.range(at: 2), in: xml) else { continue }
                    let path = resolve(String(xml[srcRange]), relativeTo: ncxDirectory)
                    let title = HTMLText.decodeEntities(String(xml[textRange])).trimmingCharacters(in: .whitespacesAndNewlines)
                    if titles[path] == nil, !title.isEmpty { titles[path] = title }
                }
            }
        }
        return titles
    }

    private static func coverImage(
        archive: ZipArchive, package: String, manifest: [String: ManifestItem], baseDirectory: String
    ) -> Data? {
        var coverItem = manifest.values.first { $0.properties.contains("cover-image") }
        if coverItem == nil {
            let coverID = tags(named: "meta", in: package)
                .first { attribute("name", in: $0) == "cover" }
                .flatMap { attribute("content", in: $0) }
            coverItem = coverID.flatMap { manifest[$0] }
        }
        if coverItem == nil {
            coverItem = manifest.values.first { $0.mediaType.hasPrefix("image/") && $0.href.lowercased().contains("cover") }
        }
        guard let coverItem, coverItem.mediaType.hasPrefix("image/") else { return nil }
        return try? archive.contents(of: resolve(coverItem.href, relativeTo: baseDirectory))
    }

    static func resolve(_ href: String, relativeTo directory: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        var components = directory.isEmpty ? [] : directory.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/").map(String.init) {
            switch part {
            case ".": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(part)
            }
        }
        return components.joined(separator: "/")
    }

    private static func tags(named name: String, in xml: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "<(?:[A-Za-z]+:)?\(name)\\b[^>]*>", options: .caseInsensitive)
        return pattern.matches(in: xml, range: NSRange(xml.startIndex..., in: xml)).compactMap { match in
            Range(match.range, in: xml).map { String(xml[$0]) }
        }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = try! NSRegularExpression(pattern: "\\s\(name)\\s*=\\s*[\"']([^\"']*)[\"']", options: .caseInsensitive)
        guard let match = pattern.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return String(tag[range])
    }

    private static func firstAttribute(_ name: String, inTag tagName: String, of xml: String) -> String? {
        tags(named: tagName, in: xml).lazy.compactMap { attribute(name, in: $0) }.first
    }

    private static func elementText(_ name: String, in xml: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let pattern = try! NSRegularExpression(pattern: "<\(escaped)\\b[^>]*>([\\s\\S]*?)</\(escaped)>", options: .caseInsensitive)
        guard let match = pattern.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        let text = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
