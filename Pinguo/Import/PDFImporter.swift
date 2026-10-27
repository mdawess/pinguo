import Foundation
import PDFKit
import Vision

/// PDF text via PDFKit, with Vision OCR for scanned pages. Hard-wrapped lines are rejoined into paragraphs.
nonisolated enum PDFImporter {
    enum PDFError: LocalizedError {
        case unreadable, noText

        var errorDescription: String? {
            switch self {
            case .unreadable: "This PDF could not be opened."
            case .noText: "No text was found in this PDF."
            }
        }
    }

    static func parse(url: URL, progress: (Double) -> Void = { _ in }) throws -> ParsedBook {
        guard let pdf = PDFDocument(url: url) else { throw PDFError.unreadable }
        var pageTexts: [String] = []
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            var text = page.string ?? ""
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 {
                text = recognizeText(on: page) ?? text
            }
            pageTexts.append(reflow(ChineseText.normalizingRadicals(text)))
            progress(Double(index + 1) / Double(max(1, pdf.pageCount)) * 0.5)
        }
        guard pageTexts.contains(where: { ChineseText.hanCharacterCount($0) > 0 }) else { throw PDFError.noText }

        let attributes = pdf.documentAttributes ?? [:]
        let title = (attributes[PDFDocumentAttribute.titleAttribute] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        let author = attributes[PDFDocumentAttribute.authorAttribute] as? String
        return ParsedBook(title: title, author: author, coverImage: coverImage(of: pdf), chapters: chapters(pdf: pdf, pageTexts: pageTexts))
    }

    /// Chapters from the PDF outline when present, otherwise groups of ten pages.
    private static func chapters(pdf: PDFDocument, pageTexts: [String]) -> [ParsedBook.Chapter] {
        var starts: [(page: Int, title: String)] = []
        if let root = pdf.outlineRoot {
            for index in 0..<root.numberOfChildren {
                guard let item = root.child(at: index), let page = item.destination?.page else { continue }
                starts.append((pdf.index(for: page), item.label ?? "Chapter \(index + 1)"))
            }
        }
        starts = starts.sorted { $0.page < $1.page }
        if starts.count < 2 {
            starts = stride(from: 0, to: pageTexts.count, by: 10).map { ($0, "Pages \($0 + 1)–\(min($0 + 10, pageTexts.count))") }
        } else if starts[0].page > 0 {
            starts.insert((0, "Front matter"), at: 0)
        }
        return starts.enumerated().compactMap { offset, start in
            let end = offset + 1 < starts.count ? starts[offset + 1].page : pageTexts.count
            guard start.page < end else { return nil }
            let text = pageTexts[start.page..<end].joined(separator: "\n")
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .init(title: start.title, text: text)
        }
    }

    /// Joins lines that were wrapped by page layout, keeping breaks after sentence endings or short lines.
    static func reflow(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard lines.count > 1 else { return lines.first ?? "" }
        let lengths = lines.map(\.count).sorted()
        let typical = lengths[lengths.count * 3 / 4]
        var paragraphs: [String] = []
        var current = ""
        for line in lines {
            current += current.isEmpty || !ChineseText.containsHan(line) ? (current.isEmpty ? line : " " + line) : line
            let endsSentence = line.last.map { ChineseText.sentenceTerminators.contains($0) || ChineseText.closingPunctuation.contains($0) } ?? false
            if (endsSentence && line.count < typical - 1) || line.count < typical / 2 {
                paragraphs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { paragraphs.append(current) }
        return paragraphs.joined(separator: "\n")
    }

    private static func recognizeText(on page: PDFPage) -> String? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = 2000 / max(bounds.width, bounds.height)
        let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        guard let cgImage = image.cgImage else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func coverImage(of pdf: PDFDocument) -> Data? {
        guard let page = pdf.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = 600 / max(bounds.width, bounds.height)
        let thumbnail = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        return thumbnail.jpegData(compressionQuality: 0.85)
    }
}
