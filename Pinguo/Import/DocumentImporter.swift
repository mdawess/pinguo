import Foundation
import ImageIO
import SwiftData
import UniformTypeIdentifiers

enum ImportSource: Sendable {
    case epub(URL)
    case textFile(URL)
    case pastedText(title: String, text: String)
    case prepared(ParsedBook)
}

extension ParsedBook: @unchecked Sendable {}

/// Runs the import pipeline off the main actor: extract text → chapters → sentences → words → store.
@ModelActor
actor DocumentImporter {
    private let segmenter = Segmenter()

    func run(_ source: ImportSource, into documentID: PersistentIdentifier) async {
        guard let document = modelContext.model(for: documentID) as? Document else { return }
        do {
            let book = try Self.parse(source, fallbackTitle: document.title)
            document.title = book.title
            document.author = book.author
            if let cover = book.coverImage {
                document.coverImage = Self.downsampledJPEG(cover, maxPixelSize: 600)
            }
            try store(book, in: document)
            document.status = .ready
            document.importProgress = 1
        } catch {
            document.status = .failed
            document.importError = error.localizedDescription
        }
        try? modelContext.save()
    }

    func sentenceTexts(of documentID: PersistentIdentifier) -> [[String]] {
        guard let document = modelContext.model(for: documentID) as? Document, document.status == .ready else { return [] }
        return document.orderedChapters.map { $0.orderedSentences.map(\.text) }
    }

    private func store(_ book: ParsedBook, in document: Document) throws {
        let totalCharacters = book.chapters.reduce(0) { $0 + $1.text.count }
        var processedCharacters = 0
        var sentenceOffset = 0
        var uniqueWords = Set<String>()

        for (chapterIndex, parsedChapter) in book.chapters.enumerated() {
            let chapter = Chapter(index: chapterIndex, title: parsedChapter.title, firstSentenceOffset: sentenceOffset)
            modelContext.insert(chapter)
            chapter.document = document

            var sentenceIndex = 0
            for (paragraphIndex, paragraph) in ChineseText.paragraphs(from: parsedChapter.text).enumerated() {
                for text in paragraph {
                    let tokens = segmenter.tokens(in: text)
                    for token in tokens where token.isLexical {
                        uniqueWords.insert(token.text(in: text))
                    }
                    let sentence = Sentence(index: sentenceIndex, paragraphIndex: paragraphIndex, text: text, tokens: tokens)
                    modelContext.insert(sentence)
                    sentence.chapter = chapter
                    sentenceIndex += 1
                }
            }
            sentenceOffset += sentenceIndex
            processedCharacters += parsedChapter.text.count
            document.importProgress = totalCharacters > 0 ? Double(processedCharacters) / Double(totalCharacters) : 1
            if chapterIndex % 3 == 2 { try modelContext.save() }
        }

        document.totalSentences = sentenceOffset
        document.totalCharacters = totalCharacters
        document.uniqueWords = uniqueWords.sorted()
    }

    nonisolated static func parse(_ source: ImportSource, fallbackTitle: String) throws -> ParsedBook {
        switch source {
        case .epub(let url):
            return try EPUBParser.parse(url: url)
        case .textFile(let url):
            let data = try Data(contentsOf: url)
            let text = decodeText(data)
            return ParsedBook(title: url.deletingPathExtension().lastPathComponent, author: nil, coverImage: nil, chapters: splitIntoChapters(text))
        case .pastedText(let title, let text):
            let resolvedTitle = title.isEmpty ? defaultTitle(for: text) : title
            return ParsedBook(title: resolvedTitle, author: nil, coverImage: nil, chapters: splitIntoChapters(text))
        case .prepared(let book):
            return book
        }
    }

    nonisolated static func decodeText(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let chinese = String(data: data, encoding: gb18030) { return chinese }
        if let utf16 = String(data: data, encoding: .utf16) { return utf16 }
        return String(decoding: data, as: UTF8.self)
    }

    nonisolated static func defaultTitle(for text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Untitled"
        return String(firstLine.trimmingCharacters(in: .whitespaces).prefix(16))
    }

    /// Splits on headings such as 第一章 / 第12回 / Chapter 3; otherwise into parts of roughly 4,000 characters.
    nonisolated static func splitIntoChapters(_ text: String) -> [ParsedBook.Chapter] {
        let lines = text.components(separatedBy: .newlines)
        let headingPattern = #"^\s*(第[0-9零一二三四五六七八九十百千两]+[章回节卷部篇]|Chapter\s+\d+|序章|楔子|尾声|后记)"#
        var chapters: [ParsedBook.Chapter] = []
        var currentTitle: String?
        var currentLines: [String] = []

        func flush() {
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty || currentTitle != nil {
                chapters.append(.init(title: currentTitle ?? "Part \(chapters.count + 1)", text: body))
            }
            currentLines = []
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.count <= 30, trimmed.range(of: headingPattern, options: .regularExpression) != nil {
                flush()
                currentTitle = trimmed
            } else {
                currentLines.append(line)
            }
        }
        flush()
        chapters.removeAll { $0.text.isEmpty }

        if chapters.count <= 1 {
            let body = chapters.first?.text ?? text
            let title = chapters.first?.title
            let parts = chunk(body, targetLength: 4000)
            if parts.count == 1 { return [.init(title: title ?? "Text", text: parts[0])] }
            return parts.enumerated().map { .init(title: "Part \($0.offset + 1)", text: $0.element) }
        }
        return chapters
    }

    nonisolated private static func chunk(_ text: String, targetLength: Int) -> [String] {
        var parts: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: .newlines) {
            current += paragraph + "\n"
            if current.count >= targetLength {
                parts.append(current)
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(current) }
        return parts.isEmpty ? [text] : parts
    }

    nonisolated static func downsampledJPEG(_ data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Main-actor entry point: creates the Library row immediately, then imports in the background.
@MainActor
enum ImportCoordinator {
    @discardableResult
    static func start(
        _ source: ImportSource,
        title: String,
        kind: DocumentKind,
        sourceURL: String? = nil,
        makesCardsFromTaps: Bool = true,
        pregeneratingAudioWith voice: (voiceID: String, modelID: String)? = nil,
        in context: ModelContext,
        configure: (Document) -> Void = { _ in }
    ) -> Document {
        let document = Document(title: title, kind: kind, sourceURL: sourceURL)
        document.makesCardsFromTaps = makesCardsFromTaps
        configure(document)
        context.insert(document)
        try? context.save()
        let container = context.container
        let documentID = document.persistentModelID
        Task.detached(priority: .userInitiated) {
            let importer = DocumentImporter(modelContainer: container)
            await importer.run(source, into: documentID)
            if let voice {
                await AudioPregenerator.run(chapters: importer.sentenceTexts(of: documentID), voiceID: voice.voiceID, modelID: voice.modelID)
            }
        }
        return document
    }

    /// Copies a picked file out of its security scope so the background importer can read it.
    static func copyToTemporaryLocation(_ url: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let destination = URL.temporaryDirectory.appending(path: UUID().uuidString).appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
