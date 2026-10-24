import SwiftUI

enum AppTab: Hashable {
    case library, review, speak, progress
}

struct RootView: View {
    @State private var selectedTab: AppTab = .library

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                PlaceholderScreen(title: "Library")
            }
            Tab("Review", systemImage: "rectangle.on.rectangle", value: AppTab.review) {
                PlaceholderScreen(title: "Review")
            }
            Tab("Speak", systemImage: "bubble", value: AppTab.speak) {
                PlaceholderScreen(title: "Speak")
            }
            Tab("Progress", systemImage: "person", value: AppTab.progress) {
                PlaceholderScreen(title: "Progress")
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
