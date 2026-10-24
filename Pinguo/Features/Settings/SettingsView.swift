import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @State private var keyDrafts: [APIService: String] = [:]
    @State private var savedServices: Set<APIService> = []

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

            Section("Reading") {
                Picker("Pinyin", selection: $settings.pinyinMode) {
                    ForEach(PinyinMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Stepper("Estimated level: HSK \(settings.estimatedHSKLevel)", value: $settings.estimatedHSKLevel, in: 1...6)
            }

            Section("About") {
                Text("Dictionary: CC-CEDICT (CC BY-SA 4.0). HSK levels from complete-hsk-vocabulary.")
                    .font(.meta13)
                    .foregroundStyle(Color.inkSecondary)
            }
        }
        .navigationTitle("Settings")
    }
}
