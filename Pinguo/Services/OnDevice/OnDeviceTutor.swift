import Foundation
import FoundationModels

/// The speaking partner on Apple's on-device model, for conversations without a connection.
/// Weaker than Claude, so it gets a shorter brief; pinyin comes from the bundled dictionary rather than the model.
nonisolated struct OnDeviceTutor: Sendable {
    @Generable
    struct Turn {
        @Generable
        struct Correction {
            @Guide(description: "True only if the learner's last Chinese sentence had a real mistake.")
            var needed: Bool
            @Guide(description: "The learner's last sentence rewritten naturally in Simplified Chinese. Empty when not needed.")
            var natural: String
            @Guide(description: "The part of natural that differs from what the learner said. Empty when not needed.")
            var changed: String
            @Guide(description: "One short English sentence explaining the change. Empty when not needed.")
            var reason: String
        }

        @Guide(description: "Your next line in Simplified Chinese only: one to three short, simple sentences, usually ending with a question.")
        var reply: String
        @Guide(description: "Natural English translation of reply.")
        var translation: String
        var correction: Correction
        @Guide(description: "Two different complete sentences (4–15 characters each) the learner could say back to your reply, from the learner's side of the role-play, in Simplified Chinese. Example: 我要一杯热拿铁。", .count(2))
        var suggestions: [String]
    }

    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings to practise offline."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading its model."
        case .unavailable(.deviceNotEligible): "This device doesn't support Apple Intelligence."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    func respond(scenario: Scenario, hskLevel: Int, deckWords: [String], history: [ConversationLine]) async throws -> TutorTurn {
        guard Self.isAvailable else { throw OnDeviceTutorError.unavailable(Self.unavailableReason ?? "") }
        let instructions = """
            You are a friendly Mandarin speaking partner for an English-speaking learner at about HSK \(hskLevel).
            Role-play: \(scenario.brief)
            Always reply in simple Simplified Chinese (HSK 1–\(min(6, hskLevel + 1)) words), stay in your role and keep the conversation going.
            If the learner wrote in English they are stuck: start with 你可以说："…" showing how to say it in Chinese, then continue.
            Only correct real mistakes in the learner's last Chinese message.
            """
        let words = deckWords.prefix(15).joined(separator: "、")
        let transcript = history.suffix(8).map { line in
            line.isTutor ? "You: \(line.text)" : "Learner\(line.wasEnglish ? " (in English)" : ""): \(line.text)"
        }
        let prompt = transcript.isEmpty
            ? "Open the conversation in your role."
            : "Conversation so far:\n\(transcript.joined(separator: "\n"))\n\nWrite your next turn."
        let session = LanguageModelSession(instructions: words.isEmpty ? instructions : instructions + "\nWhere natural, use words the learner is studying: \(words)")
        let turn = try await session.respond(to: prompt, generating: Turn.self).content

        return TutorTurn(
            reply: turn.reply,
            pinyin: Self.pinyin(for: turn.reply),
            translation: turn.translation,
            correction: TutorTurn.Correction(
                needed: turn.correction.needed,
                natural: turn.correction.natural,
                changed: turn.correction.changed,
                reason: turn.correction.reason
            ),
            suggestions: Self.usableSuggestions(turn.suggestions)
        )
    }

    /// The small model sometimes returns blanks or word lists instead of sentences; keep only real lines.
    static func usableSuggestions(_ suggestions: [String]) -> [String] {
        suggestions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 24 && !$0.contains("、") }
    }

    static func pinyin(for text: String) -> String {
        Segmenter().tokens(in: text).compactMap { token -> String? in
            let word = token.text(in: text)
            guard token.isLexical else { return nil }
            return ChineseDictionary.shared.lookup(word)?.pinyin ?? word
        }
        .joined(separator: " ")
    }
}

nonisolated enum OnDeviceTutorError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "You're offline. \(reason)"
        }
    }
}
