import SwiftUI

/// The shared word lookup card: Reader, Review and Speak all show words through this view.
struct WordCardView<PrimaryAction: View>: View {
    let word: String
    let sentence: String?
    let sentenceContext: String
    var onSpeak: (String) -> Void = { SpeechFallback.shared.speak($0) }
    var showsChrome = true
    @ViewBuilder var primaryAction: PrimaryAction

    @Environment(WordStateStore.self) private var wordStates
    @State private var translation: String?
    @State private var isTranslating = false
    @State private var translationError: String?

    private var entry: DictionaryEntry? { ChineseDictionary.shared.lookup(word) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                Text(word)
                    .font(.chineseSerif(40))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let pinyin = entry?.pinyin {
                    Text(pinyin).font(.geist(17)).foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 8)
                CircleIconButton(systemName: "speaker.wave.2") { onSpeak(word) }
                    .accessibilityLabel("Play pronunciation")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry?.gloss ?? "Not in the dictionary")
                    .font(.body17)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !metaLine.isEmpty {
                    Text(metaLine).font(.meta13).foregroundStyle(Color.inkSecondary)
                }
            }

            FamiliarityBar(familiarity: wordStates.familiarity(of: word)) { level in
                wordStates.setFamiliarity(level, for: word)
            }

            if let translation {
                Text(translation)
                    .font(.body15)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            } else if let translationError {
                Text(translationError).font(.meta13).foregroundStyle(Color.newWord)
            }

            HStack(spacing: 12) {
                primaryAction
                    .frame(maxWidth: .infinity)
                if sentence != nil {
                    Button(action: translate) {
                        Group {
                            if isTranslating {
                                ProgressView()
                            } else {
                                Image(systemName: "translate").font(.system(size: 17, weight: .light))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .foregroundStyle(Color.ink)
                        .overlay(Circle().strokeBorder(Color.hairline))
                        .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Translate sentence")
                }
            }
        }
        .padding(showsChrome ? 20 : 0)
        .background {
            if showsChrome { RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.background) }
        }
        .overlay {
            if showsChrome { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hairline) }
        }
        .shadow(color: .black.opacity(showsChrome ? 0.08 : 0), radius: 24, y: 8)
        .onChange(of: word) {
            translation = nil
            translationError = nil
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if let partOfSpeech = entry?.partOfSpeech?.split(separator: ",").first {
            parts.append(String(partOfSpeech))
        }
        if let level = entry?.hskLevel { parts.append("HSK \(level)") }
        let breakdown = ChineseDictionary.shared.characterBreakdown(of: word)
            .filter { !$0.gloss.isEmpty }
            .map { "\($0.character) \($0.gloss)" }
        if breakdown.count == word.count, !breakdown.isEmpty {
            parts.append(breakdown.joined(separator: " + "))
        }
        return parts.joined(separator: " · ")
    }

    private func translate() {
        guard let sentence, !isTranslating else { return }
        isTranslating = true
        translationError = nil
        Task {
            do {
                let result = try await TranslationService.shared.translate(sentence, context: sentenceContext)
                withAnimation { translation = result }
            } catch {
                translationError = error.localizedDescription
            }
            isTranslating = false
        }
    }
}

/// "Add to review" on the word card; once added it shows the word is in the deck.
struct ReviewToggleButton: View {
    let word: String
    let onAdd: () -> Void
    @Environment(ReviewStore.self) private var reviews

    var body: some View {
        if reviews.hasCard(for: word) {
            Label("In review", systemImage: "checkmark")
                .font(.geist(16, .medium))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(Color.inkSecondary)
                .background(Capsule().fill(Color.surface))
        } else {
            Button(action: onAdd) {
                Text("Add to review").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
        }
    }
}
