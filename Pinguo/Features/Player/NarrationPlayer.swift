import AVFoundation
import MediaPlayer
import Observation
import SwiftData

/// Plays a document chapter by chapter in the chosen ElevenLabs voice, generating audio a few sentences
/// ahead of the playhead and reporting which sentence is being spoken.
@Observable
final class NarrationPlayer: NSObject, AVAudioPlayerDelegate {
    private(set) var document: Document?
    private(set) var chapterIndex = 0
    private(set) var currentSentence: Int?
    private(set) var isPlaying = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var elapsed: Double = 0
    private(set) var total: Double = 0
    var speed: Double = 1.0 {
        didSet { audioPlayer?.rate = Float(speed) }
    }

    private var voiceID = ElevenLabsClient.defaultVoiceID
    private var modelID = ElevenLabsClient.defaultModelID
    private var chapterTitle = ""
    private var sentences: [String] = []
    private var chunks: [NarrationChunk] = []
    private var clips: [Int: NarrationClip] = [:]
    private var chunkIndex = 0
    private var audioPlayer: AVAudioPlayer?
    private var ticker: Timer?
    private var loadGeneration = 0
    private var remoteCommandsConfigured = false

    // MARK: Loading

    func isPlaying(_ document: Document) -> Bool {
        self.document?.id == document.id && isPlaying
    }

    func isLoaded(_ document: Document, chapter: Int) -> Bool {
        self.document?.id == document.id && chapterIndex == chapter
    }

    /// Prepares a chapter and starts playing at `sentence`.
    func play(_ document: Document, chapter: Int, from sentence: Int, voiceID: String, modelID: String) {
        configureSessionIfNeeded()
        let voiceChanged = voiceID != self.voiceID || modelID != self.modelID
        self.voiceID = voiceID
        self.modelID = modelID
        if self.document?.id != document.id || chapterIndex != chapter || sentences.isEmpty || voiceChanged {
            prepare(document, chapter: chapter)
        }
        start(atSentence: sentence)
    }

    private func prepare(_ document: Document, chapter: Int) {
        self.document = document
        chapterIndex = chapter
        let chapterModel = document.orderedChapters.first { $0.index == chapter }
        chapterTitle = chapterModel?.title ?? ""
        sentences = chapterModel?.orderedSentences.map(\.text) ?? []
        chunks = NarrationPlanner.chunks(for: sentences)
        clips = [:]
        for (index, chunk) in chunks.enumerated() {
            if let cached = AudioCache.readManifest(cacheKey(for: chunk)) { clips[index] = cached }
        }
        recomputeTimeline()
    }

    private func cacheKey(for chunk: NarrationChunk) -> String {
        AudioCache.key(text: sentences[chunk.sentenceRange].joined(), voiceID: voiceID, modelID: modelID)
    }

