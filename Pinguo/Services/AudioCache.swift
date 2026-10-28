import CryptoKit
import Foundation

/// A spoken chunk: the audio file plus when each of its sentences starts.
nonisolated struct NarrationClip: Codable, Sendable {
    let fileName: String
    let sentenceStarts: [Double]
    let duration: Double

    var fileURL: URL { AudioCache.directory.appending(path: fileName) }
}

/// Local-only audio cache keyed by (text, voice, model), so re-listening never costs credits.
actor AudioCache {
    static let shared = AudioCache()
    nonisolated static let directory: URL = {
        let url = URL.cachesDirectory.appending(path: "Narration", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private let client = ElevenLabsClient()
    private var inFlight: [String: Task<NarrationClip, Error>] = [:]

    nonisolated static func key(text: String, voiceID: String, modelID: String) -> String {
        let digest = SHA256.hash(data: Data("\(modelID)|\(voiceID)|\(text)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func cachedClip(sentences: [String], voiceID: String, modelID: String) -> NarrationClip? {
        let key = Self.key(text: sentences.joined(), voiceID: voiceID, modelID: modelID)
        return Self.readManifest(key)
    }

    /// Returns the clip for these consecutive sentences, synthesising it once if needed. Without a usable
    /// connection (or an ElevenLabs key) it falls back to the on-device voice, cached separately so the
    /// ElevenLabs version is still fetched once back online.
    func clip(sentences: [String], voiceID: String, modelID: String) async throws -> NarrationClip {
        if let cached = cachedClip(sentences: sentences, voiceID: voiceID, modelID: modelID) { return cached }
        guard CloudReachability.shouldTryCloud else { return try await OnDeviceSpeech.shared.clip(sentences: sentences) }
        do {
            return try await cloudClip(sentences: sentences, voiceID: voiceID, modelID: modelID)
        } catch let error as ServiceError {
            guard case .missingKey = error else { throw error }
            return try await OnDeviceSpeech.shared.clip(sentences: sentences)
        } catch where CloudReachability.isOffline(error) {
            return try await OnDeviceSpeech.shared.clip(sentences: sentences)
        }
    }

    /// Fetches the ElevenLabs clip without falling back, for downloading audio ahead of a flight.
    func cloudClip(sentences: [String], voiceID: String, modelID: String) async throws -> NarrationClip {
        let text = sentences.joined()
        let key = Self.key(text: text, voiceID: voiceID, modelID: modelID)
        if let cached = Self.readManifest(key) { return cached }
        if let running = inFlight[key] { return try await running.value }

        let client = client
        let task = Task<NarrationClip, Error> {
            let (audio, alignment) = try await client.speech(text: text, voiceID: voiceID, modelID: modelID)
            let fileName = "\(key).mp3"
            try audio.write(to: Self.directory.appending(path: fileName), options: .atomic)
            let clip = NarrationClip(
                fileName: fileName,
                sentenceStarts: Self.sentenceStarts(sentences: sentences, alignment: alignment),
                duration: alignment.ends.last ?? 0
            )
            try JSONEncoder().encode(clip).write(to: Self.directory.appending(path: "\(key).json"), options: .atomic)
            return clip
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
    }

    /// Maps sentence boundaries onto the character timings returned with the audio.
    nonisolated static func sentenceStarts(sentences: [String], alignment: CharacterAlignment) -> [Double] {
        var starts: [Double] = []
        var characterOffset = 0
        for sentence in sentences {
            let index = min(characterOffset, max(0, alignment.starts.count - 1))
            starts.append(alignment.starts.isEmpty ? 0 : alignment.starts[index])
            characterOffset += sentence.count
        }
        return starts
    }

    nonisolated static func readManifest(_ key: String) -> NarrationClip? {
        let manifest = directory.appending(path: "\(key).json")
        guard let data = try? Data(contentsOf: manifest),
              let clip = try? JSONDecoder().decode(NarrationClip.self, from: data),
              FileManager.default.fileExists(atPath: clip.fileURL.path) else { return nil }
        return clip
    }

    nonisolated static var totalSize: Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    nonisolated static func clear() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

nonisolated struct NarrationChunk: Hashable, Sendable {
    let sentenceRange: Range<Int>
    let characterCount: Int
}

nonisolated enum NarrationPlanner {
    static let secondsPerCharacter = 0.24

    /// Groups consecutive sentences into chunks of a few sentences (≈ `targetCharacters`) for synthesis.
    static func chunks(for sentences: [String], targetCharacters: Int = 160, maxSentences: Int = 4) -> [NarrationChunk] {
        var chunks: [NarrationChunk] = []
        var start = 0
        while start < sentences.count {
            var end = start
            var characters = 0
            while end < sentences.count, end - start < maxSentences, characters == 0 || characters + sentences[end].count <= targetCharacters {
                characters += sentences[end].count
                end += 1
            }
            chunks.append(NarrationChunk(sentenceRange: start..<end, characterCount: characters))
            start = end
        }
        return chunks
    }
}
