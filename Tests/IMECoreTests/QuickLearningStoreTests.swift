import Foundation
import Testing
@testable import IMECore

private final class QuickLearningTestBundleAnchor: NSObject {}

struct QuickLearningStoreTests {
    @Test func readingAndPreviewingDoNotCreateOrRewriteLearningData() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = QuickLearningStore(defaults: defaults, lockURL: lockURL())
        #expect(store.entries().isEmpty)
        #expect(store.counts(for: "a").isEmpty)
        #expect(defaults.object(forKey: QuickPrefs.learningDataKey) == nil)
        defaults.set(["bad-key": ["keep until explicit mutation": 4]], forKey: QuickPrefs.learningDataKey)
        let before = defaults.dictionary(forKey: QuickPrefs.learningDataKey)! as NSDictionary
        _ = store.entries()
        #expect(defaults.dictionary(forKey: QuickPrefs.learningDataKey)! as NSDictionary == before)
    }

    @Test func ordersEntriesAndSaturatesAtIntMax() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = QuickLearningStore(defaults: defaults, lockURL: lockURL())
        defaults.set(["ab": ["甲": Int.max, "乙": 4], "a": ["丙": 4]], forKey: QuickPrefs.learningDataKey)

        #expect(store.entries().map(\.id) == ["ab\u{1F}甲", "a\u{1F}丙", "ab\u{1F}乙"])
        #expect(store.record(code: "ab", text: "甲"))
        #expect(store.counts(for: "ab")["甲"] == Int.max)
    }

    @Test func importValidatesDocumentAndEntriesWithoutChangingOtherPreferences() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = QuickLearningStore(defaults: defaults, lockURL: lockURL())
        let dict = QuickDictionary(candidates: ["a": ["字", "𠮷"]], fullCandidates: ["b": ["擴展字"]])
        defaults.set(false, forKey: QuickPrefs.learningKey)
        defaults.set(["a": ["字": 3]], forKey: QuickPrefs.learningDataKey)
        let json = #"{"version":1,"mode":"quick","selections":[{"code":"a","text":"字","count":7},{"code":"a","text":"字","count":5},{"code":"a","text":"𠮷","count":9223372036854775807},{"code":"b","text":"擴展字","count":2},{"code":"a","text":"未知","count":8},{"code":"A","text":"字","count":1},{"code":"a","text":"字","count":true},{"code":"a","text":"字","count":1.5},{"code":"a","text":"字","count":9223372036854775808}] }"#

        let result = try store.importJSON(Data(json.utf8), dictionary: dict)
        #expect(result == QuickLearningImportResult(added: 2, updated: 1, skipped: 6))
        #expect(store.counts(for: "a")["字"] == 7)
        #expect(store.counts(for: "a")["𠮷"] == Int.max)
        #expect(store.counts(for: "b")["擴展字"] == 2)
        #expect(defaults.bool(forKey: QuickPrefs.learningKey) == false)
    }

    @Test func malformedTopLevelNeverWritesAndDisabledEngineDoesNotRecord() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = QuickLearningStore(defaults: defaults, lockURL: lockURL())
        let dict = QuickDictionary(candidates: ["a": ["字"]])
        defaults.set(["a": ["字": 1]], forKey: QuickPrefs.learningDataKey)
        for json in [#"{"version":true,"mode":"quick","selections":[]}"#, #"{"version":1,"mode":"pinyin","selections":[]}"#, #"{"version":1,"mode":"quick","selections":{}}"#] {
            #expect(throws: (any Error).self) { try store.importJSON(Data(json.utf8), dictionary: dict) }
            #expect(store.counts(for: "a")["字"] == 1)
        }
        QuickEngine(dictionary: dict, defaults: defaults, learningStore: store).recordSelection(code: "a", text: "字", enabled: false)
        #expect(store.counts(for: "a")["字"] == 1)
    }

    @Test func storesSharingLockDoNotLoseConcurrentIncrements() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let lock = lockURL()
        let stores = (0..<4).map { _ in QuickLearningStore(defaults: defaults, lockURL: lock) }
        let group = DispatchGroup()
        for store in stores {
            group.enter()
            DispatchQueue.global().async {
                for _ in 0..<50 { #expect(store.record(code: "a", text: "字")) }
                group.leave()
            }
        }
        #expect(group.wait(timeout: .now() + 20) == .success)
        #expect(stores[0].counts(for: "a")["字"] == 200)
    }

    @Test func lockOpenFailureFailsClosed() throws {
        let (defaults, name) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let parentFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("file".utf8).write(to: parentFile)
        defer { try? FileManager.default.removeItem(at: parentFile) }
        let store = QuickLearningStore(defaults: defaults, lockURL: parentFile.appendingPathComponent("lock"))

        #expect(!store.record(code: "a", text: "字"))
        #expect(store.entries().isEmpty)
        #expect(defaults.object(forKey: QuickPrefs.learningDataKey) == nil)
    }

    @Test func separateProcessesMergeSelectionsAlongsideImportAndDeletion() throws {
        let (defaults, name) = try isolatedDefaults()
        let lock = lockURL()
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: lock)
        }
        let store = QuickLearningStore(defaults: defaults, lockURL: lock)
        #expect(store.record(code: "b", text: "舊"))
        let processes = try (0..<2).map { _ -> Process in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            var arguments = ["--testing-library", "swift-testing", "--filter", "QuickLearningStoreTests/crossProcessWorker"]
            // 新版 SwiftPM 以 helper 載入 Mach-O test bundle；子程序也須載入同一份。
            if let index = CommandLine.arguments.firstIndex(of: "--test-bundle-path"),
               CommandLine.arguments.indices.contains(index + 1) {
                arguments = ["--test-bundle-path", CommandLine.arguments[index + 1]] + arguments
            } else if process.executableURL?.lastPathComponent == "swiftpm-testing-helper" {
                let bundleExecutable = try #require(Bundle(for: QuickLearningTestBundleAnchor.self).executableURL)
                arguments = ["--test-bundle-path", bundleExecutable.path] + arguments
            }
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["AFM_QUICK_TEST_DOMAIN"] = name
            environment["AFM_QUICK_TEST_LOCK"] = lock.path
            process.environment = environment
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return process
        }
        #expect(store.remove(code: "b", text: "舊"))
        let data = Data(#"{"version":1,"mode":"quick","selections":[{"code":"c","text":"新","count":9}]}"#.utf8)
        _ = try store.importJSON(data, dictionary: QuickDictionary(candidates: ["c": ["新"]]))
        let deadline = Date().addingTimeInterval(20)
        while processes.contains(where: \.isRunning), Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        for process in processes {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
        }
        #expect(store.counts(for: "a")["字"] == 100)
        #expect(store.counts(for: "b").isEmpty)
        #expect(store.counts(for: "c")["新"] == 9)
    }

    /// 子程序只操作父測試指定的隔離 suite，不觸及正式輸入法。
    @Test func crossProcessWorker() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let domain = environment["AFM_QUICK_TEST_DOMAIN"] else { return }
        #expect(domain.hasPrefix("QuickLearningStoreTests."))
        guard domain.hasPrefix("QuickLearningStoreTests."), let path = environment["AFM_QUICK_TEST_LOCK"] else { return }
        let defaults = try #require(UserDefaults(suiteName: domain))
        let store = QuickLearningStore(defaults: defaults, lockURL: URL(fileURLWithPath: path))
        for _ in 0..<50 { #expect(store.record(code: "a", text: "字")) }
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let name = "QuickLearningStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    private func lockURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("quick-learning-\(UUID().uuidString).lock")
    }
}
