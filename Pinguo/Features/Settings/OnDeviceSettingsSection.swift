import AVFoundation
import SwiftUI
import Translation

/// Settings › On-device: the Apple voice, translation and Apple Intelligence pieces Pinguo runs on.
struct OnDeviceSettingsSection: View {
    @State private var translationStatus: LanguageAvailability.Status?
    @State private var translationRequest: TranslationSession.Configuration?

    var body: some View {
        Section {
            LabeledContent("Voice", value: ChineseVoices.best.map { "\($0.name) (\(ChineseVoices.qualityLabel(of: $0)))" } ?? "None installed")
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
            LabeledContent("Speaking tutor", value: TutorService.unavailableReason == nil ? "Apple Intelligence" : "Unavailable")
        } header: {
            Text("On-device")
        } footer: {
            Text(footer)
        }
        .task { translationStatus = await AppleTranslator.status() }
        .translationTask(translationRequest) { session in
            try? await session.prepareTranslation()
            translationStatus = await AppleTranslator.status()
        }
    }

    private func requestTranslationDownload() {
        if translationRequest == nil {
            translationRequest = TranslationSession.Configuration(source: .chinese, target: .english)
        } else {
            translationRequest?.invalidate()
        }
    }

    private var footer: String {
        var lines = ["Everything runs on this device and works offline: narration uses Apple voices, translation uses Apple Translation and the speaking tutor uses Apple Intelligence."]
        if !ChineseVoices.hasHighQualityVoice {
            lines.append("For more natural narration, download a Premium or Enhanced Chinese (China mainland) voice in Settings › Accessibility › Spoken Content › Voices.")
        }
        if let reason = TutorService.unavailableReason {
            lines.append(reason)
        }
        return lines.joined(separator: "\n\n")
    }
}
