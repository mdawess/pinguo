import Foundation
import Translation

/// Apple's on-device translation between Mandarin and English, once the language packs are downloaded.
actor AppleTranslator {
    static let chineseToEnglish = AppleTranslator(source: .chinese, target: .english)
    static let englishToChinese = AppleTranslator(source: .english, target: .chinese)

    nonisolated let source: Locale.Language
    nonisolated let target: Locale.Language
    private var session: TranslationSession?

    init(source: Locale.Language, target: Locale.Language) {
        self.source = source
        self.target = target
    }

    nonisolated static func status() async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: .chinese, to: .english)
    }

    func translate(_ text: String) async throws -> String {
        guard await LanguageAvailability().status(from: source, to: target) == .installed else { throw AppleTranslatorError.notDownloaded }
        let session = session ?? TranslationSession(installedSource: source, target: target)
        self.session = session
        return try await session.translate(text).targetText
    }

    func translate(_ texts: [String]) async throws -> [String] {
        guard await LanguageAvailability().status(from: source, to: target) == .installed else { throw AppleTranslatorError.notDownloaded }
        let session = session ?? TranslationSession(installedSource: source, target: target)
        self.session = session
        let requests = texts.enumerated().map { TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset)) }
        var results = texts
        for response in try await session.translations(from: requests) {
            if let index = response.clientIdentifier.flatMap(Int.init) { results[index] = response.targetText }
        }
        return results
    }
}

extension Locale.Language {
    nonisolated static let chinese = Locale.Language(identifier: "zh-Hans")
    nonisolated static let english = Locale.Language(identifier: "en")
}

nonisolated enum AppleTranslatorError: LocalizedError {
    case notDownloaded

    var errorDescription: String? {
        "Download Chinese–English translation in Settings › On-device to translate."
    }
}
