import Foundation
import Testing
@testable import IMECore

@Suite(.serialized)
struct IMECoreCorrectnessRegressionTests {
    @Test func exactRawAndAbbreviationHitsKeepUserTierAndCanBeDisabled() throws {
        let (exactDefaults, exactSuite) = try isolatedDefaults()
        defer { exactDefaults.removePersistentDomain(forName: exactSuite) }
        let exactFreq = try makeUserFreq(defaults: exactDefaults)
        exactFreq.record("你", pinyin: "ni")
        exactFreq.record("泥", pinyin: "ni")
        let exactEngine = CandidateEngine(
            store: try makeStore(records: [("ni", "你", 1_000_000), ("ni", "擬", 800_000)], syllables: ["ni"]),
            userFreq: exactFreq, userFreqEnabled: { true }, fuzzyPinyinEnabled: { false })

        let exact = exactEngine.candidates(for: "ni")
        #expect(exact.first(where: { $0.text == "你" })?.isUser == true)
        #expect(exact.first(where: { $0.text == "泥" })?.isUser == true)
        #expect(exact.firstIndex(where: { $0.isUser })! < exact.firstIndex(where: { !$0.isUser })!)

        // The first 16 h-initial syllables exclude "hao" from n+h expansion.
        // The whole-code "nh" lookup must therefore retain the learned word's tier.
        let hPrefixes = (0..<16).map { "ha" + String(UnicodeScalar(97 + $0)!) }.filter { $0 != "hao" }
        let syllables = ["ni", "haaa"] + hPrefixes + ["hao"]
        let (abbreviationDefaults, abbreviationSuite) = try isolatedDefaults()
        defer { abbreviationDefaults.removePersistentDomain(forName: abbreviationSuite) }
        let abbreviationFreq = try makeUserFreq(defaults: abbreviationDefaults)
        abbreviationFreq.record("你好", pinyin: "ni hao")
        let abbreviationEngine = CandidateEngine(
            store: try makeStore(records: [("nh", "你好", 1_000_000)], syllables: syllables),
            userFreq: abbreviationFreq, userFreqEnabled: { true }, fuzzyPinyinEnabled: { false })
        let abbreviation = abbreviationEngine.candidates(for: "nh")
        #expect(abbreviation.first(where: { $0.text == "你好" })?.isUser == true)

        let disabledEngine = CandidateEngine(
            store: try makeStore(records: [("ni", "你", 1_000_000), ("ni", "擬", 800_000)], syllables: ["ni"]),
            userFreq: exactFreq, userFreqEnabled: { false }, fuzzyPinyinEnabled: { false })
        let disabled = disabledEngine.candidates(for: "ni")
        #expect(disabled.allSatisfy { !$0.isUser })
        #expect(exactFreq.count("你") == 1, "停用個人學習時保留既有資料")
    }

    @Test func externalDeleteAndImportMergePendingCountsAndPinyin() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var initialCounts = ["刪除詞": 4, "刪同詞": 7, "匯入詞": 10]
        for index in 0..<4_997 { initialCounts[String(format: "old%04d", index)] = 1 }
        #expect(initialCounts.count == 5_000)
        defaults.set(initialCounts, forKey: "AFMUserFreq")
        defaults.set(["刪除詞": "jiu", "刪同詞": "jiu", "匯入詞": "jiu"], forKey: "AFMUserPinyin")
        let freq = try makeUserFreq(defaults: defaults)

        freq.record("新詞", pinyin: "xin")
        freq.record("新詞", pinyin: "xin")
        freq.record("匯入詞", pinyin: "local")
        freq.record("刪同詞", pinyin: "local")

        var importedCounts = ["匯入詞": 100, "外部詞": 2]
        for index in 0..<4_998 { importedCounts[String(format: "external%04d", index)] = 1 }
        #expect(importedCounts.count == 5_000)
        defaults.set(importedCounts, forKey: "AFMUserFreq")
        defaults.set(["匯入詞": "external", "外部詞": "ta"], forKey: "AFMUserPinyin")
        defaults.set(["刪除詞", "刪同詞"], forKey: "AFMUserWordsDeleted")
        freq.reloadFromDefaults()

        let merged = await waitUntil {
            freq.count("新詞") == 2 && freq.count("匯入詞") == 101
                && freq.count("刪除詞") == 0 && freq.count("刪同詞") == 0
        }
        #expect(merged)
        #expect(freq.count("外部詞") == 2)
        #expect(freq.hits(key: "external", partialPrefix: false).contains(where: { $0.word == "匯入詞" }))
        freq.reloadFromDefaults()
        #expect(freq.count("匯入詞") == 101, "相同外部狀態重複通知不可重複套用 pending 增量")

