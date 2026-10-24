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
