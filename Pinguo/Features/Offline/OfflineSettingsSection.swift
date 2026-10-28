import SwiftUI
import Translation

/// Settings › Offline: what works without a connection and the on-device pieces to download before a flight.
struct OfflineSettingsSection: View {
    @State private var translationStatus: LanguageAvailability.Status?
    @State private var translationRequest: TranslationSession.Configuration?

    var body: some View {
        let connectivity = Connectivity.shared
        Section {
            Toggle("Always use on-device", isOn: Binding(get: { connectivity.preferOnDevice }, set: { connectivity.setPreferOnDevice($0) }))
            LabeledContent("Connection", value: connectivity.isOnline ? "Online" : "Offline")

            LabeledContent("Voice", value: OnDeviceSpeech.bestVoiceDescription)
            Button("Preview on-device voice") { SpeechFallback.shared.speak("你好，欢迎来到拼果。今天我们一起读书吧。") }

            HStack {
                Text("Translation")
                Spacer()
                switch translationStatus {
                case .installed: Text("Downloaded").foregroundStyle(Color.inkSecondary)
                case .supported: Button("Download") { requestTranslationDownload() }
                case .unsupported: Text("Unavailable").foregroundStyle(Color.inkSecondary)
                case nil: ProgressView()
                @unknown default: EmptyView()
                }
            }

            LabeledContent("Tutor", value: OnDeviceTutor.unavailableReason == nil ? "Apple Intelligence" : "Unavailable")
        } header: {
            Text("Offline")
        } footer: {
            Text(footer)
        }
        .task { translationStatus = await OnDeviceTranslator.status() }
        .translationTask(translationRequest) { session in
            try? await session.prepareTranslation()
            translationStatus = await OnDeviceTranslator.status()
        }
    }

    private func requestTranslationDownload() {
        if translationRequest == nil {
            translationRequest = TranslationSession.Configuration(source: OnDeviceTranslator.source, target: OnDeviceTranslator.target)
        } else {
            translationRequest?.invalidate()
        }
    }

    private var footer: String {
        var lines = ["Without a connection Pinguo switches to Apple's on-device voice, translation and tutor. For the best quality on a flight, use “Download for offline” on a book first to save its ElevenLabs narration and Claude translations."]
        if !OnDeviceSpeech.hasHighQualityVoice {
            lines.append("For a more natural offline voice, download a Premium or Enhanced Chinese (China mainland) voice in Settings › Accessibility › Spoken Content › Voices.")
        }
        if let reason = OnDeviceTutor.unavailableReason {
            lines.append(reason)
        }
        return lines.joined(separator: "\n\n")
    }
}