    // MARK: Transport

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if audioPlayer != nil {
            resume()
        } else if let currentSentence {
            start(atSentence: currentSentence)
        }
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTicker()
        updateNowPlaying()
    }

    func resume() {
        guard let audioPlayer else { return }
        audioPlayer.play()
        isPlaying = true
        startTicker()
        updateNowPlaying()
    }

    func stop() {
        loadGeneration += 1
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        isLoading = false
        currentSentence = nil
        document = nil
        stopTicker()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func skipSentence(by offset: Int) {
        let target = max(0, min(sentences.count - 1, (currentSentence ?? 0) + offset))
        start(atSentence: target)
    }

    func seek(toFraction fraction: Double) {
        let target = fraction * total
        var accumulated = 0.0
        for (index, chunk) in chunks.enumerated() {
            let length = duration(ofChunk: index)
            if accumulated + length >= target || index == chunks.count - 1 {
                let offsetInChunk = target - accumulated
                guard let clip = clips[index] else {
                    start(atSentence: chunk.sentenceRange.lowerBound)
                    return
                }
                let sentenceOffset = clip.sentenceStarts.lastIndex { $0 <= offsetInChunk } ?? 0
                start(atSentence: chunk.sentenceRange.lowerBound + sentenceOffset, offset: offsetInChunk - clip.sentenceStarts[sentenceOffset])
                return
            }
            accumulated += length
        }
    }

    private func start(atSentence sentence: Int, offset: Double = 0) {
        guard let index = chunks.firstIndex(where: { $0.sentenceRange.contains(sentence) }) else { return }
        currentSentence = sentence
        saveProgress()
        playChunk(index, sentence: sentence, extraOffset: offset)
    }

    private func playChunk(_ index: Int, sentence: Int? = nil, extraOffset: Double = 0) {
        loadGeneration += 1
        let generation = loadGeneration
        chunkIndex = index
        audioPlayer?.stop()
        audioPlayer = nil
        errorMessage = nil
        let chunk = chunks[index]

        Task {
            do {
                isLoading = clips[index] == nil
                let clip = try await clip(forChunk: index)
                guard generation == loadGeneration else { return }
                isLoading = false
                let player = try AVAudioPlayer(contentsOf: clip.fileURL)
                player.delegate = self
                player.enableRate = true
                player.rate = Float(speed)
                let sentenceOffset = (sentence ?? chunk.sentenceRange.lowerBound) - chunk.sentenceRange.lowerBound
                let startTime = clip.sentenceStarts.indices.contains(sentenceOffset) ? clip.sentenceStarts[sentenceOffset] : 0
                player.currentTime = max(0, startTime + extraOffset - 0.05)
                player.play()
                audioPlayer = player
                isPlaying = true
                startTicker()
                updateNowPlaying()
                prefetch(after: index)
            } catch {
                guard generation == loadGeneration else { return }
                isLoading = false
                isPlaying = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func clip(forChunk index: Int) async throws -> NarrationClip {
        if let cached = clips[index] { return cached }
        let chunk = chunks[index]
        let clip = try await AudioCache.shared.clip(sentences: Array(sentences[chunk.sentenceRange]), voiceID: voiceID, modelID: modelID)
        clips[index] = clip
        recomputeTimeline()
        return clip
    }

    private func prefetch(after index: Int) {
        for next in (index + 1)...(index + 2) where chunks.indices.contains(next) && clips[next] == nil {
            Task { _ = try? await clip(forChunk: next) }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.advanceAfterChunk() }
    }

    private func advanceAfterChunk() {
        if chunks.indices.contains(chunkIndex + 1) {
            currentSentence = chunks[chunkIndex + 1].sentenceRange.lowerBound
            playChunk(chunkIndex + 1)
        } else if let document, document.orderedChapters.contains(where: { $0.index == chapterIndex + 1 }) {
            prepare(document, chapter: chapterIndex + 1)
            start(atSentence: 0)
        } else {
            isPlaying = false
            stopTicker()
            updateNowPlaying()
        }
    }

    // MARK: Timeline

    private func duration(ofChunk index: Int) -> Double {
        clips[index]?.duration ?? Double(chunks[index].characterCount) * NarrationPlanner.secondsPerCharacter
    }

    private func recomputeTimeline() {
        total = chunks.indices.reduce(0) { $0 + duration(ofChunk: $1) }
        updateElapsed()
    }

    private func updateElapsed() {
        let before = (0..<min(chunkIndex, chunks.count)).reduce(0) { $0 + duration(ofChunk: $1) }
        elapsed = before + (audioPlayer?.currentTime ?? 0)
    }

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let audioPlayer, let clip = clips[chunkIndex], chunks.indices.contains(chunkIndex) else { return }
        let time = audioPlayer.currentTime
        let offset = clip.sentenceStarts.lastIndex { $0 <= time + 0.05 } ?? 0
        let sentence = chunks[chunkIndex].sentenceRange.lowerBound + offset
        if sentence != currentSentence {
            currentSentence = sentence
            saveProgress()
        }
        updateElapsed()
    }

    private func saveProgress() {
        guard let document, let currentSentence else { return }
        document.lastChapterIndex = chapterIndex
        document.lastSentenceIndex = currentSentence
        if let chapter = document.orderedChapters.first(where: { $0.index == chapterIndex }) {
            document.sentencesRead = max(document.sentencesRead, chapter.firstSentenceOffset + currentSentence + 1)
        }
    }

    // MARK: System integration

    private func configureSessionIfNeeded() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlayPause(); return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.skipSentence(by: 1); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.skipSentence(by: -1); return .success }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent, total > 0 else { return .commandFailed }
            seek(toFraction: event.positionTime / total)
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let document else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: chapterTitle.isEmpty ? document.title : chapterTitle,
            MPMediaItemPropertyAlbumTitle: document.title,
            MPMediaItemPropertyPlaybackDuration: total,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? speed : 0,
        ]
        if let author = document.author { info[MPMediaItemPropertyArtist] = author }
        if let data = document.coverImage, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
