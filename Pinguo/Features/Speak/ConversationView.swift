import SwiftData
import SwiftUI

struct ConversationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(ReviewStore.self) private var reviews
    @Environment(WordStateStore.self) private var wordStates
    @State private var model: ConversationModel?
    @State private var talk = PushToTalk()
    @State private var typing = false
    @State private var draft = ""
    @State private var listeningInEnglish = false
    @State private var lookedUpWord: LookedUpConversationWord?
    @State private var showsSummary = false
    @FocusState private var draftFocused: Bool

    let conversation: Conversation
    let scenario: Scenario

    var body: some View {
        VStack(spacing: 0) {
            if let model {
                messageList(model)
                composer(model)
            } else {
                Spacer()
            }
        }
        .background(Color.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(scenario.title).font(.geist(16, .semibold)).lineLimit(1)
                    Text("with \(settings.resolvedVoiceName) · HSK \(conversation.hskLevel)").font(.meta12).foregroundStyle(Color.inkSecondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showsSummary = true } label: { Label("End & summarise", systemImage: "checkmark.circle") }
                    Picker("Level", selection: Binding(get: { conversation.hskLevel }, set: { conversation.hskLevel = $0 })) {
                        ForEach(1...6, id: \.self) { Text("HSK \($0)").tag($0) }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Conversation options")
            }
        }
        .task {
            if model == nil {
                model = ConversationModel(conversation: conversation, scenario: scenario, context: modelContext)
            }
            await model?.openIfNeeded(deckWords: reviews.practiceWords(), onTutorMessage: play)
        }
        .sheet(item: $lookedUpWord) { item in
            WordCardView(word: item.word, sentence: item.sentence, sentenceContext: "", onSpeak: speak) {
                ReviewToggleButton(word: item.word) {
                    reviews.addWordCard(word: item.word, sentence: item.sentence, document: nil, chapterTitle: scenario.title,
                                        voiceID: settings.resolvedVoiceID, modelID: settings.voiceModelID)
                }
            }
            .padding(12)
            .presentationDetents([.medium])
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $showsSummary) {
            if let model {
                ConversationSummaryView(model: model, scenario: scenario) {
                    showsSummary = false
                    dismiss()
                }
                .presentationDetents([.large])
            }
        }
        .onDisappear { talk.cancel() }
    }

    private func messageList(_ model: ConversationModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.messages) { message in
                        if message.role == .tutor {
                            TutorBubble(message: message, pinyinMode: settings.pinyinMode, onSpeak: { speak(message.text) }) { word in
                                lookedUpWord = LookedUpConversationWord(word: word, sentence: message.text)
                            }
                        } else {
                            LearnerBubble(message: message)
                        }
                    }
                    if model.lastTurnWasOnDevice, !model.isThinking {
                        Label("Offline · on-device tutor (Apple Intelligence)", systemImage: "airplane")
                            .font(.meta12)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    if model.isThinking {
                        ThinkingDots().padding(.leading, 4).id("thinking")
                    }
                    if let error = model.errorMessage {
                        HStack {
                            Text(error).font(.meta13).foregroundStyle(Color.newWord)
                            Button("Retry") {
                                Task { await model.retry(deckWords: reviews.practiceWords(), onTutorMessage: play) }
                            }
                            .font(.geist(13, .medium))
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.count) { scrollToBottom(proxy) }
            .onChange(of: model.isThinking) { scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private func composer(_ model: ConversationModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.suggestions.isEmpty && !talk.isRecording {
                Text("Try saying").font(.meta13).foregroundStyle(Color.inkSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.suggestions, id: \.self) { suggestion in
                            Button { send(suggestion, english: false) } label: {
                                Text(suggestion)
                                    .font(.chineseSerif(17))
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 16)
                                    .frame(height: 40)
                                    .overlay(Capsule().strokeBorder(Color.hairline))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if talk.isRecording {
                Text(talk.partialTranscript.isEmpty ? (listeningInEnglish ? "Listening in English…" : "正在听…") : talk.partialTranscript)
                    .font(.chineseSerif(19))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if let error = talk.errorMessage {
                Text(error).font(.meta12).foregroundStyle(Color.newWord)
            }
            if typing {
                HStack(spacing: 10) {
                    CircleIconButton(systemName: "mic") { typing = false }
                        .accessibilityLabel("Speak instead")
                    TextField("用中文回答…", text: $draft, axis: .vertical)
                        .font(.chineseSerif(18))
                        .lineLimit(1...4)
                        .focused($draftFocused)
                        .submitLabel(.send)
                        .onSubmit(sendDraft)
                        .onChange(of: draft) { _, text in
                            // A multi-line field inserts Return as a newline; treat it as send.
                            if text.hasSuffix("\n") {
                                draft.removeLast()
                                sendDraft()
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.hairline))
                    CircleIconButton(systemName: "arrow.up", filled: true, action: sendDraft)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isThinking)
                        .accessibilityLabel("Send")
                }
            } else {
                HStack {
                    CircleIconButton(systemName: "keyboard") {
                        typing = true
                        draftFocused = true
                    }
                    .accessibilityLabel("Type instead")
                    Spacer()
                    VStack(spacing: 8) {
                        HoldToTalkButton(isRecording: talk.isRecording && !listeningInEnglish, size: 72, label: Image(systemName: "mic")) {
                            beginListening(english: false)
                        } onRelease: {
                            finishListening()
                        }
                        Text("Hold to speak").font(.meta13).foregroundStyle(Color.inkSecondary)
                    }
                    Spacer()
                    HoldToTalkButton(isRecording: talk.isRecording && listeningInEnglish, size: 44, label: Text("EN").font(.geist(13, .semibold))) {
                        beginListening(english: true)
                    } onRelease: {
                        finishListening()
                    }
                    .accessibilityLabel("Hold to say it in English")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.background)
        .disabled(model.isThinking && !talk.isRecording)
    }

    private func beginListening(english: Bool) {
        listeningInEnglish = english
        Task { await talk.start(locale: Locale(identifier: english ? "en-US" : "zh-CN")) }
    }

    private func finishListening() {
        let english = listeningInEnglish
        Task {
            let text = await talk.stop()
            if !text.isEmpty { send(text, english: english) }
        }
    }

    private func sendDraft() {
        let text = draft
        draft = ""
        draftFocused = false
        send(text, english: !ChineseText.containsHan(text) && !text.isEmpty)
    }

    private func send(_ text: String, english: Bool) {
        guard let model else { return }
        Task { await model.send(text, inEnglish: english, deckWords: reviews.practiceWords(), onTutorMessage: play) }
    }

    private func play(_ message: Message) {
        speak(message.text)
    }

    private func speak(_ text: String) {
        Pronunciation.shared.speak(text, voiceID: settings.resolvedVoiceID, modelID: settings.voiceModelID)
    }
}

private struct LookedUpConversationWord: Identifiable {
    let word: String
    let sentence: String
    var id: String { word + sentence }
}

struct TutorBubble: View {
    let message: Message
    let pinyinMode: PinyinMode
    let onSpeak: () -> Void
    let onLookUp: (String) -> Void
    @State private var showsTranslation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                TappableSentence(text: message.text, highlighted: nil, fontSize: 19, onTap: onLookUp)
                if pinyinMode != .off, let pinyin = message.pinyin {
                    Text(pinyin).font(.geist(14)).foregroundStyle(Color.inkSecondary)
                }
                if showsTranslation, let english = message.englishText {
                    Text(english).font(.body15).foregroundStyle(Color.ink).padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, bottomLeading: 6, bottomTrailing: 22, topTrailing: 22), style: .continuous).fill(Color.surface))
            .frame(maxWidth: 320, alignment: .leading)

            HStack(spacing: 18) {
                Button(action: onSpeak) { Image(systemName: "speaker.wave.2").font(.system(size: 14, weight: .light)) }
                    .accessibilityLabel("Replay")
                Button(showsTranslation ? "Hide" : "Translate") { withAnimation { showsTranslation.toggle() } }
                    .font(.meta13)
            }
            .foregroundStyle(Color.inkSecondary)
            .buttonStyle(.plain)
            .padding(.leading, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LearnerBubble: View {
    let message: Message

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text(message.text)
                .font(message.wasEnglish ? .body17 : .chineseSerif(19))
                .foregroundStyle(Color.inkInverse)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 22, bottomLeading: 22, bottomTrailing: 6, topTrailing: 22), style: .continuous).fill(Color.ink))
                .frame(maxWidth: 300, alignment: .trailing)
            if message.hasCorrection {
                CorrectionCard(message: message).frame(maxWidth: 300, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct CorrectionCard: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("More natural").font(.meta12).foregroundStyle(Color.inkSecondary)
            Text(highlighted).font(.chineseSerif(18))
            if let reason = message.correctionReason, !reason.isEmpty {
                Text(reason).font(.meta13).foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.background))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.hairline))
    }

    private var highlighted: AttributedString {
        var text = AttributedString(message.correctionNatural ?? "")
        text.foregroundColor = Color.ink
        if let changed = message.correctionChanged, !changed.isEmpty, let range = text.range(of: changed) {
            text[range].backgroundColor = Color.learning
            text[range].foregroundColor = Color.learningText
        }
        return text
    }
}

