import SwiftUI

struct ReaderView: View {
    @State private var model: ReaderModel
    @Environment(WordStateStore.self) private var wordStates
    @Environment(AppSettings.self) private var settings
    @Environment(NarrationPlayer.self) private var player
    @Environment(ReviewStore.self) private var reviews
    @State private var showsSettings = false
    @State private var showsVoicePicker = false
    @State private var showsContents = false
    @State private var scrolledParagraphID: Int?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesSidePanel: Bool { horizontalSizeClass == .regular }

    init(document: Document) {
        _model = State(initialValue: ReaderModel(document: document))
    }

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: 0) {
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

            if !usesSidePanel {
                overlayCard
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
            if usesSidePanel {
                Rectangle().fill(Color.hairline).frame(width: 1)
                wordPanel.frame(width: 360)
            }
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
        .toolbar {
            if usesSidePanel {
                ToolbarItem(placement: .topBarTrailing) {
                    @Bindable var settings = settings
                    SegmentedPicker(options: [(PinyinMode.always, "Pinyin"), (.newWordsOnly, "New only"), (.off, "Off")], selection: $settings.pinyinMode, height: 36)
                        .frame(width: 230)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .background { keyboardShortcuts }
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
                ReviewToggleButton(word: selection.word) {
                    addCard(word: selection.word, sentence: sentence.text)
                }
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
                Button {
                    reviews.addSentenceCard(
                        sentence: sentence.text,
                        document: model.document,
                        chapterTitle: model.chapter?.title,
                        voiceID: settings.voiceID(for: model.document),
                        modelID: settings.voiceModelID
                    )
                    model.sentenceActionsIndex = nil
                } label: {
                    Image(systemName: "rectangle.stack.badge.plus").font(.system(size: 17, weight: .light)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .overlay(Circle().strokeBorder(Color.hairline))
                .accessibilityLabel("Add sentence card")
            }
            .frame(maxWidth: 520)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// iPad: the selected word and the New words around the reading position, beside the text.
    private var wordPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let selection = model.selection, let sentence = model.sentence(selection.sentenceIndex) {
                    WordCardView(
                        word: selection.word,
                        sentence: sentence.text,
                        sentenceContext: model.context(around: sentence.id),
                        onSpeak: speak,
                        showsChrome: false
                    ) {
                        ReviewToggleButton(word: selection.word) { addCard(word: selection.word, sentence: sentence.text) }
                    }
                } else if let index = model.sentenceActionsIndex, let sentence = model.sentence(index) {
                    SentenceCardView(sentence: sentence, context: model.context(around: index)) {
                        model.sentenceActionsIndex = nil
                    } actions: {
                        Button("Play from here") { playFrom(sentence.id) }.buttonStyle(.pill)
                    }
                } else {
                    Text("Tap a word to look it up.").font(.body15).foregroundStyle(Color.inkSecondary)
                }
                Hairline()
                newOnThisPage
            }
            .padding(28)
        }
        .background(Color.background)
    }

    private var pageNewWords: [(word: String, sentence: ReaderSentence)] {
        let anchor = scrolledParagraphID ?? model.paragraphs.first?.id ?? 0
        var seen = Set<String>()
        return model.paragraphs
            .filter { $0.id >= anchor && $0.id < anchor + 6 }
            .flatMap(\.sentences)
            .flatMap { sentence in sentence.lexicalWords.map { (word: $0, sentence: sentence) } }
            .filter { wordStates.familiarity(of: $0.word) == .new && ChineseDictionary.shared.lookup($0.word) != nil && seen.insert($0.word).inserted }
    }

    private var newOnThisPage: some View {
        let words = pageNewWords
        return VStack(alignment: .leading, spacing: 12) {
            Text("New on this page").font(.meta13).foregroundStyle(Color.inkSecondary)
            if words.isEmpty {
                Text("No new words here.").font(.body15).foregroundStyle(Color.inkSecondary)
            }
            ForEach(words.prefix(12), id: \.word) { item in
                Button {
                    if let token = item.sentence.tokens.first(where: { $0.text == item.word }) { select(item.sentence, token) }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.word).font(.chineseSerif(19)).foregroundStyle(Color.ink)
                        Spacer()
                        Text(ChineseDictionary.shared.lookup(item.word)?.shortGloss ?? "").font(.meta13).foregroundStyle(Color.inkSecondary).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
            }
            if !words.isEmpty {
                Button("Add all to review") {
                    for item in words { addCard(word: item.word, sentence: item.sentence.text) }
                }
                .buttonStyle(PillButtonStyle(kind: .secondary, height: 44))
                .padding(.top, 4)
            }
        }
    }

    /// Hardware keyboard: space play/pause, ←/→ previous/next sentence, 1–5 familiarity of the selected word.
    private var keyboardShortcuts: some View {
        Group {
            Button("Play or pause") {
                player.isLoaded(model.document, chapter: model.chapterIndex) ? player.togglePlayPause() : playFrom(firstVisibleSentence)
            }
            .keyboardShortcut(.space, modifiers: [])
            Button("Previous sentence") { player.skipSentence(by: -1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Next sentence") { player.skipSentence(by: 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            ForEach(Familiarity.allCases, id: \.self) { level in
                Button("Mark \(level.label)") {
                    if let word = model.selection?.word { wordStates.setFamiliarity(level, for: word) }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(level.rawValue + 1)")), modifiers: [])
            }
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        if let selection = model.selection, let sentence = model.sentence(selection.sentenceIndex) {
            wordStates.recordLookup(of: selection.word)
            if model.document.makesCardsFromTaps, wordStates.familiarity(of: selection.word) != .known {
                addCard(word: selection.word, sentence: sentence.text)
            }
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

    private func addCard(word: String, sentence: String) {
        reviews.addWordCard(
            word: word,
            sentence: sentence,
            document: model.document,
            chapterTitle: model.chapter?.title,
            voiceID: settings.voiceID(for: model.document),
            modelID: settings.voiceModelID
        )
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
