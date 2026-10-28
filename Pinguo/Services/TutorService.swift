import Foundation

nonisolated struct TutorTurn: Decodable, Sendable {
    struct Correction: Decodable, Sendable {
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

/// The speaking partner: replies in the learner's level, corrects the learner's last sentence and offers replies.
nonisolated struct TutorService: Sendable {
    let client = ClaudeClient()

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "reply": ["type": "string", "description": "Your next line, in Simplified Chinese only."],
            "pinyin": ["type": "string", "description": "Pinyin with tone marks for reply, words separated by spaces."],
            "translation": ["type": "string", "description": "Natural English translation of reply."],
            "correction": [
                "type": "object",
                "properties": [
                    "needed": ["type": "boolean"],
                    "natural": ["type": "string", "description": "The learner's last sentence rewritten naturally. Empty when not needed."],
                    "changed": ["type": "string", "description": "The exact substring of natural that differs from what the learner said."],
                    "reason": ["type": "string", "description": "One short English sentence explaining the change."],
                ],
                "required": ["needed", "natural", "changed", "reason"],
                "additionalProperties": false,
            ],
            "suggestions": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Two short replies the learner could say next, in Chinese at their level.",
            ],
        ],
        "required": ["reply", "pinyin", "translation", "correction", "suggestions"],
        "additionalProperties": false,
    ]

    /// Claude when it can be reached, otherwise Apple's on-device model.
    func respond(scenario: Scenario, hskLevel: Int, deckWords: [String], history: [ConversationLine]) async throws -> (turn: TutorTurn, isOnDevice: Bool) {
        let onDevice = { () async throws -> (turn: TutorTurn, isOnDevice: Bool) in
            (try await OnDeviceTutor().respond(scenario: scenario, hskLevel: hskLevel, deckWords: deckWords, history: history), true)
        }
        guard CloudReachability.shouldTryCloud, APIKeys.hasKey(for: .anthropic) else { return try await onDevice() }
        do {
            return (try await cloudRespond(scenario: scenario, hskLevel: hskLevel, deckWords: deckWords, history: history), false)
        } catch where CloudReachability.isOffline(error) && OnDeviceTutor.isAvailable {
            return try await onDevice()
        }
    }

    private func cloudRespond(scenario: Scenario, hskLevel: Int, deckWords: [String], history: [ConversationLine]) async throws -> TutorTurn {
        let system = """
            You are a Mandarin speaking partner for an English-speaking learner at about HSK \(hskLevel).
            Role-play: \(scenario.brief)

            How to talk:
            - Reply in Simplified Chinese only, one to three short sentences, mostly with HSK 1–\(min(6, hskLevel + 1)) vocabulary.
            - Stay in the role and keep the conversation going, usually by ending with a question.
            - Where it fits naturally, reuse words the learner is studying: \(deckWords.isEmpty ? "(none yet)" : deckWords.joined(separator: "、")).
            - If the learner's last message was in English (marked [English]), they are stuck: reply in Chinese starting with how to say it (e.g. 你可以说：“…”), then continue the role-play.

            Corrections: look only at the learner's last message. If it was Chinese and something is wrong or unnatural, set needed to true and give the natural sentence, the changed part and a one-line reason. If it was fine, or there is no learner message yet, set needed to false and leave the other fields empty. Don't correct punctuation or speech-recognition slips that don't change meaning.

            Suggestions: two short, different things the learner could say next, at their level.
            """
        var messages: [ClaudeClient.Message] = history.suffix(10).map { line in
            line.isTutor ? .assistant(line.text) : .user(line.wasEnglish ? "[English] \(line.text)" : line.text)
        }
        if messages.first?.role != "user" {
            messages.insert(.user("（开始对话。Please open the conversation in your role.）"), at: 0)
        }
        return try await client.json(TutorTurn.self, system: system, messages: messages, schema: Self.schema, effort: .low)
    }
}
