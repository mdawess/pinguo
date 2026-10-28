import SwiftUI

/// "Download for offline" actions for a document, used in the reader toolbar and Library context menus.
struct OfflineDownloadMenuItems: View {
    let document: Document
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let downloads = OfflineDownloads.shared
        if downloads.isDownloading(document) {
            Button(role: .destructive) { downloads.cancel(document) } label: {
                Label("Cancel offline download", systemImage: "xmark.circle")
            }
        } else {
            Section("Download for offline") {
                if document.orderedChapters.count > 3 {
                    downloadButton("Next 3 chapters", scope: .nextChapters(3))
                }
                downloadButton(document.orderedChapters.count > 1 ? "Whole book" : "Everything", scope: .wholeBook)
            }
        }
    }

    private func downloadButton(_ title: String, scope: OfflineScope) -> some View {
        let characters = OfflineDownloads.narrationCharacters(of: document, scope: scope)
        return Button {
            OfflineDownloads.shared.start(document, scope: scope, voiceID: settings.voiceID(for: document), modelID: settings.voiceModelID)
        } label: {
            Label {
                Text(title)
                Text("Translations + ~\(characters.formatted()) characters of narration")
            } icon: {
                Image(systemName: "arrow.down.circle")
            }
        }
    }
}

/// Toolbar icon that shows download progress for the open document.
struct OfflineDownloadButton: View {
    let document: Document

    var body: some View {
        Menu {
            OfflineDownloadMenuItems(document: document)
        } label: {
            OfflineStatusIcon(job: OfflineDownloads.shared.job(for: document))
        }
        .accessibilityLabel("Download for offline")
    }
}

struct OfflineStatusIcon: View {
    let job: OfflineDownloads.Job?

    var body: some View {
        if let job, !job.isFinished {
            ZStack {
                Circle().stroke(Color.hairline, lineWidth: 2)
                Circle().trim(from: 0, to: job.fraction).stroke(Color.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
            }
            .frame(width: 18, height: 18)
        } else if job?.failure != nil {
            Image(systemName: "exclamationmark.icloud")
        } else if job?.isFinished == true {
            Image(systemName: "checkmark.circle")
        } else {
            Image(systemName: "arrow.down.circle")
        }
    }
}

/// One-line status under a Library item while it downloads.
struct OfflineStatusLine: View {
    let document: Document

    var body: some View {
        if let job = OfflineDownloads.shared.job(for: document) {
            Group {
                if let failure = job.failure {
                    Text(failure).foregroundStyle(Color.newWord)
                } else if job.isFinished {
                    Label("Available offline", systemImage: "checkmark.circle")
                } else {
                    Text("Downloading \(Int((job.fraction * 100).rounded()))%")
                }
            }
            .font(.meta12)
            .foregroundStyle(Color.inkSecondary)
            .lineLimit(1)
        }
    }
}
