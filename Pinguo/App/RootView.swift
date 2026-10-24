import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case library, review, speak, progress
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: AppTab = .library
    @State private var wordStates: WordStateStore?
    @State private var settings: AppSettings?

    var body: some View {
        Group {
            if let wordStates, let settings {
                tabs
                    .environment(wordStates)
                    .environment(settings)
            } else {
                Color.background.ignoresSafeArea()
            }
        }
        .onOpenURL { url in
            importOpenedFile(url)
        }
        .task {
            guard wordStates == nil else { return }
            settings = AppSettings.current(in: modelContext)
            wordStates = WordStateStore(context: modelContext)
            #if DEBUG
            importLaunchArgumentFile()
            #endif
            Task.detached(priority: .utility) { _ = ChineseDictionary.shared.headwords }
        }
    }

    private func importOpenedFile(_ url: URL) {
        guard url.isFileURL, let local = try? ImportCoordinator.copyToTemporaryLocation(url) else { return }
        let isEPUB = url.pathExtension.lowercased() == "epub"
        ImportCoordinator.start(
            isEPUB ? .epub(local) : .textFile(local),
            title: url.deletingPathExtension().lastPathComponent,
            kind: .epub,
            makesCardsFromTaps: settings?.makeCardsFromTapsByDefault ?? true,
            in: modelContext
        )
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
                PlaceholderScreen(title: "Review")
            }
            Tab("Speak", systemImage: "bubble", value: AppTab.speak) {
                PlaceholderScreen(title: "Speak")
            }
            Tab("Progress", systemImage: "person", value: AppTab.progress) {
                NavigationStack {
                    if let settings { SettingsView(settings: settings) }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
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
