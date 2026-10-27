import AVFoundation

/// Plays a word or sentence in the chosen voice (cached), falling back to the on-device voice when offline.
final class Pronunciation {
    static let shared = Pronunciation()
    private var player: AVAudioPlayer?

    func speak(_ text: String, voiceID: String, modelID: String) {
        Task {
            do {
                let clip = try await AudioCache.shared.clip(sentences: [text], voiceID: voiceID, modelID: modelID)
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                let player = try AVAudioPlayer(contentsOf: clip.fileURL)
                player.play()
                self.player = player
            } catch {
                SpeechFallback.shared.speak(text)
            }
        }
    }
}
