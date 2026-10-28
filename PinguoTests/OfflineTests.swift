import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Pinguo

@Suite(.serialized)
struct OfflineTests {
    @Test func onDeviceSpeechRendersAClipWithSentenceTimings() async throws {
        try #require(OnDeviceSpeech.bestVoice != nil, "No zh-CN voice installed on this runtime")
        let sentences = ["今天天气很好。", "我们去公园散步吧。"]
        let clip = try await OnDeviceSpeech.shared.clip(sentences: sentences)

        #expect(clip.isOnDevice)
        #expect(clip.sentenceStarts.count == 2)
        #expect(clip.sentenceStarts[0] == 0)
        #expect(clip.sentenceStarts[1] > 0.3)
        #expect(clip.duration > clip.sentenceStarts[1])
        let player = try AVAudioPlayer(contentsOf: clip.fileURL)
        #expect(abs(player.duration - clip.duration) < 0.5)
    }

    @Test func narrationFallsBackToOnDeviceVoiceWhenOffline() async throws {
        try #require(OnDeviceSpeech.bestVoice != nil, "No zh-CN voice installed on this runtime")
        CloudReachability.set(online: false)
        defer { CloudReachability.set(online: true) }

        let clip = try await AudioCache.shared.clip(sentences: ["飞机马上就要起飞了。"], voiceID: ElevenLabsClient.defaultVoiceID, modelID: ElevenLabsClient.defaultModelID)
        #expect(clip.isOnDevice)
        #expect(await AudioCache.shared.cachedClip(sentences: ["飞机马上就要起飞了。"], voiceID: ElevenLabsClient.defaultVoiceID, modelID: ElevenLabsClient.defaultModelID) == nil)
    }

    @Test func offlineErrorsAreRecognised() {
        #expect(CloudReachability.isOffline(URLError(.notConnectedToInternet)))
        #expect(CloudReachability.isOffline(URLError(.timedOut)))
        #expect(!CloudReachability.isOffline(URLError(.badServerResponse)))
        #expect(!CloudReachability.isOffline(ServiceError.refused))
    }

    @Test func tutorPinyinComesFromTheDictionary() {
        #expect(OnDeviceTutor.pinyin(for: "你好！我们去吃饭吧？") == "nǐhǎo wǒmen qù chīfàn ba")
    }

    @Test func dropsBlankAndListSuggestionsFromTheOnDeviceTutor() {
        #expect(OnDeviceTutor.usableSuggestions(["", "水果茶、红茶、奶茶、咖啡", " 我要一杯热拿铁。 "]) == ["我要一杯热拿铁。"])
    }

    @Test func offlineDownloadScopeStartsAtTheCurrentChapter() throws {
        let context = ModelContext(PinguoStore.makeContainer(inMemory: true))
        let document = Document(title: "Test", kind: .epub)
        context.insert(document)
        for index in 0..<5 {
            let chapter = Chapter(index: index, title: "\(index)", firstSentenceOffset: index)
            let sentence = Sentence(index: 0, paragraphIndex: 0, text: "第\(index)章。", tokens: [])
            context.insert(chapter)
            context.insert(sentence)
            chapter.document = document
            sentence.chapter = chapter
        }
        document.lastChapterIndex = 2

        #expect(OfflineDownloads.chapters(of: document, scope: .nextChapters(2)) == [["第2章。"], ["第3章。"]])
        #expect(OfflineDownloads.chapters(of: document, scope: .wholeBook).count == 5)
    }
}
