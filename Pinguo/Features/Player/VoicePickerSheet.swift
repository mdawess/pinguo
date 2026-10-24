import AVFoundation
import SwiftUI

struct VoicePickerSheet: View {
    @Bindable var settings: AppSettings
    let document: Document?
    let player: NarrationPlayer
    @Environment(\.dismiss) private var dismiss

    enum Filter: String, CaseIterable {
        case all = "All", female = "Female", male = "Male", slowAndClear = "Slow & clear"
    }

    @State private var filter: Filter = .all
    @State private var libraryVoices: [ElevenLabsVoice] = []
    @State private var mandarinVoices: [ElevenLabsVoice] = []
    @State private var selectedID: String?
    @State private var selectedName: String?
    @State private var onlyThisDocument = false
    @State private var loadError: String?
    @State private var previewer = VoicePreviewer()
    @State private var designDescription = ""
    @State private var designState: DesignState = .idle

    enum DesignState: Equatable {
        case idle, designing, previews([String]), saving, failed(String)
    }

    @State private var designPreviews: [VoicePreview] = []

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
                    filterChips
                    if let loadError {
                        Text(loadError).font(.meta13).foregroundStyle(Color.newWord)
                    }
                    if !filtered(libraryVoices).isEmpty {
                        sectionLabel("Your voices")
                        voiceRows(filtered(libraryVoices))
                    }
                    if !filtered(mandarinVoices).isEmpty {
                        sectionLabel("Native Mandarin")
                        voiceRows(filtered(mandarinVoices))
                        Text("Library voices need a paid ElevenLabs plan to use through the API.")
                            .font(.meta12)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    if libraryVoices.isEmpty && mandarinVoices.isEmpty && loadError == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    designCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            footer
        }
        .background(Color.background)
        .task { await loadVoices() }
        .onAppear {
            selectedID = settings.voiceID(for: document)
            selectedName = settings.resolvedVoiceName
            onlyThisDocument = document?.voiceOverrideID != nil
        }
        .onDisappear { previewer.stop() }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases, id: \.self) { option in
                    Button(option.rawValue) { filter = option }
                        .font(.geist(15, filter == option ? .medium : .regular))
                        .foregroundStyle(filter == option ? Color.inkInverse : Color.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Capsule().fill(filter == option ? Color.ink : Color.background))
                        .overlay(Capsule().strokeBorder(filter == option ? Color.clear : Color.hairline))
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.meta13).foregroundStyle(Color.inkSecondary).padding(.top, 4)
    }

    private func voiceRows(_ voices: [ElevenLabsVoice]) -> some View {
        VStack(spacing: 4) {
            ForEach(voices) { voice in
                let isSelected = voice.id == selectedID
                HStack(spacing: 14) {
                    VoiceAvatar(name: voice.shortName)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(voice.shortName).font(.geist(16, .medium)).foregroundStyle(Color.ink)
                        Text(voice.subtitle).font(.meta13).foregroundStyle(Color.inkSecondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if isSelected {
                        Image(systemName: "checkmark").font(.system(size: 16, weight: .regular)).frame(width: 44, height: 44)
                    } else if let url = voice.previewURL {
                        Button {
                            previewer.toggle(url, id: voice.id)
                        } label: {
                            Image(systemName: previewer.playingID == voice.id ? "waveform" : "play.fill")
                                .font(.system(size: 14))
                                .symbolEffect(.variableColor.iterative, isActive: previewer.playingID == voice.id)
                                .frame(width: 40, height: 40)
                                .overlay(Circle().strokeBorder(previewer.playingID == voice.id ? Color.ink : Color.hairline, lineWidth: previewer.playingID == voice.id ? 1.5 : 1))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Preview \(voice.shortName)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isSelected ? Color.surface : .clear))
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedID = voice.id
                    selectedName = voice.shortName
                }
            }
        }
    }

    private var designCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Design your own voice").font(.geist(16, .medium))
            HStack {
                TextField("A patient teacher from Chengdu…", text: $designDescription, axis: .vertical)
                    .font(.body15)
                    .lineLimit(1...3)
                    .submitLabel(.go)
                    .onSubmit(designVoice)
                if designState == .designing || designState == .saving {
                    ProgressView()
                } else if !designDescription.isEmpty {
                    Button("Create", action: designVoice).font(.geist(15, .medium))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.hairline))

            if case .failed(let message) = designState {
                Text(message).font(.meta13).foregroundStyle(Color.newWord)
            }
            if !designPreviews.isEmpty {
                ForEach(Array(designPreviews.enumerated()), id: \.element.id) { offset, preview in
                    HStack {
                        Button {
                            previewer.play(preview.audio, id: preview.id)
                        } label: {
                            Label("Option \(offset + 1)", systemImage: previewer.playingID == preview.id ? "waveform" : "play.fill")
                        }
                        Spacer()
                        Button("Keep") { saveDesigned(preview) }.buttonStyle(.pillSecondary)
                    }
                    .font(.body15)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hairline))
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
                Text("Use \(selectedName ?? "voice")").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(height: 52))
            .disabled(selectedID == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.background)
    }

    private func filtered(_ voices: [ElevenLabsVoice]) -> [ElevenLabsVoice] {
        switch filter {
        case .all: voices
        case .female: voices.filter(\.isFemale)
        case .male: voices.filter(\.isMale)
        case .slowAndClear: voices.filter(\.isSlowAndClear)
        }
    }

    private func loadVoices() async {
        let client = ElevenLabsClient()
        async let library = client.libraryVoices()
        async let mandarin = client.mandarinVoices()
        do {
            libraryVoices = try await library.sorted { ($0.isCustom ? 0 : 1, $0.name) < ($1.isCustom ? 0 : 1, $1.name) }
        } catch {
            loadError = error.localizedDescription
        }
        mandarinVoices = (try? await mandarin) ?? []
    }

    private func apply() {
        guard let selectedID else { return }
        if let document, onlyThisDocument {
            document.voiceOverrideID = selectedID
        } else {
            document?.voiceOverrideID = nil
            settings.voiceID = selectedID
            settings.voiceName = selectedName
        }
    }

    private static let designSample = "大家好，今天我们一起读一个关于周末爬山的小故事。周末的早上，我和朋友去了城外的一座小山。山不高，但是路很长。我们一边走一边聊天，聊工作，也聊以后的打算。到了山顶，风很大，天也很蓝。"

    private func designVoice() {
        let description = designDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return }
        designState = .designing
        designPreviews = []
        Task {
            do {
                let prompt = "\(description). Speaks natural standard Mandarin Chinese."
                designPreviews = try await ElevenLabsClient().designVoicePreviews(description: prompt, sampleText: Self.designSample)
                designState = .previews(designPreviews.map(\.id))
            } catch {
                designState = .failed(Self.friendly(error))
            }
        }
    }

    private func saveDesigned(_ preview: VoicePreview) {
        designState = .saving
        let name = String(designDescription.prefix(24))
        Task {
            do {
                let id = try await ElevenLabsClient().saveDesignedVoice(previewID: preview.id, name: name, description: designDescription)
                selectedID = id
                selectedName = name
                designPreviews = []
                designState = .idle
                await loadVoices()
            } catch {
                designState = .failed(Self.friendly(error))
            }
        }
    }

    private static func friendly(_ error: Error) -> String {
        if case ServiceError.http(let status, _) = error, status == 402 || status == 403 {
            return "Designing voices needs a paid ElevenLabs plan."
        }
        return error.localizedDescription
    }
}

/// Plays voice previews (remote sample URLs or designed-voice audio) one at a time.
@Observable
final class VoicePreviewer {
    private(set) var playingID: String?
    private var player: AVPlayer?
    private var dataPlayer: AVAudioPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(_ url: URL, id: String) {
        if playingID == id {
            stop()
            return
        }
        stop()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playingID = nil }
        }
        player.play()
        self.player = player
        playingID = id
    }

    func play(_ audio: Data, id: String) {
        stop()
        dataPlayer = try? AVAudioPlayer(data: audio)
        dataPlayer?.play()
        playingID = id
    }

    func stop() {
        player?.pause()
        player = nil
        dataPlayer?.stop()
        dataPlayer = nil
        playingID = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}
