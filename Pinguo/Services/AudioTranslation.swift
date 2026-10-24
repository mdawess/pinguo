import AVFoundation
import Foundation
@preconcurrency import Speech

nonisolated struct TimedWord: Sendable {
    let text: String
    let start: Double
    let end: Double
}

nonisolated struct TranscriptLine: Sendable, Equatable {
    let english: String
    let start: Double
    let end: Double
}

nonisolated struct TranslatedLine: Sendable {
    let chinese: String
    let english: String
    let start: Double
    let end: Double
}

/// English speech → timed transcript lines → natural Mandarin, line by line.
nonisolated enum AudioTranslation {
    static func transcribe(_ url: URL) async throws -> [TranscriptLine] {
        var words = (try? await onDeviceWords(url)) ?? []
        if words.isEmpty {
            words = try await ElevenLabsClient().transcribe(fileURL: url, languageCode: "eng").words.map {
                TimedWord(text: $0.text, start: $0.start, end: $0.end)
            }
        }
        return lines(from: words)
    }

    /// Groups words into sentence lines, breaking after . ? ! or when a line runs long.
    static func lines(from words: [TimedWord], maxWords: Int = 28) -> [TranscriptLine] {
        var lines: [TranscriptLine] = []
        var current: [TimedWord] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ")
                .replacingOccurrences(of: " ,", with: ",")
                .trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { lines.append(TranscriptLine(english: text, start: first.start, end: last.end)) }
            current = []
        }
        for word in words where !word.text.trimmingCharacters(in: .whitespaces).isEmpty {
            current.append(TimedWord(text: word.text.trimmingCharacters(in: .whitespaces), start: word.start, end: word.end))
            let endsSentence = word.text.trimmingCharacters(in: .whitespaces).last.map { ".?!".contains($0) } ?? false
            if endsSentence || current.count >= maxWords { flush() }
        }
        flush()
        return lines
    }

    private static func onDeviceWords(_ url: URL) async throws -> [TimedWord] {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else { return [] }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.addsPunctuation = true
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        let transcription: SFTranscription = try await withCheckedThrowingContinuation { continuation in
            let resumed = ResumeOnce()
            recognizer.recognitionTask(with: request) { result, error in
                if let error, resumed.claim() {
                    continuation.resume(throwing: error)
                } else if let result, result.isFinal, resumed.claim() {
                    continuation.resume(returning: result.bestTranscription)
                }
            }
        }
        let segments = transcription.segments
        let punctuated = transcription.formattedString.split(separator: " ").map(String.init)
        // formattedString carries punctuation and segments carry timings; zip them when they line up.
        let texts = punctuated.count == segments.count ? punctuated : segments.map(\.substring)
        return zip(texts, segments).map { TimedWord(text: $0, start: $1.timestamp, end: $1.timestamp + $1.duration) }
    }

    static let translationSchema: [String: Any] = [
        "type": "object",
        "properties": [
            "lines": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": ["index": ["type": "integer"], "chinese": ["type": "string"]],
                    "required": ["index", "chinese"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["lines"],
        "additionalProperties": false,
    ]

    private struct TranslationBatch: Decodable {
        struct Line: Decodable {
            let index: Int
            let chinese: String
        }

        let lines: [Line]
    }

    static func translate(_ lines: [TranscriptLine], adaptToHSK level: Int?) async throws -> [TranslatedLine] {
        let client = ClaudeClient()
        var result: [TranslatedLine] = []
        let levelInstruction = level.map { "Adapt the Chinese for a learner at HSK \($0): prefer common words and simple structures while keeping the meaning." }
            ?? "Use natural, idiomatic Mandarin a native speaker would say."
        let system = """
            You translate an English spoken transcript into Simplified Chinese, line by line, for a Mandarin learner.
            \(levelInstruction)
            Keep one Chinese line per English line with the same index; use context from neighbouring lines. Spoken register, Chinese punctuation.
            """
        for start in stride(from: 0, to: lines.count, by: 40) {
            let batch = Array(lines[start..<min(lines.count, start + 40)])
            let numbered = batch.enumerated().map { "\(start + $0.offset): \($0.element.english)" }.joined(separator: "\n")
            let response = try await client.json(TranslationBatch.self, system: system, messages: [.user(numbered)], schema: translationSchema, effort: .low, maxTokens: 16000)
            let byIndex = Dictionary(response.lines.map { ($0.index, $0.chinese) }, uniquingKeysWith: { first, _ in first })
            for (offset, line) in batch.enumerated() {
                let chinese = byIndex[start + offset] ?? ""
                result.append(TranslatedLine(chinese: chinese.isEmpty ? line.english : chinese, english: line.english, start: line.start, end: line.end))
            }
        }
        return result
    }

    static func duration(of url: URL) -> Double {
        (try? AVAudioPlayer(contentsOf: url))?.duration ?? 0
    }

    static var sourceAudioDirectory: URL {
        let url = URL.documentsDirectory.appending(path: "SourceAudio", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private nonisolated final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return false }
        done = true
        return true
    }
}
