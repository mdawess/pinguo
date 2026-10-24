import Foundation
import SwiftData

enum PinyinMode: String, Codable, CaseIterable {
    case always, newWordsOnly, off

    var label: String {
        switch self {
        case .always: "Always"
        case .newWordsOnly: "New words"
        case .off: "Off"
        }
    }
}

enum ScriptPreference: String, Codable, CaseIterable {
    case simplified, traditional
}

enum ReaderTheme: String, Codable, CaseIterable {
    case light, paper, dark
}

@Model
final class AppSettings {
    var pinyinModeRaw: String = PinyinMode.newWordsOnly.rawValue
    var toneColours: Bool = false
    var scriptRaw: String = ScriptPreference.simplified.rawValue
    var textSize: Double = 21
    var themeRaw: String = ReaderTheme.light.rawValue
    var dailyNewCards: Int = 20
    var dailyReviews: Int = 200
    var voiceID: String?
    var voiceName: String?
    var voiceModelID: String = "eleven_multilingual_v2"
    var playbackSpeed: Double = 1.0
    var makeCardsFromTapsByDefault: Bool = true
    var pregenerateAudioByDefault: Bool = false
    var estimatedHSKLevel: Int = 3

    init() {}

    var pinyinMode: PinyinMode {
        get { PinyinMode(rawValue: pinyinModeRaw) ?? .newWordsOnly }
        set { pinyinModeRaw = newValue.rawValue }
    }

    var script: ScriptPreference {
        get { ScriptPreference(rawValue: scriptRaw) ?? .simplified }
        set { scriptRaw = newValue.rawValue }
    }

    var theme: ReaderTheme {
        get { ReaderTheme(rawValue: themeRaw) ?? .light }
        set { themeRaw = newValue.rawValue }
    }

    var resolvedVoiceID: String { voiceID ?? ElevenLabsClient.defaultVoiceID }
    var resolvedVoiceName: String { voiceName ?? ElevenLabsClient.defaultVoiceName }

    func voiceID(for document: Document?) -> String {
        document?.voiceOverrideID ?? resolvedVoiceID
    }

    static func current(in context: ModelContext) -> AppSettings {
        let all = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let existing = all.first { return existing }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
