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
