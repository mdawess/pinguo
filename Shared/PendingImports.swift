import Foundation

/// Items handed from the share extension to the app through the shared App Group container.
nonisolated struct PendingImport: Codable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case url, text, file
    }

    var id = UUID()
    let kind: Kind
    let value: String
    var title: String?
    var createdAt = Date()
}

nonisolated enum PendingImports {
    static let appGroup = "group.com.mdawes.pinguo"

    static var directory: URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let url = container.appending(path: "PendingImports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func enqueue(_ item: PendingImport) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try JSONEncoder().encode(item).write(to: directory.appending(path: "\(item.id.uuidString).json"), options: .atomic)
    }

    /// Copies a shared file into the container and queues it; returns the queued item.
    static func enqueueFile(at url: URL) throws -> PendingImport {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        let name = "\(UUID().uuidString)-\(url.lastPathComponent)"
        try FileManager.default.copyItem(at: url, to: directory.appending(path: name))
        let item = PendingImport(kind: .file, value: name, title: url.deletingPathExtension().lastPathComponent)
        try enqueue(item)
        return item
    }

    static func fileURL(for item: PendingImport) -> URL? {
        directory?.appending(path: item.value)
    }

    /// Returns queued items oldest first and removes their manifests.
    static func drain() -> [PendingImport] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        let items = files.filter { $0.pathExtension == "json" }.compactMap { url -> PendingImport? in
            defer { try? FileManager.default.removeItem(at: url) }
            return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(PendingImport.self, from: $0) }
        }
        return items.sorted { $0.createdAt < $1.createdAt }
    }
}
