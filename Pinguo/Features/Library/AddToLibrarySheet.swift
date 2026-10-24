import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AddToLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @State private var showsFileImporter = false
    @State private var showsPasteText = false
    @State private var errorMessage: String?
    @State private var articleAddress = ""

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    uploadCard
                    articleCard
                    AddRow(icon: "text.alignleft", title: "Paste text", subtitle: nil) {
                        showsPasteText = true
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.meta13).foregroundStyle(Color.newWord)
                    }
                    VStack(spacing: 0) {
                        Toggle(isOn: $settings.makeCardsFromTapsByDefault) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Make cards from words I tap").font(.body15)
                                Text("With the sentence and audio attached").font(.meta13).foregroundStyle(Color.inkSecondary)
                            }
                        }
                        .padding(.vertical, 12)
                        Hairline()
                        Toggle("Pre-generate audio", isOn: $settings.pregenerateAudioByDefault)
                            .font(.body15)
                            .padding(.vertical, 12)
                    }
                    .tint(Color.ink)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color.background)
            .navigationTitle("Add to library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
            .navigationDestination(isPresented: $showsPasteText) {
                PasteTextView { title, text in
                    ImportCoordinator.start(
                        .pastedText(title: title, text: text),
                        title: title.isEmpty ? DocumentImporter.defaultTitle(for: text) : title,
                        kind: .text,
                        makesCardsFromTaps: settings.makeCardsFromTapsByDefault,
                        pregeneratingAudioWith: pregenerationVoice,
                        in: modelContext
                    )
                    dismiss()
                }
            }
            .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: Self.importableTypes) { result in
                handlePickedFile(result)
            }
        }
    }

    static let importableTypes: [UTType] = [
        UTType(filenameExtension: "epub") ?? .epub,
        .pdf,
        .plainText,
        .utf8PlainText,
    ]

    private var uploadCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .light))
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.background))
            Text("Upload a book or document").font(.geist(17, .medium)).padding(.top, 6)
            Text("EPUB, PDF or TXT · split into chapters automatically")
                .font(.meta13)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Choose file") { showsFileImporter = true }
                .buttonStyle(.pill)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.surface))
    }

    private var articleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import an article").font(.geist(16, .medium))
            HStack(spacing: 10) {
                TextField("Paste a link", text: $articleAddress)
                    .font(.body15)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(importArticle)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.hairline))
                Button("Import", action: importArticle)
                    .buttonStyle(PillButtonStyle(kind: .secondary, height: 44))
                    .disabled(articleAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hairline))
    }

    private func importArticle() {
        let address = articleAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return }
        ImportCoordinator.start(
            .article(address),
            title: URL(string: address)?.host ?? address,
            kind: .article,
            sourceURL: address,
            makesCardsFromTaps: settings.makeCardsFromTapsByDefault,
            pregeneratingAudioWith: pregenerationVoice,
            in: modelContext
        )
        dismiss()
    }

    private var pregenerationVoice: (voiceID: String, modelID: String)? {
        settings.pregenerateAudioByDefault ? (settings.resolvedVoiceID, settings.voiceModelID) : nil
    }

    private func handlePickedFile(_ result: Result<URL, Error>) {
        do {
            let picked = try result.get()
            let local = try ImportCoordinator.copyToTemporaryLocation(picked)
            let title = picked.deletingPathExtension().lastPathComponent
            let source: ImportSource
            let kind: DocumentKind
            switch picked.pathExtension.lowercased() {
            case "epub":
                source = .epub(local)
                kind = .epub
            case "pdf":
                source = .pdf(local)
                kind = .pdf
            default:
                source = .textFile(local)
                kind = .epub
            }
            ImportCoordinator.start(
                source,
                title: title,
                kind: kind,
                makesCardsFromTaps: settings.makeCardsFromTapsByDefault,
                pregeneratingAudioWith: pregenerationVoice,
                in: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AddRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    var iconTint: Color = .surface
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                IconTile(systemName: icon, size: 44, tint: iconTint)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.geist(16, .medium)).foregroundStyle(Color.ink)
                    if let subtitle {
                        Text(subtitle).font(.meta13).foregroundStyle(Color.inkSecondary).multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .light)).foregroundStyle(Color.inkSecondary)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PasteTextView: View {
    let onAdd: (String, String) -> Void
    @State private var title = ""
    @State private var text = ""
    @FocusState private var focusesText: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title (optional)", text: $title)
                .font(.body17)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.hairline))
            TextEditor(text: $text)
                .font(.chineseSerif(19))
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.surface))
                .focused($focusesText)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("粘贴中文文本…").font(.chineseSerif(19)).foregroundStyle(Color.inkSecondary).padding(20).allowsHitTesting(false)
                    }
                }
            Button {
                onAdd(title.trimmingCharacters(in: .whitespaces), text)
            } label: {
                Text("Add to library").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pill)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(Color.background)
        .navigationTitle("Paste text")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusesText = true }
    }
}
