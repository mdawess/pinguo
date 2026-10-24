import SwiftUI

struct ReaderView: View {
    @State private var model: ReaderModel
    @Environment(WordStateStore.self) private var wordStates
    @Environment(AppSettings.self) private var settings
    @Environment(NarrationPlayer.self) private var player
    @State private var showsSettings = false
    @State private var showsVoicePicker = false
    @State private var showsContents = false
    @State private var scrolledParagraphID: Int?

    init(document: Document) {
        _model = State(initialValue: ReaderModel(document: document))
    }

    var body: some View {
        VStack(spacing: 0) {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: paragraphSpacing) {
                        ForEach(model.paragraphs) { paragraph in
                            ParagraphView(
                                paragraph: paragraph,
                                model: model,
                                style: cellStyle,
                                pinyinMode: settings.pinyinMode,
                                lineSpacing: lineSpacing,
                                onSelect: select
                            )
                            .id(paragraph.id)
                        }
                        chapterFooter
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 26)
                    .padding(.top, 12)
                    .padding(.bottom, 240)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissOverlays() }
                }
                .scrollPosition(id: $scrolledParagraphID, anchor: .top)
                .onAppear {
                    if let target = model.restoreParagraphID {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    followPlayer(proxy)
                }
                .onChange(of: model.chapterIndex) {
                    if model.spokenSentenceIndex == nil {
                        proxy.scrollTo(model.paragraphs.first?.id, anchor: .top)
                    }
                }
                .onChange(of: player.currentSentence) { followPlayer(proxy) }
                .onChange(of: player.chapterIndex) { followPlayer(proxy) }
            }
            .onChange(of: scrolledParagraphID) { _, paragraphID in
                if let paragraphID { model.saveProgress(paragraphID: paragraphID) }
            }

            overlayCard
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
            PlayerBar(
                player: player,
                isActive: player.isLoaded(model.document, chapter: model.chapterIndex),
                voiceName: voiceName,
                onPlay: { playFrom(firstVisibleSentence) },
                onChooseVoice: { showsVoicePicker = true }
            )
        }
        .background(settings.theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(model.document.title).font(.geist(15, .medium)).lineLimit(1)
                    if let chapter = model.chapter {
                        Text(chapter.title).font(.meta12).foregroundStyle(Color.inkSecondary).lineLimit(1)
                    }
                }
                .onTapGesture { showsContents = true }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showsContents = true } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("Contents")
                Button { showsSettings = true } label: { Text("Aa").font(.geist(17, .semibold)) }
                    .accessibilityLabel("Reading settings")
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(settings.theme.colorScheme)
        .sheet(isPresented: $showsSettings) {
            ReadingSettingsSheet(settings: settings)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsVoicePicker) {
            VoicePickerSheet(settings: settings, document: model.document, player: player)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showsContents) {
            ChapterListSheet(chapters: model.chapters, current: model.chapterIndex) { index in
                model.loadChapter(index)
                showsContents = false
            }
            .presentationDetents([.medium, .large])
        }
        .animation(.snappy(duration: 0.25), value: model.selection)
        .animation(.snappy(duration: 0.25), value: model.sentenceActionsIndex)
    }

    @ViewBuilder private var overlayCard: some View {
        if let selection = model.selection, let sentence = model.sentence(selection.sentenceIndex) {
            WordCardView(
                word: selection.word,
                sentence: sentence.text,
                sentenceContext: model.context(around: sentence.id),
                onSpeak: speak
            ) {
                Button("Mark as known") {
                    wordStates.setFamiliarity(.known, for: selection.word)
                    model.selection = nil
                }
                .buttonStyle(.pill)
            }
            .frame(maxWidth: 520)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let index = model.sentenceActionsIndex, let sentence = model.sentence(index) {
            SentenceCardView(sentence: sentence, context: model.context(around: index)) {
                model.sentenceActionsIndex = nil
            } actions: {
                Button("Play from here") {
                    playFrom(sentence.id)
                    model.sentenceActionsIndex = nil
                }
                .buttonStyle(.pill)
                Button("Replay") { speak(sentence.text) }
                    .buttonStyle(.pillSecondary)
            }
            .frame(maxWidth: 520)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder private var chapterFooter: some View {
        let newWords = model.newWords(using: wordStates)
        VStack(alignment: .leading, spacing: 14) {
            Hairline().padding(.vertical, 12)
            if !newWords.isEmpty {
                Text("\(newWords.count) words in this chapter are still New.")
                    .font(.body15)
                    .foregroundStyle(Color.inkSecondary)
                Button("Mark remaining New words as Known") {
                    wordStates.markKnown(newWords)
                }
                .buttonStyle(.pillSecondary)
            }
            if model.hasNextChapter {
                Button {
                    model.loadChapter(model.chapterIndex + 1)
                } label: {
                    Label("Next chapter", systemImage: "arrow.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill)
            } else {
                Text("The end").font(.body15).foregroundStyle(Color.inkSecondary)
            }
        }
        .onAppear { model.markChapterFinished() }
    }

    private func select(_ sentence: ReaderSentence, _ token: ReaderToken) {
        model.sentenceActionsIndex = nil
        model.select(sentenceIndex: sentence.id, token: token)
        if let selection = model.selection {
            wordStates.recordLookup(of: selection.word)
        }
    }

    private var firstVisibleSentence: Int {
        let paragraphID = scrolledParagraphID ?? model.restoreParagraphID
        return model.paragraphs.first { $0.id == paragraphID }?.sentences.first?.id ?? 0
    }

    private var voiceName: String {
        model.document.voiceOverrideID == nil ? settings.resolvedVoiceName : "Voice"
    }

    private func playFrom(_ sentenceIndex: Int) {
        player.play(
            model.document,
            chapter: model.chapterIndex,
            from: sentenceIndex,
            voiceID: settings.voiceID(for: model.document),
            modelID: settings.voiceModelID
        )
    }

    private func speak(_ text: String) {
        Pronunciation.shared.speak(text, voiceID: settings.voiceID(for: model.document), modelID: settings.voiceModelID)
    }

    /// Keeps the spoken sentence highlighted and in the upper third, following the player across chapters.
    private func followPlayer(_ proxy: ScrollViewProxy) {
        guard player.document?.id == model.document.id else {
            model.spokenSentenceIndex = nil
            return
        }
        if player.chapterIndex != model.chapterIndex {
            model.loadChapter(player.chapterIndex, restoringSentence: player.currentSentence ?? 0)
        }
        model.spokenSentenceIndex = player.currentSentence
        guard let sentence = player.currentSentence.flatMap(model.sentence), model.selection == nil else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            proxy.scrollTo(sentence.paragraphIndex, anchor: UnitPoint(x: 0.5, y: 0.2))
        }
    }

    private func dismissOverlays() {
        model.selection = nil
        model.sentenceActionsIndex = nil
    }

    private var cellStyle: WordCellStyle {
        WordCellStyle(
            fontSize: settings.textSize,
            showsRubyRow: settings.pinyinMode != .off,
            toneColours: settings.toneColours,
            traditional: settings.script == .traditional
        )
    }

    private var lineSpacing: CGFloat {
        settings.pinyinMode == .off ? settings.textSize * 0.95 : settings.textSize * 0.55
    }

    private var paragraphSpacing: CGFloat {
        settings.textSize * 1.2
    }
}

struct ParagraphView: View {
    let paragraph: ReaderParagraph
    let model: ReaderModel
    let style: WordCellStyle
    let pinyinMode: PinyinMode
    let lineSpacing: CGFloat
    let onSelect: (ReaderSentence, ReaderToken) -> Void
    @Environment(WordStateStore.self) private var wordStates

    var body: some View {
        FlowLayout(lineSpacing: lineSpacing) {
            ForEach(paragraph.sentences) { sentence in
                ForEach(sentence.tokens) { token in
                    let familiarity = token.isLexical ? wordStates.familiarity(of: token.text) : .known
                    WordCell(
                        token: token,
                        annotation: model.annotations[token.text],
                        familiarity: familiarity,
                        showsPinyin: token.isLexical && (pinyinMode == .always || (pinyinMode == .newWordsOnly && familiarity != .known)),
                        isSelected: model.selection?.sentenceIndex == sentence.id && model.selection?.tokenIndex == token.id,
                        isSpoken: model.spokenSentenceIndex == sentence.id,
                        style: style
                    )
                    .layoutValue(key: FlowLayout.KeepsWithPrevious.self, value: token.isPunctuation)
                    .onTapGesture { onSelect(sentence, token) }
                    .onLongPressGesture(minimumDuration: 0.45) {
                        model.selection = nil
                        model.sentenceActionsIndex = sentence.id
                    }
                }
            }
        }
    }
}

struct ChapterListSheet: View {
    let chapters: [Chapter]
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(chapters, id: \.index) { chapter in
                Button {
                    onSelect(chapter.index)
                } label: {
                    HStack {
                        Text(chapter.title).font(.body15).foregroundStyle(Color.ink)
                        Spacer()
                        if chapter.index == current {
                            Image(systemName: "checkmark").foregroundStyle(Color.ink)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
