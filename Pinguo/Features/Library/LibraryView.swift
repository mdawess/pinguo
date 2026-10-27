import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query(sort: \Document.importedAt, order: .reverse) private var documents: [Document]
    @Environment(\.modelContext) private var modelContext
    @Environment(WordStateStore.self) private var wordStates
    @Environment(ReviewStore.self) private var reviews
    @State private var path = NavigationPath()
    @State private var showsAddSheet = false
    @State private var searchText = ""
    @State private var isSearching = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        header
                        if documents.isEmpty {
                            emptyState
                        } else if !searchText.isEmpty {
                            searchResults
                        } else {
                            if let current = continueDocument {
                                ContinueCard(document: current) { path.append(current) }
                            }
                            importingRows
                            if !books.isEmpty { bookShelf }
                            if !otherItems.isEmpty { articlesAndAudio }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
                .background(Color.background)

                Button { showsAddSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color.inkInverse)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.ink))
                        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                }
                .accessibilityLabel("Add to library")
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Document.self) { document in
                if document.kind == .translatedAudio {
                    TranslatedAudioView(document: document)
                } else {
                    ReaderView(document: document)
                }
            }
            .sheet(isPresented: $showsAddSheet) {
                AddToLibrarySheet()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Library").font(.largeTitle30)
                Spacer()
                Button {
                    withAnimation { isSearching.toggle() }
                    if !isSearching { searchText = "" }
                } label: {
                    Image(systemName: isSearching ? "xmark" : "magnifyingglass")
                        .font(.system(size: 19, weight: .light))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSearching ? "Close search" : "Search")
            }
            Text(summaryLine).font(.body15).foregroundStyle(Color.inkSecondary)
            if isSearching {
                TextField("Search titles", text: $searchText)
                    .font(.body17)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.surface))
                    .padding(.top, 10)
            }
        }
        .padding(.top, 12)
    }

    var summaryLine: String {
        let known = "\(wordStates.knownWordCount.formatted()) words known"
        return reviews.dueCount > 0 ? "\(reviews.dueCount) cards due · \(known)" : known
    }

    private var readyDocuments: [Document] { documents.filter { $0.status == .ready } }

    private var continueDocument: Document? {
        readyDocuments.filter { $0.lastOpenedAt != nil }.max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    private var books: [Document] { readyDocuments.filter { $0.kind.isShelfItem } }
    private var otherItems: [Document] { readyDocuments.filter { !$0.kind.isShelfItem } }

    private var importingRows: some View {
        ForEach(documents.filter { $0.status != .ready }) { document in
            ImportingRow(document: document) { modelContext.delete(document) }
        }
    }

    private var bookShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Books") {
                if books.count > 3 {
                    NavigationLink("See all") { AllBooksView(books: books) }
                        .font(.body15)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), alignment: .leading, spacing: 20) {
                ForEach(books.prefix(6)) { book in
                    NavigationLink(value: book) { BookTile(document: book) }
                        .buttonStyle(.plain)
                        .contextMenu { deleteButton(book) }
                }
            }
        }
    }

    private var articlesAndAudio: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Articles & audio").padding(.bottom, 8)
            ForEach(otherItems) { item in
                NavigationLink(value: item) { DocumentRow(document: item) }
                    .buttonStyle(.plain)
                    .contextMenu { deleteButton(item) }
                if item.id != otherItems.last?.id { Hairline().padding(.leading, 56) }
            }
        }
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 4) {
            let matches = readyDocuments.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) || ($0.author ?? "").localizedCaseInsensitiveContains(searchText)
            }
            if matches.isEmpty {
                Text("No matches").font(.body15).foregroundStyle(Color.inkSecondary)
            }
            ForEach(matches) { item in
                NavigationLink(value: item) { DocumentRow(document: item) }.buttonStyle(.plain)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nothing to read yet").font(.sectionTitle)
            Text("Add an EPUB, a text file or paste some Chinese. Tap any word while you read to look it up.")
                .font(.body15)
                .foregroundStyle(Color.inkSecondary)
            Button("Add something to read") { showsAddSheet = true }
                .buttonStyle(.pill)
                .padding(.top, 6)
        }
        .padding(.top, 40)
    }

    private func deleteButton(_ document: Document) -> some View {
        Button(role: .destructive) {
            modelContext.delete(document)
            try? modelContext.save()
        } label: {
            Label("Remove from library", systemImage: "trash")
        }
    }
}

