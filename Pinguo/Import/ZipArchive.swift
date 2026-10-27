import Compression
import Foundation

/// Minimal read-only ZIP reader (stored and deflate entries), enough for EPUB containers.
nonisolated struct ZipArchive {
    struct Entry {
        let path: String
        let compressionMethod: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: Error {
        case notAZipFile, unsupportedCompression(UInt16), corruptEntry(String)
    }

    private let data: Data
    let entries: [String: Entry]

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    func contents(of path: String) throws -> Data {
        let normalized = path.removingPercentEncoding ?? path
        guard let entry = entries[normalized] ?? entries[path] else { throw ZipError.corruptEntry(path) }
        let headerOffset = entry.localHeaderOffset
        guard data.count >= headerOffset + 30, data.uint32(at: headerOffset) == 0x04034B50 else {
            throw ZipError.corruptEntry(path)
        }
        let nameLength = Int(data.uint16(at: headerOffset + 26))
        let extraLength = Int(data.uint16(at: headerOffset + 28))
        let start = headerOffset + 30 + nameLength + extraLength
        guard start + entry.compressedSize <= data.count else { throw ZipError.corruptEntry(path) }
        let compressed = data.subdata(in: start..<(start + entry.compressedSize))
        switch entry.compressionMethod {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.compressionMethod)
        }
    }

    private static func readCentralDirectory(_ data: Data) throws -> [String: Entry] {
        let minimumEndRecord = 22
        guard data.count >= minimumEndRecord else { throw ZipError.notAZipFile }
        var endOffset = data.count - minimumEndRecord
        let searchLimit = max(0, data.count - minimumEndRecord - 65_535)
        while endOffset >= searchLimit, data.uint32(at: endOffset) != 0x06054B50 {
            endOffset -= 1
        }
        guard endOffset >= searchLimit else { throw ZipError.notAZipFile }

        let entryCount = Int(data.uint16(at: endOffset + 10))
        var offset = Int(data.uint32(at: endOffset + 16))
        var entries: [String: Entry] = [:]
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, data.uint32(at: offset) == 0x02014B50 else { break }
            let method = data.uint16(at: offset + 10)
            let compressedSize = Int(data.uint32(at: offset + 20))
            let uncompressedSize = Int(data.uint32(at: offset + 24))
            let nameLength = Int(data.uint16(at: offset + 28))
            let extraLength = Int(data.uint16(at: offset + 30))
            let commentLength = Int(data.uint16(at: offset + 32))
            let localHeaderOffset = Int(data.uint32(at: offset + 42))
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            let path = String(decoding: nameData, as: UTF8.self)
            entries[path] = Entry(
                path: path,
                compressionMethod: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            )
            offset += 46 + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func inflate(_ compressed: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    source.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { throw ZipError.corruptEntry("deflate") }
        output.count = written
        return output
    }
}

private extension Data {
    nonisolated func uint16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    nonisolated func uint32(at offset: Int) -> UInt32 {
        UInt32(uint16(at: offset)) | UInt32(uint16(at: offset + 2)) << 16
    }
}
