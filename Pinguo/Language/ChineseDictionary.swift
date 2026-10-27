import Foundation
import SQLite3

nonisolated struct DictionaryEntry: Hashable, Sendable {
    struct Reading: Hashable, Sendable, Decodable {
        let pinyin: String
        let definitions: [String]
    }

    let simplified: String
    let traditional: String
    let pinyin: String
    let tones: [Int]
    let definitions: [String]
    let otherReadings: [Reading]
    let partOfSpeech: String?
    let hskLevel: Int?
    let frequencyRank: Int?

    var gloss: String {
        definitions.prefix(3).joined(separator: "; ")
    }

    var shortGloss: String {
        let first = definitions.first ?? ""
        return first.split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? first
    }
}

/// CC-CEDICT with HSK levels, bundled read-only as SQLite.
nonisolated final class ChineseDictionary: @unchecked Sendable {
    static let shared = ChineseDictionary()

    private var database: OpaquePointer?
    private let lock = NSLock()
    private var cache: [String: DictionaryEntry?] = [:]
    private var headwordSet: Set<String>?
    private(set) var longestHeadwordLength = 1

    init(path: String? = Bundle.main.path(forResource: "dictionary", ofType: "sqlite")) {
        guard let path else { return }
        sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
    }

    deinit {
        sqlite3_close(database)
    }

    var headwords: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        if let headwordSet { return headwordSet }
        var words = Set<String>()
        words.reserveCapacity(130_000)
        var longest = 1
        query("SELECT simplified FROM headword", bind: { _ in }) { statement in
            let word = String(cString: sqlite3_column_text(statement, 0))
            longest = max(longest, word.count)
            words.insert(word)
        }
        headwordSet = words
        longestHeadwordLength = min(longest, 12)
        return words
    }

    /// Every headword at or below an HSK level, for seeding a learner's known words.
    func words(upToHSK level: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var words: [String] = []
        query("SELECT simplified FROM headword WHERE hsk_level IS NOT NULL AND hsk_level <= ?1", bind: { sqlite3_bind_int($0, 1, Int32(level)) }) { statement in
            words.append(String(cString: sqlite3_column_text(statement, 0)))
        }
        return words
    }

    func contains(_ word: String) -> Bool {
        headwords.contains(word)
    }

    func lookup(_ word: String) -> DictionaryEntry? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[word] { return cached }
        var entry: DictionaryEntry?
        let sql = """
            SELECT simplified, traditional, pinyin, tones, definitions, other_readings, part_of_speech, hsk_level, frequency_rank
            FROM headword WHERE simplified = ?1 OR traditional = ?1 LIMIT 1
            """
        query(sql, bind: { sqlite3_bind_text($0, 1, word, -1, SQLITE_TRANSIENT) }) { statement in
            entry = DictionaryEntry(
                simplified: Self.text(statement, 0),
                traditional: Self.text(statement, 1),
                pinyin: Self.text(statement, 2),
                tones: Self.text(statement, 3).compactMap { $0.wholeNumberValue },
                definitions: Self.decode([String].self, Self.text(statement, 4)) ?? [],
                otherReadings: Self.decode([DictionaryEntry.Reading].self, Self.text(statement, 5)) ?? [],
                partOfSpeech: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Self.text(statement, 6),
                hskLevel: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 7)),
                frequencyRank: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 8))
            )
        }
        cache[word] = entry
        return entry
    }

    /// Per-character glosses such as "风 wind + 景 view", for words of two or more characters.
    func characterBreakdown(of word: String) -> [(character: String, gloss: String)] {
        guard word.count > 1 else { return [] }
        return word.map { character in
            let gloss = lookup(String(character))?.shortGloss ?? ""
            return (String(character), Self.trimmedGloss(gloss))
        }
    }

    private static func trimmedGloss(_ gloss: String) -> String {
        var trimmed = gloss.replacingOccurrences(of: "(bound form) ", with: "")
        trimmed = trimmed.replacingOccurrences(of: #"\s*\(.*?\)\s*"#, with: " ", options: .regularExpression)
        trimmed = trimmed.replacingOccurrences(of: "to ", with: "", options: .anchored)
        return trimmed.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? trimmed
    }

    private func query(_ sql: String, bind: (OpaquePointer?) -> Void, row: (OpaquePointer?) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        while sqlite3_step(statement) == SQLITE_ROW {
            row(statement)
        }
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T? {
        try? JSONDecoder().decode(type, from: Data(json.utf8))
    }
}

nonisolated private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
