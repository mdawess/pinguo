import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var keyDrafts: [APIService: String] = [:]
    @State private var savedServices: Set<APIService> = []
    @State private var seededLevel: Int?
    @Environment(WordStateStore.self) private var wordStates

    var body: some View {
        Form {
            Section {
                ForEach(APIService.allCases) { service in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(service.displayName).font(.body15)
                            Spacer()
                            if APIKeys.hasKey(for: service) || savedServices.contains(service) {
                                Label("Saved", systemImage: "checkmark").font(.meta12).foregroundStyle(Color.inkSecondary)
                            }
                        }
                        HStack {
                            SecureField("Paste key", text: Binding(
                                get: { keyDrafts[service, default: ""] },
                                set: { keyDrafts[service] = $0 }
                            ))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            Button("Save") {
                                APIKeys.save(keyDrafts[service, default: ""], for: service)
                                keyDrafts[service] = ""
                                savedServices.insert(service)
                            }
                            .disabled(keyDrafts[service, default: ""].isEmpty)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("API keys")
            } footer: {
                Text("Keys are stored in the Keychain on this device and are only sent to their own service.")
            }

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
                Picker("Voice model", selection: $settings.voiceModelID) {
                    Text("Multilingual v2 (most natural)").tag("eleven_multilingual_v2")
                    Text("Flash v2.5 (faster, half the credits)").tag("eleven_flash_v2_5")
                    Text("v3 (most expressive)").tag("eleven_v3")
                }
                LabeledContent("Audio cache", value: ByteCountFormatter.string(fromByteCount: Int64(AudioCache.totalSize), countStyle: .file))
                Button("Clear audio cache", role: .destructive) { AudioCache.clear() }
            } header: {
                Text("Voice")
            } footer: {
                Text("Narration is cached by text, voice and model, so re-listening never costs credits.")
            }

            OfflineSettingsSection()

            Section("About") {
                Text("Dictionary: CC-CEDICT (CC BY-SA 4.0). HSK levels from complete-hsk-vocabulary.")
                    .font(.meta13)
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .navigationTitle("Settings")
    }
}
