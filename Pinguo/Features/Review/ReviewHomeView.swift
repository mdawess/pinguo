import SwiftData
import SwiftUI

struct ReviewHomeView: View {
    @Environment(ReviewStore.self) private var reviews
    @Query(sort: \Card.createdAt, order: .reverse) private var cards: [Card]
    @State private var showsSession = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Review").font(.largeTitle30)
                        Text(subtitle).font(.body15).foregroundStyle(Color.inkSecondary)
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(reviews.dueCount)").font(.geist(56, .semibold)).monospacedDigit()
                            Text(reviews.dueCount == 1 ? "card due" : "cards due").font(.body17).foregroundStyle(Color.inkSecondary)
                        }
                        Button {
                            showsSession = true
                        } label: {
                            Text(reviews.dueCount == 0 ? "All caught up" : "Start review").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PillButtonStyle(height: 52))
                        .disabled(reviews.dueCount == 0)
                    }
                    .padding(24)
                    .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.surface))

                    if !cards.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Recently added").padding(.bottom, 8)
                            ForEach(cards.prefix(30)) { card in
                                CardRow(card: card)
                                    .contextMenu {
                                        Button(role: .destructive) { reviews.delete(card) } label: {
                                            Label("Delete card", systemImage: "trash")
                                        }
                                    }
                                if card.id != cards.prefix(30).last?.id { Hairline() }
                            }
                        }
                    } else {
                        Text("Tap words while you read and add them to review. Each card keeps the sentence you found it in.")
                            .font(.body15)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(Color.background)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { reviews.refresh() }
            .fullScreenCover(isPresented: $showsSession, onDismiss: { reviews.refresh() }) {
                ReviewSessionView()
            }
        }
    }

    private var subtitle: String {
        "\(cards.count) \(cards.count == 1 ? "card" : "cards") · \(cards.filter { $0.state == .review }.count) in long-term review"
    }
}

struct CardRow: View {
    let card: Card

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(card.word)
                .font(.chineseSerif(card.kind == .word ? 20 : 16))
                .lineLimit(1)
            if card.kind == .word, let entry = ChineseDictionary.shared.lookup(card.word) {
                Text(entry.shortGloss).font(.meta13).foregroundStyle(Color.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(dueLabel).font(.meta12).foregroundStyle(Color.inkSecondary)
        }
        .padding(.vertical, 10)
    }

    private var dueLabel: String {
        if card.state == .new { return "New" }
        return card.due <= .now ? "Due" : "in " + IntervalFormatter.label(from: .now, to: card.due)
    }
}