struct ContinueCard: View {
    let document: Document
    let onResume: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            CoverView(document: document, width: 104)
            VStack(alignment: .leading, spacing: 0) {
                Text("Continue").font(.body15).foregroundStyle(Color.inkSecondary)
                Text(document.title).font(.chineseSans(22)).lineLimit(2).padding(.top, 6)
                Text(progressLine).font(.body15).foregroundStyle(Color.inkSecondary).padding(.top, 4)
                ProgressLine(value: document.readingProgress).padding(.top, 10)
                Button(action: onResume) {
                    Label("Resume", systemImage: "play.fill").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.pill)
                .padding(.top, 30)
            }
        }
    }

    private var progressLine: String {
        let chapter = document.orderedChapters.first { $0.index == document.lastChapterIndex }
        let chapterLabel = chapter.map { "Chapter \($0.index + 1)" } ?? document.kind.label
        return "\(chapterLabel) · \(document.estimatedMinutesLeft) min left"
    }
}

struct BookTile: View {
    let document: Document

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverView(document: document)
                .padding(.bottom, 8)
            Text(document.title).font(.chineseSans(15)).lineLimit(1).foregroundStyle(Color.ink)
            Text(detail).font(.meta13).foregroundStyle(Color.inkSecondary)
        }
    }

    private var detail: String {
        let progress = document.lastOpenedAt == nil ? "New" : "\(Int((document.readingProgress * 100).rounded()))%"
        return document.kind == .pdf ? "PDF · \(progress)" : progress
    }
}

struct DocumentRow: View {
    let document: Document
    @Environment(WordStateStore.self) private var wordStates

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemName: icon)
            VStack(alignment: .leading, spacing: 3) {
                Text(document.title).font(.chineseSans(17)).lineLimit(1).foregroundStyle(Color.ink)
                Text(detail).font(.meta13).foregroundStyle(Color.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var icon: String {
        switch document.kind {
        case .article: "link"
        case .translatedAudio: "headphones"
        case .pdf: "doc.richtext"
        case .epub: "book.closed"
        case .text: "text.alignleft"
        }
    }

    private var detail: String {
        let minutes = max(1, document.totalCharacters / 260)
        let share = Int((wordStates.newWordShare(of: document.uniqueWords) * 100).rounded())
        if document.kind == .translatedAudio, let duration = document.durationSeconds {
            return "\(document.kind.label) · \(Int(duration / 60)) min"
        }
        return "\(document.kind.label) · \(minutes) min · \(share)% new words"
    }
}

struct ImportingRow: View {
    let document: Document
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            IconTile(systemName: document.status == .failed ? "exclamationmark.triangle" : "arrow.down.doc")
            VStack(alignment: .leading, spacing: 6) {
                Text(document.title.isEmpty ? "Importing…" : document.title).font(.body15).lineLimit(1)
                if document.status == .failed {
                    Text(document.importError ?? "Import failed").font(.meta13).foregroundStyle(Color.newWord).lineLimit(2)
                } else {
                    ProgressLine(value: document.importProgress, height: 3)
                }
            }
            if document.status == .failed {
                Button("Remove", action: onRemove).font(.meta13).foregroundStyle(Color.inkSecondary)
            }
        }
    }
}

struct AllBooksView: View {
    let books: [Document]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 24) {
                ForEach(books) { book in
                    NavigationLink(value: book) { BookTile(document: book) }.buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(Color.background)
        .navigationTitle("Books")
    }
}
