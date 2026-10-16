import Foundation
import Testing
@testable import afm_app
import IMECore

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
        model.settingsMode = .pinyin
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
        model.settingsMode = .pinyin
        model.dictSearch = "中文"

        #expect(model.isSearchingDict)
        #expect(model.dictRows.isEmpty)
    }

    @Test func settingsModePersistsAndRestoresIndependentQuickDraftAndSearch() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let dictionary = QuickDictionary(candidates: ["aa": ["中"]], roots: ["a": "日"])
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AFMAppTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("quick-learning.lock")
        let learning = QuickLearningStore(defaults: defaults, lockURL: lockURL)
        let model = AppModel(defaults: defaults, translate: { _ in nil },
                             cloudProbe: { _, _, _, _ in "unused" }, loadDictionary: false,
                             dictionary: dictionary, learningStore: learning)

        model.promptQuickRerank = "速成草稿"
        model.quickDictSearch = "aa"
        model.quickUserSearch = "中"
        model.setSettingsMode(.pinyin)
        model.promptRerank = "拼音草稿"
        model.dictSearch = "ni"
        model.setSettingsMode(.quick)

        #expect(model.settingsMode == .quick)
        #expect(model.promptQuickRerank == "速成草稿")
        #expect(model.quickDictSearch == "aa")
        #expect(model.quickUserSearch == "中")
        #expect(defaults.string(forKey: "AFMSettingsMode") == "quick")
        #expect(model.promptRerank == "拼音草稿")
        #expect(model.dictSearch == "ni")

        model.applyPrompts()
        #expect(defaults.string(forKey: ModelPrefs.promptQuickRerankKey) == "速成草稿")
        #expect(defaults.object(forKey: ModelPrefs.promptRerankKey) == nil)
    }

    @Test func quickDictionarySearchAndSectionAreModeScoped() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let dictionary = QuickDictionary(candidates: ["aa": ["中", "忠"], "ab": ["人"]],
                                         associations: ["aa": ["中國"]], roots: ["a": "日", "b": "月"])
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AFMAppTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("quick-learning.lock")
        let model = AppModel(defaults: defaults, translate: { _ in nil },
                             cloudProbe: { _, _, _, _ in "unused" }, loadDictionary: false,
                             dictionary: dictionary,
                             learningStore: QuickLearningStore(defaults: defaults, lockURL: lockURL))

        model.quickDictSearch = "aa"
        #expect(model.quickDictTotalCount == 2)
        model.quickDictSection = .associations
        #expect(model.quickDictTotalCount == 1)
        #expect(model.quickDictRows.first?.text == "中國")
    }

    @Test func switchingModeCancelsPendingTranslationAndIgnoresLateReply() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let gate = ReplyGate()
        let model = AppModel(defaults: defaults, translateModeAware: { text, _, _ in
            await gate.reply(for: text)
        }, cloudProbe: { _, _, _, _ in "unused" }, loadDictionary: false,
        dictionary: QuickDictionary(candidates: [:]),
        learningStore: QuickLearningStore(defaults: defaults,
            lockURL: FileManager.default.temporaryDirectory.appendingPathComponent("AFMAppTests-\(UUID().uuidString)/quick-learning.lock")))

        model.translateInput = "hello"
        model.submitTranslate()
        await gate.waitUntilPending("hello")
        let request = try #require(model.translateTask)
        model.setSettingsMode(.pinyin)
        #expect(request.isCancelled)
        await gate.resolve("hello", with: "stale")
        await request.value
        #expect(model.translateResult.isEmpty)
        #expect(!model.translating)
    }

    @Test func clearingQuickLearningDoesNotChangePinyinLearningOrEnableLearning() throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AFMAppTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("quick-learning.lock")
        let learning = QuickLearningStore(defaults: defaults, lockURL: lockURL)
        let dictionary = QuickDictionary(candidates: ["aa": ["中"]], roots: ["a": "日"])
        _ = learning.record(code: "aa", text: "中")
        defaults.set(["拼音詞": 4], forKey: "AFMUserFreq")
        let model = AppModel(defaults: defaults, translate: { _ in nil },
                             cloudProbe: { _, _, _, _ in "unused" }, loadDictionary: false,
                             dictionary: dictionary, learningStore: learning)

        model.clearQuickUsers()

        #expect(learning.entries().isEmpty)
        #expect(defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] == ["拼音詞": 4])
        #expect(!defaults.bool(forKey: QuickPrefs.learningKey))
    }

    @Test func reservedQuickHotkeyResolvesToItsDefault() {
        #expect(AppModel.resolvedHotkeyCode(stored: 39, fallback: 3) == 3)
        #expect(AppModel.resolvedHotkeyCode(stored: 9, fallback: 3) == 9)
        #expect(AppModel.resolvedHotkeyCode(stored: nil, fallback: 3) == 3)
    }

    @Test func candidateLayoutPersistsWithoutChangingTypingOptionsOrCancellingTranslation() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("future-unknown-layout", forKey: QuickPrefs.candidateLayoutKey)
        let gate = ReplyGate()
        let model = AppModel(defaults: defaults, translate: { text in await gate.reply(for: text) }, loadDictionary: false)
        #expect(model.quickCandidateLayout == .vertical)
        model.translateInput = "hello"
        model.submitTranslate()
        await gate.waitUntilPending("hello")
        let task = try #require(model.translateTask)
        let before = defaults.dictionaryRepresentation()
        model.quickCandidateLayout = .horizontal
        #expect(!task.isCancelled)
        #expect(QuickPrefs.candidateLayout(defaults: defaults) == .horizontal)
        for (key, value) in before where key != QuickPrefs.candidateLayoutKey {
            #expect(NSDictionary(dictionary: [key: value]) == NSDictionary(dictionary: [key: defaults.object(forKey: key)!]))
        }
        let reopened = AppModel(defaults: defaults, translate: { _ in nil }, loadDictionary: false)
        #expect(reopened.quickCandidateLayout == .horizontal)
        await gate.resolve("hello", with: "你好")
        await task.value
        #expect(model.translateResult == "你好")
    }

    @Test func firstModeSwitchKeepsExistingCustomPromptsAndResetOnlyAffectsCurrentMode() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("stored pinyin", forKey: ModelPrefs.promptRerankKey)
        defaults.set("stored quick", forKey: ModelPrefs.promptQuickRerankKey)
        let model = AppModel(defaults: defaults, translate: { _ in nil }, loadDictionary: false)
        #expect(model.settingsMode == .quick)
        model.settingsMode = .pinyin
        #expect(model.promptRerank == "stored pinyin")
        model.settingsMode = .quick
        #expect(model.promptQuickRerank == "stored quick")
        model.resetPrompts()
        #expect(defaults.string(forKey: ModelPrefs.promptRerankKey) == "stored pinyin")
        #expect(defaults.object(forKey: ModelPrefs.promptQuickRerankKey) == nil)
        model.settingsMode = .pinyin
        let reopened = AppModel(defaults: defaults, translate: { _ in nil }, loadDictionary: false)
        #expect(reopened.settingsMode == .pinyin)
    }

    @Test func quickSearchPaginatesAllResultsAndBrowsingCharsetDoesNotChangeTyping() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let candidates = (0..<205).map { "字\($0)" }
        let model = AppModel(defaults: defaults, translate: { _ in nil }, loadDictionary: false,
            dictionary: QuickDictionary(candidates: ["aa": candidates],
                                        fullCandidates: ["aa": candidates + ["𠮷"]],
                                        associations: ["你": ["們", "好"]]))
        model.quickDictSearch = "a"
        #expect(model.quickDictPageCount == 3)
        #expect(model.quickDictRows.count == 100)
        model.quickDictPage = 2
        #expect(model.quickDictRows.map(\.text) == Array(candidates.suffix(5)))
        model.settingsMode = .pinyin
        model.settingsMode = .quick
        #expect(model.quickDictPage == 2)
        model.quickDictFullCharset = true
        #expect(model.quickDictPage == 0)
        #expect(!model.quickFullCharset)
        #expect(defaults.object(forKey: QuickPrefs.fullCharsetKey) == nil)
        model.quickDictSearch = "𠮷"
        #expect(model.quickDictRows.map(\.text) == ["𠮷"])
        model.quickDictSection = .associations
        model.quickDictSearch = "你"
        #expect(model.quickDictRows.map(\.text) == ["們", "好"])
        model.quickDictPage = Int.max
        #expect(model.quickDictPage == 0)
        #expect(model.quickDictRows.count == 2)
    }

    @Test func translationPageUsesIndependentCloudPermissionAndCancelsOnConfigChange() async throws {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: ModelPrefs.cloudEnabledKey)
        defaults.set(true, forKey: QuickPrefs.cloudKey)
        let gate = ReplyGate()
        let model = AppModel(defaults: defaults, translateModeAware: { text, mode, cloud in
            await gate.reply(for: "\(mode.rawValue):\(cloud):\(text)")
        }, loadDictionary: false)
        model.translateInput = "hello"
        model.submitTranslate()
        await gate.waitUntilPending("quick:false:hello")
        let first = try #require(model.translateTask)
        model.quickTranslationCloud = true
        #expect(first.isCancelled)
        await gate.resolve("quick:false:hello", with: "outdated")
        await first.value
        #expect(model.translateResult.isEmpty)
        model.submitTranslate()
        await gate.waitUntilPending("quick:true:hello")
        let second = try #require(model.translateTask)
        model.cloudModel = "new model"
        #expect(second.isCancelled)
        await gate.resolve("quick:true:hello", with: "outdated cloud")
        await second.value
        #expect(model.translateResult.isEmpty)
    }

    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "AFMAppTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
