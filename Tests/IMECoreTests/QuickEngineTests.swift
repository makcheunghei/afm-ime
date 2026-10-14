import Foundation
import Testing
@testable import IMECore

struct QuickEngineTests {
    @Test func jsonKeepsStableOrderDeduplicatesAndDefaultsFullCharset() throws {
        let dictionary = try loadJSON(#"{"version":1,"candidates":{"ab":["甲","乙","甲","　"]}}"#)

        #expect(dictionary.candidates(for: "ab") == ["甲", "乙", "　"])
        #expect(dictionary.candidates(for: "ab", fullCharset: true) == ["甲", "乙", "　"])
        #expect(dictionary.candidates(for: "AB").isEmpty)
        #expect(dictionary.candidates(for: "abc").isEmpty)
    }

    @Test func rejectsUnsupportedVersionAndMalformedCodesOrEmptyText() {
        #expect(throws: (any Error).self) {
            try loadJSON(#"{"version":2,"candidates":{}}"#)
        }
        #expect(throws: (any Error).self) {
            try loadJSON(#"{"version":1,"candidates":{"A":["字"]}}"#)
        }
        #expect(throws: (any Error).self) {
            try loadJSON(#"{"version":1,"candidates":{"a":[""]}}"#)
        }
    }

    @Test func preservesSupplementaryPlaneCharacters() throws {
        let dictionary = try loadJSON(#"{"version":1,"candidates":{"a":["𠮷"]}}"#)
        #expect(dictionary.candidates(for: "a") == ["𠮷"])
    }

    @Test func exactLookupFullCandidatesAndMoreThanOneHundredCandidates() throws {
        let standard = (0..<3).map { "常\($0)" }
        let full = standard + (3..<125).map { "全\($0)" }
        let dictionary = QuickDictionary(candidates: ["ab": standard], fullCandidates: ["ab": full])
        let engine = QuickEngine(dictionary: dictionary, defaults: try isolatedDefaults())

        #expect(engine.candidates(for: "ab") == standard)
        #expect(engine.candidates(for: "ab", fullCharset: true) == full)
        #expect(engine.candidates(for: "a").isEmpty)
    }

    @Test func associationsUseExactPrefixAndKeepDeclaredOrder() throws {
        let engine = QuickEngine(
            dictionary: QuickDictionary(candidates: [:], associations: ["天": ["氣", "空", "氣"]]),
            defaults: try isolatedDefaults()
        )

        #expect(engine.associations(after: "天") == ["氣", "空"])
        #expect(engine.associations(after: "天氣").isEmpty)
    }

    @Test func learningDisabledDoesNotWriteAndEnabledOnlyChangesQuickLearningKey() throws {
        let defaults = try isolatedDefaults()
        let dictionary = QuickDictionary(candidates: ["ab": ["甲", "乙"]])
        let engine = QuickEngine(dictionary: dictionary, defaults: defaults)
        defaults.set(["preserve": 7], forKey: "unrelated")
        defaults.set(["old": 3], forKey: "AFMUserFreq")
        let before = defaults.dictionaryRepresentation()

        engine.recordSelection(code: "ab", text: "甲", enabled: false)
        #expect((defaults.dictionaryRepresentation() as NSDictionary) == (before as NSDictionary))

        engine.recordSelection(code: "ab", text: "乙", enabled: true)
        #expect(defaults.dictionary(forKey: QuickPrefs.learningDataKey) as? [String: [String: Int]] == ["ab": ["乙": 1]])
        #expect(defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] == ["old": 3])
        #expect(defaults.dictionary(forKey: "unrelated") as? [String: Int] == ["preserve": 7])
        #expect(Set(defaults.dictionaryRepresentation().keys) == Set(before.keys).union([QuickPrefs.learningDataKey]))
    }

    @Test func learningRanksPositiveCountsAndPreservesTiesAndDisabledOrder() throws {
        let defaults = try isolatedDefaults()
        defaults.set(["ab": ["乙": 2, "丙": 2, "甲": 0]], forKey: QuickPrefs.learningDataKey)
        let engine = QuickEngine(dictionary: QuickDictionary(candidates: ["ab": ["甲", "乙", "丙"]]), defaults: defaults)

        #expect(engine.candidates(for: "ab") == ["甲", "乙", "丙"])
        #expect(engine.candidates(for: "ab", learning: true) == ["乙", "丙", "甲"])
    }

    private func loadJSON(_ json: String) throws -> QuickDictionary {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quick-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try QuickDictionary(url: url)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "QuickEngineTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
