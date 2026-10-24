import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

@Observable
final class ShareModel {
    enum Phase { case loading, ready(PendingImport), saved, failed(String) }

    private let context: NSExtensionContext?
    var phase: Phase = .loading

    init(context: NSExtensionContext?) {
        self.context = context
    }

    func load() async {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        do {
            if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }),
               let url = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                phase = .ready(PendingImport(kind: .file, value: url.path, title: url.deletingPathExtension().lastPathComponent))
            } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }),
                      let url = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                phase = .ready(PendingImport(kind: .url, value: url.absoluteString, title: url.host))
            } else if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }),
                      let text = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.hasPrefix("http") == true {
                    phase = .ready(PendingImport(kind: .url, value: url.absoluteString, title: url.host))
                } else {
                    phase = .ready(PendingImport(kind: .text, value: text, title: String(text.prefix(16))))
                }
            } else {
                phase = .failed("Pinguo can import links, text, EPUB, PDF and TXT files.")
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func save() {
        guard case .ready(let item) = phase else { return }
        do {
            if item.kind == .file {
                _ = try PendingImports.enqueueFile(at: URL(fileURLWithPath: item.value))
            } else {
                try PendingImports.enqueue(item)
            }
            phase = .saved
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                context?.completeRequest(returningItems: nil)
            }
        } catch {
            phase = .failed("Couldn't hand this to Pinguo: \(error.localizedDescription)")
        }
    }

    func cancel() {
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }
}

struct ShareView: View {
    let model: ShareModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add to Pinguo").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Cancel", action: model.cancel).foregroundStyle(.secondary)
            }
            switch model.phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .ready(let item):
                Text(item.title ?? item.value)
                    .font(.system(size: 17))
                    .lineLimit(3)
                Text(item.kind == .url ? "Article · opens in your Library" : "Imported into your Library")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Button(action: model.save) {
                    Text("Add to library").font(.system(size: 16, weight: .medium)).frame(maxWidth: .infinity, minHeight: 48)
                }
                .foregroundStyle(Color(uiColor: .systemBackground))
                .background(Capsule().fill(Color.primary))
            case .saved:
                Label("Added. Open Pinguo to read it.", systemImage: "checkmark")
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(uiColor: .systemBackground)))
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }
}
