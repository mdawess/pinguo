import Foundation
import FoundationModels

nonisolated struct TutorTurn: Sendable {
    struct Correction: Sendable {
        let needed: Bool
        let natural: String
        let changed: String
        let reason: String
    }

    let reply: String
    let pinyin: String
    let translation: String
    let correction: Correction
    let suggestions: [String]
}

nonisolated struct ConversationLine: Sendable {
    let isTutor: Bool
    let text: String
    let wasEnglish: Bool
}

/// The speaking partner on Apple's on-device model: replies at the learner's level, corrects their last
/// sentence and offers replies. Pinyin comes from the bundled dictionary rather than the model.
nonisolated struct TutorService: Sendable {
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

    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings to practise speaking."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading its model. Try again shortly."
        case .unavailable(.deviceNotEligible): "Speaking practice needs a device that supports Apple Intelligence."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    func respond(scenario: Scenario, hskLevel: Int, deckWords: [String], history: [ConversationLine]) async throws -> TutorTurn {
        if let reason = Self.unavailableReason { throw TutorError.unavailable(reason) }
        var instructions = """
            You are a friendly Mandarin speaking partner for an English-speaking learner at about HSK \(hskLevel).
            Role-play: \(scenario.brief)
            Always reply in simple Simplified Chinese (HSK 1–\(min(6, hskLevel + 1)) words), respond directly to what the learner just said, stay in your role and keep the conversation going.
            If the learner wrote in English they are stuck: start with 你可以说："…" showing how to say it in Chinese, then continue.
            Only correct real mistakes in the learner's last Chinese message.
            """
        if !deckWords.isEmpty {
            instructions += "\nWhere natural, use words the learner is studying: \(deckWords.prefix(15).joined(separator: "、"))"
        }
        let transcript = history.suffix(8).map { line in
            line.isTutor ? "You: \(line.text)" : "Learner\(line.wasEnglish ? " (in English)" : ""): \(line.text)"
        }
        let prompt = transcript.isEmpty
            ? "Open the conversation in your role."
            : "Conversation so far:\n\(transcript.joined(separator: "\n"))\n\nWrite your next turn."
        let turn = try await LanguageModelSession(instructions: instructions).respond(to: prompt, generating: Turn.self).content
        let learnerLine = history.last.flatMap { !$0.isTutor && !$0.wasEnglish ? $0.text : nil }
        let correctionIsPlausible = learnerLine.map { Self.isPlausibleCorrection(turn.correction.natural, of: $0) } ?? false

        return TutorTurn(
            reply: turn.reply,
            pinyin: Self.pinyin(for: turn.reply),
            translation: turn.translation,
            correction: TutorTurn.Correction(
                needed: turn.correction.needed && correctionIsPlausible,
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

    /// The small model sometimes "corrects" a fine sentence into an unrelated one; a real correction
    /// keeps most of the learner's characters.
    static func isPlausibleCorrection(_ natural: String, of learner: String) -> Bool {
        let learnerHan = learner.filter { $0.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) } }
        guard !learnerHan.isEmpty, natural != learner else { return false }
        let kept = learnerHan.filter { natural.contains($0) }.count
        return Double(kept) / Double(learnerHan.count) >= 0.6
    }

    static func pinyin(for text: String) -> String {
        Segmenter().tokens(in: text).compactMap { token -> String? in
            guard token.isLexical else { return nil }
            let word = token.text(in: text)
            return ChineseDictionary.shared.lookup(word)?.pinyin ?? word
        }
        .joined(separator: " ")
    }
}

nonisolated enum TutorError: LocalizedError {
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): reason
        }
    }
}
