import Foundation
import Observation
import SwiftData

struct ReaderToken: Identifiable, Hashable {
    let id: Int
    let text: String
    let isLexical: Bool

    var isPunctuation: Bool {
        !isLexical && text.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.union(.symbols).contains($0) }
    }
}

struct ReaderSentence: Identifiable, Hashable {
    let id: Int
    let paragraphIndex: Int
    let text: String
    let englishText: String?
    let tokens: [ReaderToken]

    var lexicalWords: [String] { tokens.filter(\.isLexical).map(\.text) }
}

struct ReaderParagraph: Identifiable, Hashable {
    let id: Int
    let sentences: [ReaderSentence]
}

struct WordAnnotation: Hashable, Sendable {
    let pinyin: String
    let tones: [Int]
    let traditional: String
}

struct WordSelection: Equatable {
    let sentenceIndex: Int
    let tokenIndex: Int
    let word: String
}

@Observable
final class ReaderModel {
    let document: Document
    private(set) var chapters: [Chapter] = []
    private(set) var chapterIndex = 0
    private(set) var sentences: [ReaderSentence] = []
    private(set) var paragraphs: [ReaderParagraph] = []
    private(set) var annotations: [String: WordAnnotation] = [:]
    var selection: WordSelection?
    var sentenceActionsIndex: Int?
    var spokenSentenceIndex: Int?
    var restoreParagraphID: Int?

    init(document: Document) {
        self.document = document
        chapters = document.orderedChapters
        let start = min(max(0, document.lastChapterIndex), max(0, chapters.count - 1))
        loadChapter(start, restoringSentence: document.lastSentenceIndex)
        document.lastOpenedAt = .now
    }

    var chapter: Chapter? { chapters.indices.contains(chapterIndex) ? chapters[chapterIndex] : nil }
    var hasNextChapter: Bool { chapterIndex + 1 < chapters.count }
    var hasPreviousChapter: Bool { chapterIndex > 0 }

    func loadChapter(_ index: Int, restoringSentence sentenceIndex: Int = 0) {
        guard chapters.indices.contains(index) else { return }
        chapterIndex = index
        selection = nil
        let chapterSentences = chapters[index].orderedSentences
        sentences = chapterSentences.map { sentence in
            let characters = Array(sentence.text)
            let tokens = sentence.tokens.enumerated().map { offset, span in
                let end = min(span.start + span.length, characters.count)
                let text = span.start < end ? String(characters[span.start..<end]) : ""
                return ReaderToken(id: offset, text: text, isLexical: span.isLexical)
            }
            return ReaderSentence(
                id: sentence.index,
                paragraphIndex: sentence.paragraphIndex,
                text: sentence.text,
                englishText: sentence.englishText,
                tokens: tokens
            )
        }
        paragraphs = Dictionary(grouping: sentences, by: \.paragraphIndex)
            .map { ReaderParagraph(id: $0.key, sentences: $0.value.sorted { $0.id < $1.id }) }
            .sorted { $0.id < $1.id }
        restoreParagraphID = sentences.first { $0.id == sentenceIndex }?.paragraphIndex ?? paragraphs.first?.id
        saveProgress(sentenceIndex: sentenceIndex)
        loadAnnotations()
    }

    private func loadAnnotations() {
        let words = Set(sentences.flatMap(\.lexicalWords))
        Task {
            annotations = await Self.annotate(words)
        }
    }

    @concurrent
    private nonisolated static func annotate(_ words: Set<String>) async -> [String: WordAnnotation] {
        var result: [String: WordAnnotation] = [:]
        for word in words {
            if let entry = ChineseDictionary.shared.lookup(word) {
                result[word] = WordAnnotation(pinyin: entry.pinyin, tones: entry.tones, traditional: entry.traditional)
            }
        }
        return result
    }

    func sentence(_ index: Int) -> ReaderSentence? {
        sentences.first { $0.id == index }
    }

    func select(sentenceIndex: Int, token: ReaderToken) {
        guard token.isLexical else {
            selection = nil
            return
        }
        let newSelection = WordSelection(sentenceIndex: sentenceIndex, tokenIndex: token.id, word: token.text)
        selection = selection == newSelection ? nil : newSelection
    }

    func saveProgress(sentenceIndex: Int) {
        guard let chapter else { return }
        document.lastChapterIndex = chapterIndex
        document.lastSentenceIndex = sentenceIndex
        document.sentencesRead = max(0, min(document.totalSentences, chapter.firstSentenceOffset + sentenceIndex + 1))
    }

    /// Reaching the end of a chapter counts it as read without moving the bookmark.
    func markChapterFinished() {
        guard let chapter else { return }
        document.sentencesRead = max(document.sentencesRead, min(document.totalSentences, chapter.firstSentenceOffset + sentences.count))
    }

    func saveProgress(paragraphID: Int) {
        guard let first = paragraphs.first(where: { $0.id == paragraphID })?.sentences.first else { return }
        saveProgress(sentenceIndex: first.id)
    }

    func newWords(using store: WordStateStore) -> [String] {
        var seen = Set<String>()
        return sentences.flatMap(\.lexicalWords).filter { word in
            store.familiarity(of: word) == .new && seen.insert(word).inserted
        }
    }

    func context(around sentenceIndex: Int) -> String {
        sentences.filter { abs($0.id - sentenceIndex) <= 1 && $0.id != sentenceIndex }.map(\.text).joined()
    }
}
