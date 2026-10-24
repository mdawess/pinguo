import Foundation
import NaturalLanguage

/// Word segmentation: NLTokenizer first, then refined against the dictionary with longest-match so
/// compounds such as 风景 stay whole and unknown runs are broken into known words.
nonisolated final class Segmenter: @unchecked Sendable {
    private let dictionary: ChineseDictionary
    private let lock = NSLock()

    init(dictionary: ChineseDictionary = .shared) {
        self.dictionary = dictionary
    }

    func tokens(in sentence: String) -> [TokenSpan] {
        let characters = Array(sentence)
        return runs(of: characters).flatMap { run in
            run.isHan
                ? segmentHan(Array(characters[run.range]), offset: run.range.lowerBound)
                : splitNonHan(characters, range: run.range)
        }
    }

    private struct Run {
        let range: Range<Int>
        let isHan: Bool
    }

    private func runs(of characters: [Character]) -> [Run] {
        var runs: [Run] = []
        var start = 0
        while start < characters.count {
            let isHan = Self.isHanCharacter(characters[start])
            var end = start + 1
            while end < characters.count, Self.isHanCharacter(characters[end]) == isHan {
                end += 1
            }
            runs.append(Run(range: start..<end, isHan: isHan))
            start = end
        }
        return runs
    }

    private static func isHanCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.first.map(ChineseText.isHan) ?? false
    }

    private func splitNonHan(_ characters: [Character], range: Range<Int>) -> [TokenSpan] {
        var spans: [TokenSpan] = []
        var start = range.lowerBound
        while start < range.upperBound {
            let isWordCharacter = characters[start].isLetter || characters[start].isNumber
            var end = start + 1
            while end < range.upperBound, (characters[end].isLetter || characters[end].isNumber) == isWordCharacter, isWordCharacter {
                end += 1
            }
            spans.append(TokenSpan(start: start, length: end - start, isLexical: false))
            start = end
        }
        return spans
    }

    private func segmentHan(_ characters: [Character], offset: Int) -> [TokenSpan] {
        let text = String(characters)
        let naturalTokens = naturalLanguageTokens(text)
        let words = dictionary.headwords
        let longest = dictionary.longestHeadwordLength
        var pieces: [String] = []
        var tokenIndex = 0
        while tokenIndex < naturalTokens.count {
            var merged: String?
            var mergedCount = 1
            var candidate = naturalTokens[tokenIndex]
            var lookahead = tokenIndex + 1
            while lookahead < naturalTokens.count, lookahead - tokenIndex < 4 {
                candidate += naturalTokens[lookahead]
                guard candidate.count <= longest else { break }
                if words.contains(candidate) {
                    merged = candidate
                    mergedCount = lookahead - tokenIndex + 1
                }
                lookahead += 1
            }
            if let merged {
                pieces.append(merged)
                tokenIndex += mergedCount
                continue
            }
            let token = naturalTokens[tokenIndex]
            if words.contains(token) || token.count == 1 {
                pieces.append(token)
            } else {
                let matched = forwardMaximumMatch(Array(token), words: words, longest: longest)
                pieces += matched.allSatisfy({ $0.count == 1 }) ? [token] : matched
            }
            tokenIndex += 1
        }

        var spans: [TokenSpan] = []
        var position = offset
        for piece in pieces {
            spans.append(TokenSpan(start: position, length: piece.count, isLexical: true))
            position += piece.count
        }
        return spans
    }

    private func naturalLanguageTokens(_ text: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.simplifiedChinese)
        tokenizer.string = text
        var tokens: [String] = []
        var covered = text.startIndex
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            if covered < range.lowerBound {
                tokens.append(contentsOf: text[covered..<range.lowerBound].map(String.init))
            }
            tokens.append(String(text[range]))
            covered = range.upperBound
            return true
        }
        if covered < text.endIndex {
            tokens.append(contentsOf: text[covered...].map(String.init))
        }
        return tokens
    }

    private func forwardMaximumMatch(_ characters: [Character], words: Set<String>, longest: Int) -> [String] {
        var pieces: [String] = []
        var start = 0
        while start < characters.count {
            var length = min(longest, characters.count - start)
            while length > 1, !words.contains(String(characters[start..<start + length])) {
                length -= 1
            }
            pieces.append(String(characters[start..<start + length]))
            start += length
        }
        return pieces
    }
}
