import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var seededLevel: Int?
    @Environment(WordStateStore.self) private var wordStates

    var body: some View {
        Form {
            Section {
                Picker("Pinyin", selection: $settings.pinyinMode) {
                    ForEach(PinyinMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Stepper("Estimated level: HSK \(settings.estimatedHSKLevel)", value: $settings.estimatedHSKLevel, in: 1...6)
                Button(seededLevel == settings.estimatedHSKLevel ? "HSK 1–\(settings.estimatedHSKLevel) words marked as Known" : "Mark HSK 1–\(settings.estimatedHSKLevel) words as Known") {
                    wordStates.markKnown(ChineseDictionary.shared.words(upToHSK: settings.estimatedHSKLevel))
                    seededLevel = settings.estimatedHSKLevel
                }
                .disabled(seededLevel == settings.estimatedHSKLevel)
            } header: {
                Text("Reading")
            } footer: {
                Text("Start from your level so only genuinely new words are underlined. Words you've already rated keep their level.")
            }

            Section {
                Toggle("Prepare while charging", isOn: $settings.prepareWhileCharging)
                Stepper("Chapters ahead: \(settings.chaptersToPrepare)", value: $settings.chaptersToPrepare, in: 1...10)
                    .disabled(!settings.prepareWhileCharging)
                LabeledContent("Status", value: preparationStatus)
                LabeledContent("Audio cache", value: ByteCountFormatter.string(fromByteCount: Int64(AudioCache.totalSize), countStyle: .file))
                Button("Clear audio cache", role: .destructive) { AudioCache.clear() }
            } header: {
                Text("Narration")
            } footer: {
                Text("While your device is plugged in, Pinguo renders narration and translations for the next chapters of the books you're reading, so they play from the cache later without using battery. Narration is rendered once per voice.")
            }

            OnDeviceSettingsSection()

            Section("About") {
                Text("Dictionary: CC-CEDICT (CC BY-SA 4.0). HSK levels from complete-hsk-vocabulary.")
                    .font(.meta13)
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .navigationTitle("Settings")
    }

    private var preparationStatus: String {
        let preparation = ChargingPreparation.shared
        if preparation.isPreparing { return "Preparing… \(Int((preparation.fraction * 100).rounded()))%" }
        if let last = preparation.lastFinished { return "Ready · \(last.formatted(.relative(presentation: .named)))" }
        return settings.prepareWhileCharging ? "Waiting for power" : "Off"
    }
}
