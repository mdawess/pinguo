import Foundation
import SwiftData

enum Familiarity: Int, CaseIterable, Codable {
    case new = 0, seen, familiar, almostKnown, known

    var label: String {
        switch self {
        case .new: "New"
        case .seen: "Seen"
        case .familiar: "Familiar"
        case .almostKnown: "Almost known"
        case .known: "Known"
        }
    }

    var isLearning: Bool { self == .seen || self == .familiar || self == .almostKnown }
}

@Model
final class WordState {
    var word: String = ""
    var familiarityRaw: Int = Familiarity.new.rawValue
    var firstSeenAt: Date = Date.now
    var updatedAt: Date = Date.now
    var lookupCount: Int = 0

    init(word: String, familiarity: Familiarity = .new) {
        self.word = word
        self.familiarityRaw = familiarity.rawValue
    }

    var familiarity: Familiarity {
        get { Familiarity(rawValue: familiarityRaw) ?? .new }
        set {
            familiarityRaw = newValue.rawValue
            updatedAt = .now
        }
    }
}
