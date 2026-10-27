import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID = UUID()
    var scenarioID: String = ""
    var title: String = ""
    var hskLevel: Int = 3
    var startedAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation) var messages: [Message]? = []

    init(scenarioID: String, title: String, hskLevel: Int) {
        self.scenarioID = scenarioID
        self.title = title
        self.hskLevel = hskLevel
    }

    var orderedMessages: [Message] {
        (messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }
}

enum MessageRole: String, Codable {
    case tutor, learner
}

@Model
final class Message {
    var id: UUID = UUID()
    var roleRaw: String = MessageRole.tutor.rawValue
    var text: String = ""
    var pinyin: String?
    var englishText: String?
    var wasEnglish: Bool = false
    var correctionNatural: String?
    var correctionChanged: String?
    var correctionReason: String?
    var suggestionsData: Data?
    var createdAt: Date = Date.now
    var conversation: Conversation?

    init(role: MessageRole, text: String) {
        self.roleRaw = role.rawValue
        self.text = text
    }

    var role: MessageRole { MessageRole(rawValue: roleRaw) ?? .tutor }

    var suggestions: [String] {
        get { suggestionsData.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [] }
        set { suggestionsData = try? JSONEncoder().encode(newValue) }
    }

    var hasCorrection: Bool { correctionNatural?.isEmpty == false }
}
