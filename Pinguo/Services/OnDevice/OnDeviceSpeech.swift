import AVFoundation

/// Renders narration with the best installed Apple zh-CN voice into a cached clip, so the narration
/// player handles it exactly like an ElevenLabs clip (sentence highlighting included).
actor OnDeviceSpeech {
    static let shared = OnDeviceSpeech()
    nonisolated static let modelID = "apple-on-device"

    private let synthesizer = AVSpeechSynthesizer()

    nonisolated static var bestVoice: AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == "zh-CN" && !$0.voiceTraits.contains(.isPersonalVoice) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    nonisolated static var bestVoiceDescription: String {
        guard let voice = bestVoice else { return "No Chinese voice installed" }
        let quality = switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Default"
        }
        return "\(voice.name) (\(quality))"
    }

    nonisolated static var hasHighQualityVoice: Bool {
        (bestVoice?.quality ?? .default) != .default
    }

    nonisolated static func cacheKey(for sentences: [String], voice: AVSpeechSynthesisVoice?) -> String {
        AudioCache.key(text: sentences.joined(), voiceID: voice?.identifier ?? "zh-CN", modelID: modelID)
    }

    func clip(sentences: [String], rate: Float = AVSpeechUtteranceDefaultSpeechRate * 0.9) async throws -> NarrationClip {
        let voice = Self.bestVoice
        let key = Self.cacheKey(for: sentences, voice: voice)
        if let cached = AudioCache.readManifest(key) { return cached }

        var buffers: [AVAudioPCMBuffer] = []
        var sentenceStarts: [Double] = []
        var frames: AVAudioFramePosition = 0
        var sampleRate = 22_050.0
        for sentence in sentences {
            sentenceStarts.append(Double(frames) / sampleRate)
            let rendered = await render(sentence, voice: voice, rate: rate)
            for buffer in rendered {
                sampleRate = buffer.format.sampleRate
                frames += AVAudioFramePosition(buffer.frameLength)
                buffers.append(buffer)
            }
        }
        guard let format = buffers.first?.format else { throw OnDeviceSpeechError.noAudio }

        let fileName = "apple-\(key).caf"
        let file = try AVAudioFile(
            forWriting: AudioCache.directory.appending(path: fileName),
            settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount],
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved
        )
        for buffer in buffers { try file.write(from: buffer) }

        let clip = NarrationClip(fileName: fileName, sentenceStarts: sentenceStarts, duration: Double(frames) / format.sampleRate)
        try JSONEncoder().encode(clip).write(to: AudioCache.directory.appending(path: "\(key).json"), options: .atomic)
        return clip
    }

    private func render(_ text: String, voice: AVSpeechSynthesisVoice?, rate: Float) async -> [AVAudioPCMBuffer] {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
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

nonisolated enum OnDeviceSpeechError: LocalizedError {
    case noAudio

    var errorDescription: String? {
        "No Chinese voice is available on this device. Download one in Settings › Accessibility › Spoken Content › Voices."
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

extension NarrationClip {
    nonisolated var isOnDevice: Bool { fileName.hasPrefix("apple-") }
}
