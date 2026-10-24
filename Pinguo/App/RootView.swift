import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case library, review, speak, progress
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .library
    @State private var wordStates: WordStateStore?
    @State private var settings: AppSettings?
    @State private var player = NarrationPlayer()
    @State private var reviews: ReviewStore?

    var body: some View {
        Group {
            if let wordStates, let settings, let reviews {
                tabs
                    .environment(wordStates)
                    .environment(reviews)
                    .environment(settings)
                    .environment(player)
            } else {
                Color.background.ignoresSafeArea()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { importSharedItems() }
        }
        .onChange(of: player.speed) { _, speed in settings?.playbackSpeed = speed }
        .onOpenURL { url in
            importOpenedFile(url)
        }
        .task {
            guard wordStates == nil else { return }
            settings = AppSettings.current(in: modelContext)
            let wordStates = WordStateStore(context: modelContext)
            self.wordStates = wordStates
            reviews = ReviewStore(context: modelContext, wordStates: wordStates)
            player.speed = settings?.playbackSpeed ?? 1
            #if DEBUG
            importLaunchArgumentFile()
            #endif
            importSharedItems()
            Task.detached(priority: .utility) { _ = ChineseDictionary.shared.headwords }
        }
    }

    private func importOpenedFile(_ url: URL) {
        guard url.isFileURL, let local = try? ImportCoordinator.copyToTemporaryLocation(url) else { return }
        let extensionName = url.pathExtension.lowercased()
        if ["m4a", "mp3", "wav", "aiff", "caf"].contains(extensionName) {
            ImportCoordinator.start(
                .englishAudio(local, adaptToHSK: settings?.estimatedHSKLevel),
                title: url.deletingPathExtension().lastPathComponent,
                kind: .translatedAudio,
                in: modelContext
            )
            selectedTab = .library
            return
        }
        let source: ImportSource = switch extensionName {
        case "epub": .epub(local)
        case "pdf": .pdf(local)
        default: .textFile(local)
        }
        ImportCoordinator.start(
            source,
            title: url.deletingPathExtension().lastPathComponent,
            kind: extensionName == "pdf" ? .pdf : .epub,
            makesCardsFromTaps: settings?.makeCardsFromTapsByDefault ?? true,
            pregeneratingAudioWith: settings.flatMap { $0.pregenerateAudioByDefault ? ($0.resolvedVoiceID, $0.voiceModelID) : nil },
            in: modelContext
        )
        selectedTab = .library
    }

    /// Picks up links, text and files sent from the share extension.
    private func importSharedItems() {
        guard let settings else { return }
        let items = PendingImports.drain()
        guard !items.isEmpty else { return }
        for item in items {
            switch item.kind {
            case .url:
                ImportCoordinator.start(
                    .article(item.value),
                    title: item.title ?? item.value,
                    kind: .article,
                    sourceURL: item.value,
                    makesCardsFromTaps: settings.makeCardsFromTapsByDefault,
                    in: modelContext
                )
            case .text:
                ImportCoordinator.start(
                    .pastedText(title: "", text: item.value),
                    title: DocumentImporter.defaultTitle(for: item.value),
                    kind: .text,
                    makesCardsFromTaps: settings.makeCardsFromTapsByDefault,
                    in: modelContext
                )
            case .file:
                if let url = PendingImports.fileURL(for: item) {
                    importOpenedFile(url)
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        selectedTab = .library
    }

    #if DEBUG
    /// UI tests pass `-PinguoImport <path>` to load a fixture without the document picker.
    private func importLaunchArgumentFile() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-PinguoImport"), arguments.indices.contains(flag + 1) else { return }
        importOpenedFile(URL(fileURLWithPath: arguments[flag + 1]))
    }
    #endif

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                LibraryView()
            }
            Tab("Review", systemImage: "rectangle.on.rectangle", value: AppTab.review) {
                ReviewHomeView()
            }
            .badge(reviews?.dueCount ?? 0)
            Tab("Speak", systemImage: "bubble", value: AppTab.speak) {
                SpeakHomeView()
            }
            Tab("Progress", systemImage: "person", value: AppTab.progress) {
                NavigationStack {
                    if let settings { SettingsView(settings: settings) }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .task {
            // Learning steps fall due within minutes, so keep the badge current.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                reviews?.refresh()
            }
        }
    }
}

struct PlaceholderScreen: View {
    let title: String

    var body: some View {
        NavigationStack {
            Color.background
                .ignoresSafeArea()
                .navigationTitle(title)
        }
    }
}
