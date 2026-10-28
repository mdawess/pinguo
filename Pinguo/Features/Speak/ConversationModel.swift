import Foundation
import Observation
import SwiftData

@Observable
final class ConversationModel {
    let conversation: Conversation
    let scenario: Scenario
    private let context: ModelContext
    private let tutor = TutorService()
    private(set) var isThinking = false
    private(set) var errorMessage: String?
    private(set) var messages: [Message] = []

    init(conversation: Conversation, scenario: Scenario, context: ModelContext) {
        self.conversation = conversation
        self.scenario = scenario
        self.context = context
        messages = conversation.orderedMessages
    }

    var suggestions: [String] {
        guard let last = messages.last, last.role == .tutor else { return [] }
        return last.suggestions
    }

    func openIfNeeded(deckWords: [String], onTutorMessage: (Message) -> Void) async {
        guard messages.isEmpty else { return }
        await requestTutorTurn(deckWords: deckWords, onTutorMessage: onTutorMessage)
    }

    func send(_ text: String, inEnglish: Bool, deckWords: [String], onTutorMessage: (Message) -> Void) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        let message = Message(role: .learner, text: trimmed)
        message.wasEnglish = inEnglish
        append(message)
        await requestTutorTurn(deckWords: deckWords, onTutorMessage: onTutorMessage)
    }

    func retry(deckWords: [String], onTutorMessage: (Message) -> Void) async {
        await requestTutorTurn(deckWords: deckWords, onTutorMessage: onTutorMessage)
    }

    private func requestTutorTurn(deckWords: [String], onTutorMessage: (Message) -> Void) async {
        isThinking = true
        errorMessage = nil
        defer { isThinking = false }
        let history = messages.map { ConversationLine(isTutor: $0.role == .tutor, text: $0.text, wasEnglish: $0.wasEnglish) }
        do {
            let turn = try await tutor.respond(scenario: scenario, hskLevel: conversation.hskLevel, deckWords: deckWords, history: history)
            if turn.correction.needed, let learner = messages.last, learner.role == .learner, !learner.wasEnglish,
               !turn.correction.natural.isEmpty, turn.correction.natural != learner.text {
                learner.correctionNatural = turn.correction.natural
                learner.correctionChanged = turn.correction.changed
                learner.correctionReason = turn.correction.reason
            }
            let reply = Message(role: .tutor, text: turn.reply)
            reply.pinyin = turn.pinyin
            reply.englishText = turn.translation
            reply.suggestions = Array(turn.suggestions.prefix(2))
            append(reply)
            onTutorMessage(reply)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func append(_ message: Message) {
        context.insert(message)
        message.conversation = conversation
        messages.append(message)
        try? context.save()
    }

    /// Words the tutor used that are still New for the learner, for the end-of-session summary.
    func newWordsUsed(wordStates: WordStateStore) -> [String] {
        let segmenter = Segmenter()
        var seen = Set<String>()
        return messages.filter { $0.role == .tutor }.flatMap { message in
            segmenter.tokens(in: message.text).filter(\.isLexical).map { $0.text(in: message.text) }
        }
        .filter { word in
            wordStates.familiarity(of: word) == .new && ChineseDictionary.shared.lookup(word) != nil && seen.insert(word).inserted
        }
    }

    var corrections: [Message] {
        messages.filter(\.hasCorrection)
    }
}
