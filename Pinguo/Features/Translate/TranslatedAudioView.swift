import AVFoundation
import SwiftUI

struct TranslatedAudioView: View {
    let document: Document
    @Environment(AppSettings.self) private var settings
    @Environment(NarrationPlayer.self) private var player
    @Environment(WordStateStore.self) private var wordStates
    @Environment(ReviewStore.self) private var reviews
    @State private var display: Display = .both
    @State private var original = OriginalAudioPlayer()
    @State private var lookedUp: LookedUpLine?
    @State private var showsVoicePicker = false

    enum Display: Hashable { case chinese, both, english }

    private var sentences: [Sentence] {
        document.orderedChapters.first?.orderedSentences ?? []
    }

    private var isActive: Bool { player.isLoaded(document, chapter: 0) }

    var body: some View {
        VStack(spacing: 0) {
            SegmentedPicker(options: [(Display.chinese, "中文"), (.both, "Both"), (.english, "English")], selection: $display)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(sentences, id: \.index) { sentence in
                            line(sentence).id(sentence.index)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: player.currentSentence) {
                    guard isActive, let current = player.currentSentence else { return }
                    withAnimation { proxy.scrollTo(current, anchor: UnitPoint(x: 0.5, y: 0.25)) }
                }
            }

            PlayerBar(
                player: player,
                isActive: isActive,
                voiceName: settings.resolvedVoiceName,
                onPlay: { play(from: document.lastSentenceIndex) },
                onChooseVoice: { showsVoicePicker = true }
            )

            HStack(spacing: 12) {
                Button(action: playOriginal) {
                    Text("EN")
                        .font(.geist(13, .semibold))
                        .foregroundStyle(original.isPlaying ? Color.inkInverse : Color.ink)
                        .frame(width: 48, height: 48)
                        .background(Circle().fill(original.isPlaying ? Color.ink : Color.background))
                        .overlay(Circle().strokeBorder(Color.hairline))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play the original English for this line")
                NavigationLink {
                    ReaderView(document: document)
                } label: {
                    Text("Open in reader").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pillSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .background(Color.background)
        }
        .background(Color.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(document.title).font(.geist(15, .medium)).lineLimit(1)
                    Text(subtitle).font(.meta12).foregroundStyle(Color.inkSecondary)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .sheet(item: $lookedUp) { item in
            WordCardView(word: item.word, sentence: item.sentence, onSpeak: speak) {
                ReviewToggleButton(word: item.word) {
                    reviews.addWordCard(word: item.word, sentence: item.sentence, document: document, chapterTitle: nil,
                                        voiceID: settings.voiceID(for: document))
                }
            }
            .padding(12)
            .presentationDetents([.medium])
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showsVoicePicker) {
            VoicePickerSheet(settings: settings, document: document, player: player)
        }
        .onAppear { document.lastOpenedAt = .now }
        .onDisappear { original.stop() }
    }

    private var subtitle: String {
        let duration = document.durationSeconds.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) }
        return ["Translated from English", duration].compactMap { $0 }.joined(separator: " · ")
    }

    private func line(_ sentence: Sentence) -> some View {
        let isCurrent = isActive && player.currentSentence == sentence.index
        return VStack(alignment: .leading, spacing: 8) {
            if display != .english {
                TappableSentence(text: sentence.text, highlighted: nil, fontSize: 19, showsFamiliarity: true) { word in
                    wordStates.recordLookup(of: word)
                    lookedUp = LookedUpLine(word: word, sentence: sentence.text)
                }
            }
            if display != .chinese, let english = sentence.englishText {
                Text(english)
                    .font(display == .english ? .body17 : .body15)
                    .foregroundStyle(display == .english ? Color.ink : Color.inkSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(isCurrent ? Color.surface : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { play(from: sentence.index) }
        .contextMenu {
            Button { play(from: sentence.index) } label: { Label("Play from here", systemImage: "play") }
            Button { original.play(sentence) } label: { Label("Play original English", systemImage: "speaker.wave.2") }
        }
    }

    private func play(from index: Int) {
        original.stop()
        player.play(document, chapter: 0, from: index, voiceID: settings.voiceID(for: document))
    }

    /// EN: the original English for the line being spoken (or the bookmarked line).
    private func playOriginal() {
        let index = (isActive ? player.currentSentence : nil) ?? document.lastSentenceIndex
        guard let sentence = sentences.first(where: { $0.index == index }) else { return }
        if player.isPlaying { player.pause() }
        original.play(sentence, from: document)
    }

    private func speak(_ text: String) {
        Pronunciation.shared.speak(text, voiceID: settings.voiceID(for: document))
    }
}

private struct LookedUpLine: Identifiable {
    let word: String
    let sentence: String
    var id: String { word + sentence }
}

/// Plays one line's span of the source recording.
@Observable
final class OriginalAudioPlayer {
    private(set) var isPlaying = false
    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?

    func play(_ sentence: Sentence, from document: Document? = nil) {
        guard let fileName = (document ?? sentence.chapter?.document)?.sourceAudioFileName,
              let start = sentence.sourceAudioStart else { return }
        stop()
        let url = AudioTranslation.sourceAudioDirectory.appending(path: fileName)
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        player.currentTime = max(0, start - 0.1)
        player.play()
        self.player = player
        isPlaying = true
        let length = max(0.5, (sentence.sourceAudioEnd ?? start + 5) - start + 0.3)
        stopTask = Task {
            try? await Task.sleep(for: .seconds(length))
            guard !Task.isCancelled else { return }
            stop()
        }
    }

    func stop() {
        stopTask?.cancel()
        player?.stop()
        player = nil
        isPlaying = false
    }
}
