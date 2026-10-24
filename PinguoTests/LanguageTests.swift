import Testing
@testable import Pinguo

struct SentenceSplittingTests {
    @Test func splitsOnChineseTerminatorsAndKeepsClosingQuotes() {
        let sentences = ChineseText.sentences(in: "他说：“你好！”我们走吧。好吗？")
        #expect(sentences == ["他说：“你好！”", "我们走吧。", "好吗？"])
    }

    @Test func splitsParagraphsOnLineBreaks() {
        let paragraphs = ChineseText.paragraphs(from: "第一段。第二句。\n\n　　第二段")
        #expect(paragraphs == [["第一段。", "第二句。"], ["第二段"]])
    }
}

struct SegmenterTests {
    let segmenter = Segmenter()

    private func words(_ sentence: String) -> [String] {
        segmenter.tokens(in: sentence).map { $0.text(in: sentence) }
    }

    @Test func keepsCompoundsWhole() {
        let result = words("这里的风景比照片上的好看多了。")
        #expect(result.contains("风景"))
        #expect(result.contains("照片"))
        #expect(result.last == "。")
    }

    @Test func tokensCoverTheWholeSentence() {
        let sentence = "周末的早上，我和朋友去了城外的一座小山。Hello 2026!"
        let spans = segmenter.tokens(in: sentence)
        #expect(spans.map { $0.text(in: sentence) }.joined() == sentence)
        #expect(spans.filter(\.isLexical).allSatisfy { ChineseText.containsHan($0.text(in: sentence)) })
    }

    @Test func tokenEncodingRoundTrips() {
        let spans = [TokenSpan(start: 0, length: 2, isLexical: true), TokenSpan(start: 300, length: 1, isLexical: false)]
        #expect(TokenSpan.decode(TokenSpan.encode(spans)) == spans)
    }
}

struct DictionaryTests {
    @Test func looksUpWordsWithHSKLevelAndPreferredReading() throws {
        let entry = try #require(ChineseDictionary.shared.lookup("风景"))
        #expect(entry.pinyin == "fēngjǐng")
        #expect(entry.hskLevel == 4)
        #expect(ChineseDictionary.shared.lookup("了")?.pinyin == "le")
    }

    @Test func breaksWordsIntoCharacterGlosses() {
        let breakdown = ChineseDictionary.shared.characterBreakdown(of: "风景")
        #expect(breakdown.map(\.character) == ["风", "景"])
        #expect(breakdown[0].gloss == "wind")
    }
}

struct NarrationPlanningTests {
    @Test func groupsSentencesIntoChunksOfAFewSentences() {
        let sentences = Array(repeating: "我们一边走一边聊天。", count: 10)
        let chunks = NarrationPlanner.chunks(for: sentences, targetCharacters: 35, maxSentences: 4)
        #expect(chunks.map(\.sentenceRange) == [0..<3, 3..<6, 6..<9, 9..<10])
        #expect(chunks.flatMap { Array($0.sentenceRange) } == Array(0..<10))
    }

    @Test func keepsAnOverlongSentenceInItsOwnChunk() {
        let long = String(repeating: "长", count: 300)
        let chunks = NarrationPlanner.chunks(for: ["短。", long, "短。"], targetCharacters: 160)
        #expect(chunks.map(\.sentenceRange) == [0..<1, 1..<2, 2..<3])
    }

    @Test func mapsSentenceStartsOntoCharacterTimings() {
        let alignment = CharacterAlignment(
            characters: ["你", "好", "。", "再", "见", "。"],
            starts: [0, 0.2, 0.4, 0.6, 0.8, 1.0],
            ends: [0.2, 0.4, 0.6, 0.8, 1.0, 1.2]
        )
        #expect(AudioCache.sentenceStarts(sentences: ["你好。", "再见。"], alignment: alignment) == [0, 0.6])
    }
}
