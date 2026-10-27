import Foundation
import Testing
@testable import Pinguo

struct EPUBParserTests {
    private var fixtureURL: URL {
        Bundle(for: FixtureLocator.self).url(forResource: "weekend", withExtension: "epub")!
    }

    @Test func readsMetadataChaptersAndTitles() throws {
        let book = try EPUBParser.parse(url: fixtureURL)
        #expect(book.title == "周末的小山")
        #expect(book.author == "测试作者")
        #expect(book.chapters.map(\.title) == ["周末的小山", "回家的路"])
        #expect(book.chapters[0].text.contains("这里的风景比照片上的好看多了"))
        #expect(!book.chapters[0].text.contains("<"))
    }

    @Test func splitsPlainTextOnChapterHeadings() {
        let chapters = DocumentImporter.splitIntoChapters("第一章 开始\n你好。\n第二章 结束\n再见。")
        #expect(chapters.map(\.title) == ["第一章 开始", "第二章 结束"])
        #expect(chapters[1].text == "再见。")
    }

    @Test func decodesEntities() {
        #expect(HTMLText.plainText(from: "<p>A&nbsp;&amp;&#x4F60;&#22909;</p><p>B</p>") == "A &你好\nB")
    }
}

final class FixtureLocator {}

struct ArticleExtractorTests {
    @Test func keepsArticleParagraphsAndDropsBoilerplate() throws {
        let html = """
        <html><head><title>人工智能如何改变制造业 | 新闻网</title><meta charset="utf-8"></head>
        <body><nav><a href="/">首页</a><a href="/news">新闻</a></nav>
        <div class="ad"><p><a href="/buy">点击这里购买最新的手机和电脑产品</a></p></div>
        <article><h1>人工智能如何改变制造业</h1>
        <p>近年来，人工智能技术在制造业中的应用越来越广泛。</p>
        <p>很多工厂开始使用机器人和智能系统，提高了生产效率。</p></article>
        <footer><p>版权所有，未经许可不得转载本网站的任何内容。</p></footer></body></html>
        """
        let book = try ArticleExtractor.extract(html: html, url: URL(string: "https://example.com/a"))
        #expect(book.title == "人工智能如何改变制造业")
        let text = book.chapters[0].text
        #expect(text.contains("提高了生产效率"))
        #expect(!text.contains("版权所有"))
        #expect(!text.contains("购买"))
    }

    @Test func reflowsHardWrappedPDFLines() {
        let wrapped = "周末的早上，我和朋友去了城外的一\n座小山。山不高，但是路很长。\n第二段开始了，我们一边走一边聊\n天。"
        #expect(PDFImporter.reflow(wrapped) == "周末的早上，我和朋友去了城外的一座小山。山不高，但是路很长。\n第二段开始了，我们一边走一边聊天。")
    }
}

struct PDFImporterTests {
    @Test func extractsAndReflowsText() throws {
        let url = Bundle(for: FixtureLocator.self).url(forResource: "hill", withExtension: "pdf")!
        let book = try PDFImporter.parse(url: url)
        #expect(book.title == "小山游记")
        #expect(book.coverImage != nil)
        let paragraphs = book.chapters.map(\.text).joined(separator: "\n").components(separatedBy: "\n")
        #expect(paragraphs.first?.hasPrefix("周末的早上，我和朋友去了城外的一座小山。") == true)
        #expect(paragraphs.contains { $0.contains("这里的风景比照片上的好看多了") })
    }
}

struct AudioTranslationTests {
    @Test func groupsTimedWordsIntoSentenceLines() {
        let words = [
            TimedWord(text: "Good", start: 0, end: 0.3), TimedWord(text: "morning,", start: 0.3, end: 0.7),
            TimedWord(text: "everyone.", start: 0.7, end: 1.2), TimedWord(text: "Let's", start: 1.5, end: 1.7),
            TimedWord(text: "start", start: 1.7, end: 2.0),
        ]
        let lines = AudioTranslation.lines(from: words)
        #expect(lines == [
            TranscriptLine(english: "Good morning, everyone.", start: 0, end: 1.2),
            TranscriptLine(english: "Let's start", start: 1.5, end: 2.0),
        ])
    }
}
