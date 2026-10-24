import Foundation

/// A word inside a sentence, as character offsets so the Reader never re-segments.
nonisolated struct TokenSpan: Hashable, Sendable {
    var start: Int
    var length: Int
    var isLexical: Bool

    var range: Range<Int> { start..<(start + length) }

    func text(in sentence: String) -> String {
        let characters = Array(sentence)
        guard start >= 0, start + length <= characters.count else { return "" }
        return String(characters[range])
    }

    /// Packs each span into 4 bytes: start (UInt16), length (UInt8), flags (UInt8).
    static func encode(_ spans: [TokenSpan]) -> Data {
        var data = Data(capacity: spans.count * 4)
        for span in spans {
            let start = UInt16(clamping: span.start)
            data.append(UInt8(start >> 8))
            data.append(UInt8(start & 0xFF))
            data.append(UInt8(clamping: span.length))
            data.append(span.isLexical ? 1 : 0)
        }
        return data
    }

    static func decode(_ data: Data) -> [TokenSpan] {
        let bytes = [UInt8](data)
        var spans: [TokenSpan] = []
        spans.reserveCapacity(bytes.count / 4)
        var offset = 0
        while offset + 3 < bytes.count {
            let start = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            let length = Int(bytes[offset + 2])
            spans.append(TokenSpan(start: start, length: length, isLexical: bytes[offset + 3] == 1))
            offset += 4
        }
        return spans
    }
}
