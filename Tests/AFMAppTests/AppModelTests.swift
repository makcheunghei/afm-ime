import Foundation
import Testing
@testable import afm_app

private actor ReplyGate {
    private var pending: [String: CheckedContinuation<String?, Never>] = [:]
    private var arrivalWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    func reply(for key: String) async -> String? {
        await withCheckedContinuation { continuation in
            pending[key] = continuation
            let waiters = arrivalWaiters.removeValue(forKey: key) ?? []
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilPending(_ key: String) async {
        if pending[key] != nil { return }
        await withCheckedContinuation { continuation in
            arrivalWaiters[key, default: []].append(continuation)
        }
    }

    func resolve(_ key: String, with value: String?) {
        pending.removeValue(forKey: key)?.resume(returning: value)
    }
}

@Suite(.serialized)
@MainActor
struct AppModelTests {
    @Test func clearingInputCancelsPendingTranslationAndIgnoresLateReply() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = ReplyGate()
        let model = AppModel(defaults: defaults, translate: { text in
            await gate.reply(for: text)
        }, cloudProbe: { _, _, _, _ in "unused" }, loadDictionary: false)

        model.translateInput = "A"
        model.submitTranslate()
        await gate.waitUntilPending("A")
        let request = try #require(model.translateTask)
        #expect(model.translating)

        model.translateInput = ""
        #expect(!model.translating)
        #expect(request.isCancelled)
        await gate.resolve("A", with: "stale A")
        await request.value

        #expect(model.translateResult.isEmpty)
        #expect(!model.translating)
    }

    @Test func outOfOrderTranslationsKeepNewestResultAndBusyState() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = ReplyGate()
        let model = AppModel(defaults: defaults, translate: { text in
            await gate.reply(for: text)
        }, cloudProbe: { _, _, _, _ in "unused" }, loadDictionary: false)

        model.translateInput = "A"
        model.submitTranslate()
        await gate.waitUntilPending("A")
        let requestA = try #require(model.translateTask)

        model.translateInput = "B"
        model.submitTranslate()
        await gate.waitUntilPending("B")
        let requestB = try #require(model.translateTask)

        await gate.resolve("B", with: "new B")
        await requestB.value
        #expect(model.translateResult == "new B")
        #expect(!model.translating)

        model.translateInput = "C"
        model.submitTranslate()
        await gate.waitUntilPending("C")
        let requestC = try #require(model.translateTask)
        #expect(model.translating)

        await gate.resolve("A", with: "stale A")
        await requestA.value
        #expect(model.translateResult.isEmpty)
        #expect(model.translating)

        await gate.resolve("C", with: "new C")
        await requestC.value
        #expect(model.translateResult == "new C")
        #expect(!model.translating)
    }

    @Test func cloudSettingsChangeCancelsProbeAndIgnoresLateReply() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = ReplyGate()
        let model = AppModel(defaults: defaults, translate: { _ in nil }, cloudProbe: { baseURL, _, _, _ in
            await gate.reply(for: baseURL) ?? ""
        }, loadDictionary: false)

        model.cloudBaseURL = "https://old.example"
        model.testCloud()
        await gate.waitUntilPending("https://old.example")
        let request = try #require(model.cloudProbeTask)
        #expect(model.cloudTesting)

        model.cloudModel = "new-model"
        #expect(!model.cloudTesting)
        #expect(request.isCancelled)
        await gate.resolve("https://old.example", with: "stale result")
        await request.value

        #expect(model.cloudTestResult.isEmpty)
        #expect(!model.cloudTesting)
    }

    @Test func blankDictionarySearchRestoresPagedBrowse() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, translate: { _ in nil }, cloudProbe: { _, _, _, _ in "unused" })
        #expect(model.store != nil, "The shared dictionary should be available to exercise prefix search.")

        model.dictSearch = " \t\n"

        #expect(!model.isSearchingDict)
        #expect(model.dictRows.count == 100)
        #expect(model.dictPageCount > 1)
    }

    @Test func nonPinyinDictionarySearchReturnsNoRows() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, translate: { _ in nil }, cloudProbe: { _, _, _, _ in "unused" })
        #expect(model.store != nil, "The shared dictionary should be available to exercise prefix search.")

        model.dictSearch = "中文"

        #expect(model.isSearchingDict)
        #expect(model.dictRows.isEmpty)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "AFMAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
