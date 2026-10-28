import AVFoundation
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
    var playbackSpeed: Double = 1.0
    var makeCardsFromTapsByDefault: Bool = true
    var estimatedHSKLevel: Int = 3
    var prepareWhileCharging: Bool = true
    var chaptersToPrepare: Int = 3

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

    /// The chosen on-device voice, or the best installed Mandarin voice if it isn't on this device.
    var resolvedVoiceID: String? { ChineseVoices.voice(withID: voiceID)?.identifier }
    var resolvedVoiceName: String { ChineseVoices.voice(withID: voiceID)?.name ?? "Voice" }

    func voiceID(for document: Document?) -> String? {
        ChineseVoices.voice(withID: document?.voiceOverrideID ?? voiceID)?.identifier
    }

    static func current(in context: ModelContext) -> AppSettings {
        let all = (try? context.fetch(FetchDescriptor<AppSettings>())) ?? []
        if let existing = all.first { return existing }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
