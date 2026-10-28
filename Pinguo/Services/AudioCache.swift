import AVFoundation
import CryptoKit
import Foundation

/// A spoken chunk: the audio file plus when each of its sentences starts.
nonisolated struct NarrationClip: Codable, Sendable {
    let fileName: String
    let sentenceStarts: [Double]
    let duration: Double

    var fileURL: URL { AudioCache.directory.appending(path: fileName) }
}

/// Narration rendered with an on-device voice and cached by (text, voice), so chapters render once.
actor AudioCache {
    static let shared = AudioCache()
    nonisolated static let directory: URL = {
        let url = URL.cachesDirectory.appending(path: "Narration", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private var inFlight: [String: Task<NarrationClip, Error>] = [:]

    nonisolated static func key(text: String, voiceID: String) -> String {
        let digest = SHA256.hash(data: Data("\(voiceID)|\(text)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the clip for these consecutive sentences, rendering it once if needed.
    func clip(sentences: [String], voiceID: String?) async throws -> NarrationClip {
        let voice = ChineseVoices.voice(withID: voiceID)
        let key = Self.key(text: sentences.joined(), voiceID: voice?.identifier ?? "zh-CN")
        if let cached = Self.readManifest(key) { return cached }
        if let running = inFlight[key] { return try await running.value }

        let task = Task<NarrationClip, Error> {
            let (buffers, sentenceStarts) = try await SpeechSynthesis.shared.render(sentences, voice: voice)
            let format = buffers[0].format
            let fileName = "\(key).caf"
            let file = try AVAudioFile(
                forWriting: Self.directory.appending(path: fileName),
                settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount],
                commonFormat: format.commonFormat,
                interleaved: format.isInterleaved
            )
            for buffer in buffers { try file.write(from: buffer) }
            let frames = buffers.reduce(0) { $0 + Double($1.frameLength) }
            let clip = NarrationClip(fileName: fileName, sentenceStarts: sentenceStarts, duration: frames / format.sampleRate)
            try JSONEncoder().encode(clip).write(to: Self.directory.appending(path: "\(key).json"), options: .atomic)
            return clip
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        return try await task.value
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
