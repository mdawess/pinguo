import SwiftUI

struct ReviewSessionView: View {
    @Environment(ReviewStore.self) private var reviews
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var current: Card?
    @State private var isRevealed = false
    @State private var completed = 0
    @State private var remaining = 0
    @State private var lookedUpWord: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 17, weight: .light)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("End review")
                ProgressLine(value: total == 0 ? 1 : Double(completed) / Double(total), height: 4)
                Text("\(completed) / \(total)").font(.meta13.monospacedDigit()).foregroundStyle(Color.inkSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let current {
                ReviewCardFace(card: current, isRevealed: isRevealed, onPlay: { play(current) }, onLookUp: { lookedUpWord = $0 })
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy) { isRevealed = true } }
                    .id(current.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))

                Group {
                    if isRevealed {
                        RatingControl(intervals: reviews.intervals(for: current)) { rate(current, $0) }
                    } else {
                        Button { withAnimation(.snappy) { isRevealed = true } } label: {
                            Text("Show answer").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButtonStyle(kind: .secondary, height: 60))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Text("Done for now").font(.sectionTitle)
                    Text("\(completed) cards reviewed").font(.body15).foregroundStyle(Color.inkSecondary)
                    Button("Close") { dismiss() }.buttonStyle(.pill).padding(.top, 8)
                }
                Spacer()
            }
        }
        .background(Color.background)
        .onAppear(perform: advance)
        .sheet(item: Binding(get: { lookedUpWord.map(LookedUpWord.init) }, set: { lookedUpWord = $0?.word })) { item in
            WordCardView(word: item.word, sentence: current?.sentenceText, sentenceContext: "", onSpeak: { speak($0) }) {
                EmptyView()
            }
            .padding(12)
            .presentationDetents([.medium])
            .presentationBackground(.clear)
        }
    }

    private var total: Int { completed + remaining }

    private func rate(_ card: Card, _ rating: Rating) {
        reviews.rate(card, rating)
        completed += 1
        withAnimation(.snappy) { advance() }
    }

    /// Next due card; learning cards due in the next 20 minutes are pulled forward so a session can finish.
    private func advance() {
        isRevealed = false
        var queue = reviews.dueQueue()
        if queue.isEmpty {
            queue = reviews.dueQueue(now: .now.addingTimeInterval(20 * 60)).filter { $0.state == .learning || $0.state == .relearning }
        }
        current = queue.first
        remaining = queue.count
        if let current, current.kind == .word { play(current) }
    }

    private func play(_ card: Card) {
        speak(card.sentenceText, voiceID: card.audioVoiceID, modelID: card.audioModelID)
    }

    private func speak(_ text: String, voiceID: String? = nil, modelID: String? = nil) {
        Pronunciation.shared.speak(text, voiceID: voiceID ?? settings.resolvedVoiceID, modelID: modelID ?? settings.voiceModelID)
    }
}

private struct LookedUpWord: Identifiable {
    let word: String
    var id: String { word }
}

struct ReviewCardFace: View {
    let card: Card
    let isRevealed: Bool
    let onPlay: () -> Void
    let onLookUp: (String) -> Void

    private var entry: DictionaryEntry? { ChineseDictionary.shared.lookup(card.word) }

    var body: some View {
        VStack(spacing: 0) {
            if let source = card.sourceLine {
                Text(source).font(.meta12).foregroundStyle(Color.inkSecondary).lineLimit(1).padding(.top, 28)
            }
            Spacer(minLength: 24)
            if card.kind == .word {
                Text(card.word)
                    .font(.chineseSerif(72))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(Color.ink)
                    .padding(.bottom, 20)
            }
            TappableSentence(text: card.sentenceText, highlighted: card.kind == .word ? card.word : nil, fontSize: card.kind == .word ? 18 : 26, onTap: onLookUp)
                .padding(.horizontal, 24)
            CircleIconButton(systemName: "speaker.wave.2", action: onPlay)
                .padding(.top, 18)
                .accessibilityLabel("Play sentence")

            if isRevealed {
                Hairline().padding(.horizontal, 24).padding(.vertical, 28)
                VStack(spacing: 8) {
                    if card.kind == .word {
                        Text(entry?.pinyin ?? "").font(.geist(17)).foregroundStyle(Color.inkSecondary)
                        Text(entry?.gloss ?? "").font(.geist(21, .medium)).foregroundStyle(Color.ink).multilineTextAlignment(.center)
                    }
                    if let translation = card.sentenceTranslation {
                        Text(translation.contains("\"") || translation.contains("“") ? translation : "“\(translation)”")
                            .font(.body15)
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 24)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: 560, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.surface))
        .task(id: card.id) {
            guard card.sentenceTranslation == nil else { return }
            card.sentenceTranslation = try? await TranslationService.shared.translate(card.sentenceText)
        }
    }
}

/// A sentence whose words can be tapped for the shared word card; the reviewed word is underlined.
struct TappableSentence: View {
    let text: String
    let highlighted: String?
    let fontSize: CGFloat
    var showsFamiliarity = false
    let onTap: (String) -> Void
    @Environment(WordStateStore.self) private var wordStates

    var body: some View {
        let spans = Segmenter().tokens(in: text)
        FlowLayout(lineSpacing: fontSize * 0.5) {
            ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                let word = span.text(in: text)
                let familiarity = showsFamiliarity && span.isLexical ? wordStates.familiarity(of: word) : .known
                Text(word)
                    .font(.chineseSerif(fontSize))
                    .foregroundStyle(familiarity.isLearning ? Color.learningText : Color.readerText)
                    .background {
                        if familiarity.isLearning { RoundedRectangle(cornerRadius: 3).fill(Color.learning) }
                    }
                    .overlay(alignment: .bottom) {
                        if word == highlighted {
                            Rectangle().fill(Color.ink).frame(height: 1.5).offset(y: 4)
                        } else if familiarity == .new {
                            DottedUnderline()
                                .stroke(Color.newWord, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [0.1, 3]))
                                .frame(height: 1.2)
                                .offset(y: 3)
                        }
                    }
                    .layoutValue(key: FlowLayout.KeepsWithPrevious.self, value: !span.isLexical)
                    .onTapGesture { if span.isLexical { onTap(word) } }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct RatingControl: View {
    let intervals: [Rating: String]
    let onRate: (Rating) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Rating.allCases, id: \.self) { rating in
                Button { onRate(rating) } label: {
                    VStack(spacing: 2) {
                        Text(rating.label).font(.geist(16, .medium)).foregroundStyle(Color.ink)
                        Text(intervals[rating] ?? "").font(.meta12).foregroundStyle(Color.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(rating.label), next in \(intervals[rating] ?? "")")
                if rating != .easy {
                    Rectangle().fill(Color.hairline).frame(width: 1, height: 60)
                }
            }
        }
        .background(Capsule().fill(Color.background))
        .overlay(Capsule().strokeBorder(Color.hairline))
        .clipShape(Capsule())
    }
}
