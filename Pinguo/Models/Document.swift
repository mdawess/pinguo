import Foundation
import SwiftData

enum DocumentKind: String, Codable, CaseIterable {
    case epub, pdf, article, text, translatedAudio

    var label: String {
        switch self {
        case .epub: "Book"
        case .pdf: "PDF"
        case .article: "Article"
        case .text: "Text"
        case .translatedAudio: "Translated from English"
        }
    }

    var isShelfItem: Bool { self == .epub || self == .pdf }
}

enum ImportStatus: String, Codable {
    case importing, ready, failed
}

@Model
final class Document {
    var id: UUID = UUID()
    var title: String = ""
    var author: String?
    var kindRaw: String = DocumentKind.text.rawValue
    var sourceURL: String?
    @Attribute(.externalStorage) var coverImage: Data?
    var importedAt: Date = Date.now
    var lastOpenedAt: Date?
    var lastChapterIndex: Int = 0
    var lastSentenceIndex: Int = 0
    var sentencesRead: Int = 0
    var totalSentences: Int = 0
    var totalCharacters: Int = 0
    var uniqueWordsData: Data?
    var voiceOverrideID: String?
    var makesCardsFromTaps: Bool = true
    var statusRaw: String = ImportStatus.importing.rawValue
    var importProgress: Double = 0
    var importError: String?
    var sourceAudioFileName: String?
    var durationSeconds: Double?
    @Relationship(deleteRule: .cascade, inverse: \Chapter.document) var chapters: [Chapter]? = []

    init(title: String, author: String? = nil, kind: DocumentKind, sourceURL: String? = nil) {
        self.title = title
        self.author = author
        self.kindRaw = kind.rawValue
        self.sourceURL = sourceURL
    }

    var kind: DocumentKind {
        get { DocumentKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var status: ImportStatus {
        get { ImportStatus(rawValue: statusRaw) ?? .ready }
        set { statusRaw = newValue.rawValue }
    }

    var orderedChapters: [Chapter] {
        (chapters ?? []).sorted { $0.index < $1.index }
    }

    var uniqueWords: [String] {
        get { uniqueWordsData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
        set { uniqueWordsData = try? JSONEncoder().encode(newValue) }
    }

    var readingProgress: Double {
        guard totalSentences > 0 else { return 0 }
        return min(1, Double(sentencesRead) / Double(totalSentences))
    }

    var estimatedMinutesLeft: Int {
        let charactersPerMinute = 260.0
        let remaining = Double(totalCharacters) * (1 - readingProgress)
        return max(1, Int((remaining / charactersPerMinute).rounded()))
    }
}

@Model
final class Chapter {
    var id: UUID = UUID()
    var index: Int = 0
    var title: String = ""
    var firstSentenceOffset: Int = 0
    var document: Document?
    @Relationship(deleteRule: .cascade, inverse: \Sentence.chapter) var sentences: [Sentence]? = []

    init(index: Int, title: String, firstSentenceOffset: Int) {
        self.index = index
        self.title = title
        self.firstSentenceOffset = firstSentenceOffset
    }

    var orderedSentences: [Sentence] {
        (sentences ?? []).sorted { $0.index < $1.index }
    }
}

@Model
final class Sentence {
    var id: UUID = UUID()
    var index: Int = 0
    var paragraphIndex: Int = 0
    var text: String = ""
    var englishText: String?
    var tokensData: Data?
    var sourceAudioStart: Double?
    var sourceAudioEnd: Double?
    var chapter: Chapter?

    init(index: Int, paragraphIndex: Int, text: String, tokens: [TokenSpan]) {
        self.index = index
        self.paragraphIndex = paragraphIndex
        self.text = text
        self.tokensData = TokenSpan.encode(tokens)
    }

    var tokens: [TokenSpan] {
        get { tokensData.map(TokenSpan.decode) ?? [] }
        set { tokensData = TokenSpan.encode(newValue) }
    }
}
