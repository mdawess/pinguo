import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Pinguo

struct OnDeviceTests {
    @Test func narrationRendersAClipWithSentenceTimings() async throws {
        try #require(ChineseVoices.best != nil, "No zh-CN voice installed on this runtime")
        let clip = try await AudioCache.shared.clip(sentences: ["今天天气很好。", "我们去公园散步吧。"], voiceID: nil)

        #expect(clip.sentenceStarts.count == 2)
        #expect(clip.sentenceStarts[0] == 0)
        #expect(clip.sentenceStarts[1] > 0.3)
        #expect(clip.duration > clip.sentenceStarts[1])
        let player = try AVAudioPlayer(contentsOf: clip.fileURL)
        #expect(abs(player.duration - clip.duration) < 0.5)
    }

    @Test func unknownVoiceFallsBackToTheBestInstalledVoice() throws {
        let best = try #require(ChineseVoices.best)
        #expect(ChineseVoices.voice(withID: "Xb7hH8MSUJpSbSDYk0k2")?.identifier == best.identifier)
        #expect(ChineseVoices.voice(withID: nil)?.identifier == best.identifier)
        #expect(ChineseVoices.voice(withID: best.identifier)?.identifier == best.identifier)
    }

    @Test func tutorPinyinComesFromTheDictionary() {
        #expect(TutorService.pinyin(for: "你好！我们去吃饭吧？") == "nǐhǎo wǒmen qù chīfàn ba")
    }

    @Test func dropsBlankAndListSuggestionsFromTheTutor() {
        #expect(TutorService.usableSuggestions(["", "水果茶、红茶、奶茶、咖啡", " 我要一杯热拿铁。 "]) == ["我要一杯热拿铁。"])
    }

    @Test func rejectsCorrectionsThatRewriteTheLearnerIntoSomethingElse() {
        #expect(TutorService.isPlausibleCorrection("我要一杯热拿铁。", of: "我要一杯拿铁，热。"))
        #expect(TutorService.isPlausibleCorrection("我昨天去了商店。", of: "我昨天去商店了了。"))
        #expect(!TutorService.isPlausibleCorrection("您想吃什么零食？", of: "我要一杯拿铁，热。"))
    }

    @Test func tutorOpensTheConversationInChinese() async throws {
        try #require(TutorService.unavailableReason == nil, "Apple Intelligence unavailable on this runtime")
        let scenario = try #require(Scenario.presets.first)
        let turn = try await TutorService().respond(scenario: scenario, hskLevel: 3, deckWords: [], history: [])
        #expect(turn.reply.contains { ("\u{4E00}"..."\u{9FFF}").contains(String($0)) })
        #expect(!turn.pinyin.isEmpty)
    }

    @Test @MainActor func preparesNarrationForTheChaptersAheadOfTheReader() async throws {
        try #require(ChineseVoices.best != nil, "No zh-CN voice installed on this runtime")
        let context = ModelContext(PinguoStore.makeContainer(inMemory: true))
        let settings = AppSettings.current(in: context)
        settings.chaptersToPrepare = 2
        let document = Document(title: "Prepared", kind: .epub)
        document.status = .ready
        document.lastOpenedAt = .now
        document.lastChapterIndex = 1
        context.insert(document)
        let texts = ["第一章开始了。", "第二章开始了。", "第三章开始了。", "第四章开始了。"]
        for (index, text) in texts.enumerated() {
            let chapter = Chapter(index: index, title: "\(index)", firstSentenceOffset: index)
            let sentence = Sentence(index: 0, paragraphIndex: 0, text: text, tokens: [])
            context.insert(chapter)
            context.insert(sentence)
            chapter.document = document
            sentence.chapter = chapter
        }
        let voiceID = try #require(settings.voiceID(for: document))
        AudioCache.clear()

        await ChargingPreparation.shared.prepare(in: context)

        let cached = texts.map { AudioCache.readManifest(AudioCache.key(text: $0, voiceID: voiceID)) != nil }
        #expect(cached == [false, true, true, false])
    }
}
