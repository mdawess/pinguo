import SwiftData
import SwiftUI

struct SpeakHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Conversation.startedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \Document.lastOpenedAt, order: .reverse) private var documents: [Document]
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Speak").font(.largeTitle30)
                        Text("Practise out loud with a patient tutor · HSK \(settings.estimatedHSKLevel)")
                            .font(.body15)
                            .foregroundStyle(Color.inkSecondary)
                    }
                    .padding(.top, 12)

                    VStack(spacing: 4) {
                        if let reading = readingScenario {
                            scenarioRow(reading)
                            Hairline().padding(.leading, 58)
                        }
                        ForEach(Scenario.presets) { scenario in
                            scenarioRow(scenario)
                            if scenario.id != Scenario.presets.last?.id { Hairline().padding(.leading, 58) }
                        }
                    }

                    if !conversations.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader(title: "Recent").padding(.bottom, 8)
                            ForEach(conversations.prefix(8)) { conversation in
                                Button {
                                    path.append(ConversationRoute(conversation: conversation, scenario: scenario(for: conversation)))
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(conversation.title).font(.body15).foregroundStyle(Color.ink)
                                            Text(conversation.startedAt.formatted(.relative(presentation: .named)))
                                                .font(.meta12)
                                                .foregroundStyle(Color.inkSecondary)
                                        }
                                        Spacer()
                                        Text("\(conversation.messages?.count ?? 0) messages").font(.meta12).foregroundStyle(Color.inkSecondary)
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { modelContext.delete(conversation) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(Color.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ConversationRoute.self) { route in
                ConversationView(conversation: route.conversation, scenario: route.scenario)
            }
        }
    }

    private var readingDocument: Document? {
        documents.first { $0.lastOpenedAt != nil && $0.status == .ready }
    }

    private var readingScenario: Scenario? {
        guard let document = readingDocument,
              let chapter = document.orderedChapters.first(where: { $0.index == document.lastChapterIndex }) else { return nil }
        let sentences = chapter.orderedSentences
        let end = min(sentences.count, document.lastSentenceIndex + 1)
        let excerpt = sentences[max(0, end - 12)..<end].map(\.text).joined()
        return Scenario.reading(title: document.title, excerpt: excerpt)
    }

    private func scenario(for conversation: Conversation) -> Scenario {
        Scenario.presets.first { $0.id == conversation.scenarioID } ?? readingScenario ?? Scenario.presets.last!
    }

    private func scenarioRow(_ scenario: Scenario) -> some View {
        Button {
            let conversation = Conversation(scenarioID: scenario.id, title: scenario.title, hskLevel: settings.estimatedHSKLevel)
            modelContext.insert(conversation)
            path.append(ConversationRoute(conversation: conversation, scenario: scenario))
        } label: {
            HStack(spacing: 14) {
                IconTile(systemName: scenario.icon, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scenario.title).font(.geist(16, .medium)).foregroundStyle(Color.ink).lineLimit(1)
                    Text(scenario.chineseTitle).font(.chineseSans(13)).foregroundStyle(Color.inkSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundStyle(Color.inkSecondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ConversationRoute: Hashable {
    let conversation: Conversation
    let scenario: Scenario

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.conversation.id == rhs.conversation.id }
    func hash(into hasher: inout Hasher) { hasher.combine(conversation.id) }
}
