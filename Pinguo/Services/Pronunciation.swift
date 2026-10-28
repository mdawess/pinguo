import AVFoundation

/// Speaks a word or sentence straight away in the chosen on-device voice.
final class Pronunciation {
    static let shared = Pronunciation()
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, voiceID: String? = nil, rate: Float = SpeechSynthesis.rate) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = ChineseVoices.voice(withID: voiceID)
        utterance.rate = rate
        synthesizer.speak(utterance)
    }
}
