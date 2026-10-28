import AVFoundation

/// On-device zh-CN voice for single words when offline or when latency matters.
final class SpeechFallback {
    static let shared = SpeechFallback()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, rate: Float = 0.42) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = OnDeviceSpeech.bestVoice
        utterance.rate = rate
        synthesizer.speak(utterance)
    }
}
