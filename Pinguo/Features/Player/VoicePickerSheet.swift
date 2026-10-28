import AVFoundation
import SwiftUI

struct VoicePickerSheet: View {
    @Bindable var settings: AppSettings
    let document: Document?
    let player: NarrationPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var selectedID: String?
    @State private var onlyThisDocument = false

    private static let sample = "大家好，今天我们一起读一个关于周末爬山的小故事。"

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("Voice").font(.largeTitle30)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 17, weight: .light)).frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    ForEach(["zh-CN", "zh-TW"], id: \.self) { language in
                        let group = voices.filter { $0.language == language }
                        if !group.isEmpty {
                            Text(language == "zh-CN" ? "Mainland Mandarin" : "Taiwan Mandarin")
                                .font(.meta13)
                                .foregroundStyle(Color.inkSecondary)
                                .padding(.top, 4)
                            voiceRows(group)
                        }
                    }
                    if voices.isEmpty {
                        Text("No Chinese voices are installed.").font(.body15)
                    }
                    Text("Voices run entirely on this device. For more natural narration, download a Premium or Enhanced Chinese voice in Settings › Accessibility › Spoken Content › Voices › Chinese, then come back here.")
                        .font(.meta13)
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            footer
        }
        .background(Color.background)
        .onAppear {
            voices = ChineseVoices.installed
            selectedID = settings.voiceID(for: document)
            onlyThisDocument = document?.voiceOverrideID != nil
        }
    }

    private func voiceRows(_ voices: [AVSpeechSynthesisVoice]) -> some View {
        VStack(spacing: 4) {
            ForEach(voices, id: \.identifier) { voice in
                let isSelected = voice.identifier == selectedID
                HStack(spacing: 14) {
                    VoiceAvatar(name: voice.name)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(voice.name).font(.geist(16, .medium)).foregroundStyle(Color.ink)
                        Text("\(ChineseVoices.qualityLabel(of: voice)) · \(ChineseVoices.accentLabel(of: voice))")
                            .font(.meta13)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    Button {
                        Pronunciation.shared.speak(Self.sample, voiceID: voice.identifier)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14))
                            .frame(width: 40, height: 40)
                            .overlay(Circle().strokeBorder(Color.hairline))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview \(voice.name)")
                    Image(systemName: "checkmark")
                        .font(.system(size: 16))
                        .frame(width: 24)
                        .opacity(isSelected ? 1 : 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isSelected ? Color.surface : .clear))
                .contentShape(Rectangle())
                .onTapGesture { selectedID = voice.identifier }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Text("Speed").font(.body15)
                Slider(value: Binding(get: { player.speed }, set: { player.speed = ($0 * 10).rounded() / 10 }), in: 0.5...1.5)
                    .tint(Color.ink)
                Text(player.speed.formatted(.number.precision(.fractionLength(1))) + "×")
                    .font(.geist(15, .medium).monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
            }
            if document != nil {
                Toggle("Only for this book", isOn: $onlyThisDocument).font(.body15).tint(Color.ink)
            }
            Button {
                apply()
                dismiss()
            } label: {
                Text("Use \(selectedName)").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(height: 52))
            .disabled(selectedID == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.background)
    }

    private var selectedName: String {
        voices.first { $0.identifier == selectedID }?.name ?? "voice"
    }

    private func apply() {
        guard let selectedID else { return }
        if let document, onlyThisDocument {
            document.voiceOverrideID = selectedID
        } else {
            document?.voiceOverrideID = nil
            settings.voiceID = selectedID
        }
    }
}
