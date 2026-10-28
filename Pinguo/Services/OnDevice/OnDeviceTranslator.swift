import Foundation
import Translation

/// Apple's on-device Mandarin → English translation. Works offline once the language pack is downloaded.
actor OnDeviceTranslator {
    static let shared = OnDeviceTranslator()
    nonisolated static let source = Locale.Language(identifier: "zh-Hans")
    nonisolated static let target = Locale.Language(identifier: "en")

    private var session: TranslationSession?

    nonisolated static func status() async -> LanguageAvailability.Status {
        await LanguageAvailability().status(from: source, to: target)
    }

    func translate(_ text: String) async throws -> String {
        guard await Self.status() == .installed else { throw OnDeviceTranslatorError.notDownloaded }
        let session = session ?? TranslationSession(installedSource: Self.source, target: Self.target)
        self.session = session
        return try await session.translate(text).targetText
    }
}

nonisolated enum OnDeviceTranslatorError: LocalizedError {
    case notDownloaded

    var errorDescription: String? {
        "You're offline and the Chinese–English offline translation isn't downloaded yet. Download it in Settings › Offline."
    }
}