        let didSave = await waitUntil {
            let counts = defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] ?? [:]
            let pins = defaults.dictionary(forKey: "AFMUserPinyin") as? [String: String] ?? [:]
            return counts.count == 5_000 && counts["新詞"] == 2
                && counts["匯入詞"] == 101 && pins["匯入詞"] == "external"
        }
        #expect(didSave, "等待 pending 合併結果實際落盤")
        let savedCounts = defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] ?? [:]
        let savedPinyins = defaults.dictionary(forKey: "AFMUserPinyin") as? [String: String] ?? [:]
        #expect(savedCounts.count == 5_000, "外部 5000 條加 pending 新詞後仍須受容量上限限制")
        #expect(savedCounts["新詞"] == 2)
        #expect(savedCounts["匯入詞"] == 101)
        #expect(savedCounts["外部詞"] == 2)
        #expect(savedCounts["刪除詞"] == nil, "刪除墓碑優先於舊資料及 pending")
        #expect(savedCounts["刪同詞"] == nil, "刪除墓碑丟棄同詞的 pending 增量")
        #expect(savedPinyins["匯入詞"] == "external", "外部明確拼音更新優先")
    }

    @Test func clearMarkerDiscardsPendingAndInvalidatesOldSave() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["既有詞": 3], forKey: "AFMUserFreq")
        defaults.set(["既有詞": "jiu"], forKey: "AFMUserPinyin")
        let freq = try makeUserFreq(defaults: defaults)

        freq.record("待清除", pinyin: "dai")
        defaults.removeObject(forKey: "AFMUserFreq")
        defaults.removeObject(forKey: "AFMUserPinyin")
        defaults.set(UUID().uuidString, forKey: UserFreq.clearMarkerKey)
        freq.reloadFromDefaults()

        let cleared = await waitUntil { freq.count("待清除") == 0 && freq.count("既有詞") == 0 }
        #expect(cleared)
        freq.record("清空後新詞", pinyin: "xin")
        let didSave = await waitUntil {
            let counts = defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] ?? [:]
            return counts["清空後新詞"] == 1 && counts["待清除"] == nil && counts["既有詞"] == nil
        }
        #expect(didSave, "等待清空後的新詞實際落盤")

        let savedCounts = defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] ?? [:]
        #expect(savedCounts["待清除"] == nil)
        #expect(savedCounts["既有詞"] == nil)
        #expect(savedCounts["清空後新詞"] == 1)
    }

    @Test func selectingADeletedWordRemovesItsTombstoneAndAllowsRelearning() async throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["其他詞": 4], forKey: "AFMUserFreq")
        defaults.set(["其他詞": "qi"], forKey: "AFMUserPinyin")
        defaults.set(["重新學習詞"], forKey: "AFMUserWordsDeleted")
        let freq = try makeUserFreq(defaults: defaults)

        freq.record("重新學習詞", pinyin: "xin")
        #expect(!(defaults.stringArray(forKey: "AFMUserWordsDeleted") ?? []).contains("重新學習詞"))

        defaults.set(["其他詞": 6], forKey: "AFMUserFreq")
        freq.reloadFromDefaults()
        let merged = await waitUntil { freq.count("重新學習詞") == 1 && freq.count("其他詞") == 6 }
        #expect(merged, "重新選用後的詞不應被後續外部同步墓碑刪除")

        let didSave = await waitUntil {
            let counts = defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] ?? [:]
            return counts["重新學習詞"] == 1 && counts["其他詞"] == 6
        }
        #expect(didSave)
    }

    @Test func maximumImportedCountDoesNotCrashOnScoringOrLearning() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["上限詞": Int.max], forKey: "AFMUserFreq")
        let freq = try makeUserFreq(defaults: defaults)
        #expect(freq.userScore(count: Int.max).isFinite)
        freq.record("上限詞", pinyin: "shang xian ci")
        #expect(freq.count("上限詞") == Int.max)
        freq.reloadFromDefaults()
        #expect(freq.count("上限詞") == Int.max)
    }

    private func makeUserFreq(defaults: UserDefaults,
                              observesExternalChanges: Bool = false) throws -> UserFreq {
        let seedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ime-user-seed-\(UUID().uuidString).json")
        try Data(#"{"version":1,"words":[]}"#.utf8).write(to: seedURL)
        defer { try? FileManager.default.removeItem(at: seedURL) }
        return UserFreq(defaults: defaults, builtinWordsURL: seedURL,
                        observesExternalChanges: observesExternalChanges)
    }

    private func isolatedDefaults() throws -> (defaults: UserDefaults, suite: String) {
        let suite = "IMECoreCorrectnessRegressionTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw TestFixtureError.defaultsUnavailable
        }
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func makeStore(records: [(String, String, UInt32)], syllables: [String]) throws -> DictStore {
        let sorted = records.sorted {
            if $0.0 != $1.0 { return $0.0 < $1.0 }
            if $0.2 != $1.2 { return $0.2 > $1.2 }
            return $0.1 < $1.1
        }
        var syllableData = Data()
        for syllable in syllables {
            let bytes = Data(syllable.utf8)
            appendLE(UInt16(bytes.count), to: &syllableData)
            syllableData.append(bytes)
        }
        let offsetsOffset = DictFormat.headerSize
        let syllablesOffset = offsetsOffset + sorted.count * MemoryLayout<UInt64>.size
        let recordsOffset = syllablesOffset + syllableData.count
        var recordData = Data()
        var recordOffsets: [UInt64] = []
        for (key, word, weight) in sorted {
            recordOffsets.append(UInt64(recordsOffset + recordData.count))
            let keyBytes = Data(key.utf8)
            let wordBytes = Data(word.utf8)
            recordData.append(UInt8(keyBytes.count))
            recordData.append(keyBytes)
            recordData.append(UInt8(wordBytes.count))
            recordData.append(wordBytes)
            appendLE(weight, to: &recordData)
        }

        var data = Data()
        appendLE(DictFormat.magic, to: &data)
        appendLE(DictFormat.version, to: &data)
        appendLE(UInt64(sorted.count), to: &data)
        appendLE(UInt64(offsetsOffset), to: &data)
        appendLE(UInt64(syllables.count), to: &data)
        appendLE(UInt64(syllablesOffset), to: &data)
        for offset in recordOffsets { appendLE(offset, to: &data) }
        data.append(syllableData)
        data.append(recordData)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ime-test-dict-\(UUID().uuidString).bin")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try DictStore(url: url)
    }

    private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    private enum TestFixtureError: Error {
        case defaultsUnavailable
    }
}
