import SwiftUI

/// Long-press on a sentence: translate it, replay it, or keep it as a card.
struct SentenceCardView<Actions: View>: View {
    let sentence: ReaderSentence
    let onClose: () -> Void
    @ViewBuilder var actions: Actions

    @State private var translation: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(sentence.text)
                    .font(.chineseSerif(19))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .light)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, -10)
                .padding(.trailing, -10)
            }
            Group {
                if let translation = translation ?? sentence.englishText {
                    Text(translation).foregroundStyle(Color.inkSecondary)
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.newWord)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Translating…").foregroundStyle(Color.inkSecondary)
                    }
                }
            }
            .font(.body15)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) { actions }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.background))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hairline))
        .shadow(color: .black.opacity(0.08), radius: 24, y: 8)
        .task(id: sentence.text) {
            guard sentence.englishText == nil else { return }
            translation = nil
            errorMessage = nil
            do {
                translation = try await TranslationService.shared.translate(sentence.text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
