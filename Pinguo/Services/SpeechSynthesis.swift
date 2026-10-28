import AVFoundation

/// The Mandarin voices installed on this device. Premium and Enhanced voices are downloaded in
/// Settings › Accessibility › Spoken Content › Voices.
nonisolated enum ChineseVoices {
    static var installed: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { ["zh-CN", "zh-TW"].contains($0.language) && !$0.voiceTraits.contains(.isPersonalVoice) }
            .sorted { ($0.language, -$0.quality.rawValue, $0.name) < ($1.language, -$1.quality.rawValue, $1.name) }
    }

    static var best: AVSpeechSynthesisVoice? {
        installed.filter { $0.language == "zh-CN" }.max { $0.quality.rawValue < $1.quality.rawValue } ?? installed.first
    }

    /// The chosen voice if it is still installed, otherwise the best available one.
    static func voice(withID id: String?) -> AVSpeechSynthesisVoice? {
        if let id, let voice = AVSpeechSynthesisVoice(identifier: id), voice.language.hasPrefix("zh") { return voice }
        return best
    }

    static var hasHighQualityVoice: Bool {
        installed.contains { $0.language == "zh-CN" && $0.quality != .default }
    }

    static func qualityLabel(of voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Compact"
        }
    }

    static func accentLabel(of voice: AVSpeechSynthesisVoice) -> String {
        voice.language == "zh-TW" ? "Taiwan" : "Mainland"
    }
}

/// Renders sentences with an installed voice into PCM buffers, noting where each sentence starts.
actor SpeechSynthesis {
    static let shared = SpeechSynthesis()
    nonisolated static let rate = AVSpeechUtteranceDefaultSpeechRate * 0.9

    private let synthesizer = AVSpeechSynthesizer()

    func render(_ sentences: [String], voice: AVSpeechSynthesisVoice?) async throws -> (buffers: [AVAudioPCMBuffer], sentenceStarts: [Double]) {
        var buffers: [AVAudioPCMBuffer] = []
        var sentenceStarts: [Double] = []
        var frames: AVAudioFramePosition = 0
        var sampleRate = 22_050.0
        for sentence in sentences {
            sentenceStarts.append(Double(frames) / sampleRate)
            for buffer in await render(sentence, voice: voice) {
                sampleRate = buffer.format.sampleRate
                frames += AVAudioFramePosition(buffer.frameLength)
                buffers.append(buffer)
            }
        }
        guard !buffers.isEmpty else { throw SpeechSynthesisError.noVoice }
        return (buffers, sentenceStarts)
    }

    private func render(_ text: String, voice: AVSpeechSynthesisVoice?) async -> [AVAudioPCMBuffer] {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = Self.rate
        let collector = BufferCollector()
        return await withCheckedContinuation { continuation in
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    if let rendered = collector.finish() { continuation.resume(returning: rendered) }
                } else {
                    collector.append(pcm)
                }
            }
        }
    }
}

nonisolated enum SpeechSynthesisError: LocalizedError {
    case noVoice

    var errorDescription: String? {
        "No Chinese voice is installed. Download one in Settings › Accessibility › Spoken Content › Voices."
    }
}

private nonisolated final class BufferCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []
    private var finished = false

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { buffers.append(buffer) }
    }

    func finish() -> [AVAudioPCMBuffer]? {
        lock.withLock {
            guard !finished else { return nil }
            finished = true
            return buffers
        }
    }
}
