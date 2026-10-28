import AVFoundation
import Foundation
import FoundationModels
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
        lines(from: try await onDeviceWords(url))
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
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            throw AudioTranslationError.recognizerUnavailable
        }
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

    @Generable
    struct AdaptedBatch {
        @Guide(description: "One Simplified Chinese line per numbered English line, in the same order, without numbers.")
        var lines: [String]
    }

    /// Apple Translation gives natural Mandarin; when adapting to a level, the on-device model rewrites it
    /// in simpler words (falling back to the plain translation if Apple Intelligence is unavailable).
    static func translate(_ lines: [TranscriptLine], adaptToHSK level: Int?) async throws -> [TranslatedLine] {
        var chinese = try await AppleTranslator.englishToChinese.translate(lines.map(\.english))
        if let level, TutorService.unavailableReason == nil {
            for start in stride(from: 0, to: lines.count, by: 8) {
                let range = start..<min(lines.count, start + 8)
                if let adapted = try? await adapt(Array(lines[range]), level: level), adapted.count == range.count {
                    chinese.replaceSubrange(range, with: adapted)
                }
            }
        }
        return zip(lines, chinese).map { line, text in
            TranslatedLine(chinese: text.isEmpty ? line.english : text, english: line.english, start: line.start, end: line.end)
        }
    }

    private static func adapt(_ lines: [TranscriptLine], level: Int) async throws -> [String] {
        let session = LanguageModelSession(instructions: """
            You translate spoken English into Simplified Chinese for a Mandarin learner at HSK \(level).
            Prefer common words and simple structures while keeping the meaning. Spoken register, Chinese punctuation.
            """)
        let numbered = lines.enumerated().map { "\($0.offset + 1). \($0.element.english)" }.joined(separator: "\n")
        let batch = try await session.respond(to: "Translate each of these \(lines.count) lines:\n\(numbered)", generating: AdaptedBatch.self).content
        return batch.lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