struct HoldToTalkButton<Label: View>: View {
    let isRecording: Bool
    let size: CGFloat
    let label: Label
    let onPress: () -> Void
    let onRelease: () -> Void
    @GestureState private var isPressed = false

    var body: some View {
        label
            .font(.system(size: size * 0.32, weight: .light))
            .foregroundStyle(size > 60 ? Color.inkInverse : Color.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(size > 60 ? Color.ink : Color.background))
            .overlay { if size <= 60 { Circle().strokeBorder(isRecording ? Color.ink : Color.hairline, lineWidth: isRecording ? 2 : 1) } }
            .overlay {
                if isRecording {
                    Circle().strokeBorder(Color.newWord.opacity(0.5), lineWidth: 3).scaleEffect(1.15)
                }
            }
            .scaleEffect(isPressed ? 1.08 : 1)
            .animation(.snappy(duration: 0.15), value: isPressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in state = true }
            )
            .onChange(of: isPressed) { _, pressed in
                pressed ? onPress() : onRelease()
            }
            .accessibilityAddTraits(.isButton)
    }
}

struct ThinkingDots: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color.inkSecondary)
                    .frame(width: 7, height: 7)
                    .opacity(0.3 + 0.7 * max(0, sin(phase + Double(index) * 0.8)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Capsule().fill(Color.surface))
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = .pi * 2 }
        }
        .accessibilityLabel("Tutor is replying")
    }
}

