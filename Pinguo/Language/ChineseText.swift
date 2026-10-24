import Foundation

nonisolated enum ChineseText {
    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF, 0x2A700...0x2EBEF:
            true
        default:
            false
        }
    }

    static func containsHan(_ text: some StringProtocol) -> Bool {
        text.unicodeScalars.contains(where: isHan)
    }

    static func hanCharacterCount(_ text: some StringProtocol) -> Int {
        text.unicodeScalars.filter(isHan).count
    }

    /// PDFs often encode common characters as Kangxi or CJK radical code points (⼀ ⼩ ⼭); map those back to the
    /// unified ideographs (一 小 山) without the side effects of full NFKC, which would also rewrite punctuation.
    static func normalizingRadicals(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: isRadical) else { return text }
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if isRadical(scalar) {
                scalars.append(contentsOf: String(scalar).precomposedStringWithCompatibilityMapping.unicodeScalars)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    private static func isRadical(_ scalar: Unicode.Scalar) -> Bool {
        (0x2E80...0x2EFF).contains(scalar.value) || (0x2F00...0x2FDF).contains(scalar.value)
    }

    static let sentenceTerminators: Set<Character> = ["。", "！", "？", "!", "?", "…", "；"]
    static let closingPunctuation: Set<Character> = ["”", "’", "」", "』", "）", ")", "》", "\"", "'", "】"]

    /// Paragraphs split on line breaks, each split into sentences on 。！？ keeping closing quotes attached.
    static func paragraphs(from text: String) -> [[String]] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{3000}"))) }
            .filter { !$0.isEmpty }
            .map(sentences(in:))
            .filter { !$0.isEmpty }
    }

    static func sentences(in paragraph: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        var characters = Array(paragraph)[...]
        while let character = characters.popFirst() {
            current.append(character)
            guard sentenceTerminators.contains(character) else { continue }
            while let next = characters.first, sentenceTerminators.contains(next) || closingPunctuation.contains(next) {
                current.append(next)
                characters.removeFirst()
            }
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { sentences.append(trimmed) }
            current = ""
        }
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { sentences.append(trimmed) }
        return splitOverlong(sentences)
    }

    /// Breaks very long run-on sentences at commas so playback chunks and token offsets stay small.
    private static func splitOverlong(_ sentences: [String], limit: Int = 180) -> [String] {
        sentences.flatMap { sentence -> [String] in
            guard sentence.count > limit else { return [sentence] }
            var pieces: [String] = []
            var current = ""
            for character in sentence {
                current.append(character)
                if current.count >= limit / 2, "，,、：:".contains(character) {
                    pieces.append(current)
                    current = ""
                }
            }
            if !current.isEmpty { pieces.append(current) }
            return pieces
        }
    }
}