struct ConversationSummaryView: View {
    let model: ConversationModel
    let scenario: Scenario
    let onDone: () -> Void
    @Environment(WordStateStore.self) private var wordStates
    @Environment(ReviewStore.self) private var reviews
    @Environment(AppSettings.self) private var settings
    @State private var added = false

    var body: some View {
        let words = model.newWordsUsed(wordStates: wordStates)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("\(model.messages.filter { $0.role == .learner }.count) things you said · \(model.corrections.count) corrections")
                        .font(.body15)
                        .foregroundStyle(Color.inkSecondary)
                    if !words.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "New words used")
                            ForEach(words, id: \.self) { word in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(word).font(.chineseSerif(19))
                                    Text(ChineseDictionary.shared.lookup(word)?.pinyin ?? "").font(.meta13).foregroundStyle(Color.inkSecondary)
                                    Spacer()
                                    Text(ChineseDictionary.shared.lookup(word)?.shortGloss ?? "").font(.meta13).foregroundStyle(Color.inkSecondary).lineLimit(1)
                                }
                            }
                        }
                    }
                    if !model.corrections.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Corrections")
                            ForEach(model.corrections) { message in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(message.text).font(.chineseSerif(16)).strikethrough().foregroundStyle(Color.inkSecondary)
                                    CorrectionCard(message: message)
                                }
                            }
                        }
                    }
                    Button {
                        addAll(words)
                    } label: {
                        Text(added ? "Added to review" : "Add words and corrections to review").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(height: 52))
                    .disabled(added || (words.isEmpty && model.corrections.isEmpty))
                }
                .padding(24)
            }
            .background(Color.background)
            .navigationTitle("Session summary")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) }
            }
        }
    }

    private func addAll(_ words: [String]) {
        let tutorLines = model.messages.filter { $0.role == .tutor }
        for word in words {
            let sentence = tutorLines.first { $0.text.contains(word) }?.text ?? word
            reviews.addWordCard(word: word, sentence: sentence, document: nil, chapterTitle: scenario.title,
                                voiceID: settings.resolvedVoiceID, modelID: settings.voiceModelID)
        }
        for correction in model.corrections {
            if let natural = correction.correctionNatural {
                reviews.addSentenceCard(sentence: natural, document: nil, chapterTitle: scenario.title,
                                        voiceID: settings.resolvedVoiceID, modelID: settings.voiceModelID)
            }
        }
        added = true
    }
}
