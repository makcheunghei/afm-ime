import Foundation
import Testing
@testable import IMECore

struct QuickTranslationTests {
    @Test func clipboardInsertionConfirmsRawOnceAndInvalidatesTranslation() throws {
        let fixture = try Fixture()
        fixture.type("aa")
        let request = try #require(fixture.translation.begin())
        #expect(fixture.session.insertExternalText("測試\n文字") == QuickResult(consumed: true, commits: ["aa測試\n文字"]))
        #expect(!fixture.translation.complete("stale", for: request))
        #expect(!fixture.session.isAssociation)
        #expect(fixture.store.entries().isEmpty)
        fixture.type("a")
        _ = fixture.session.select(index: 0)
        #expect(fixture.session.isAssociation)
        #expect(fixture.session.insertExternalText("剪貼簿").commits == ["剪貼簿"])
        #expect(!fixture.session.isAssociation)
    }

    @Test func cloudConfigurationCanReadTheHelpersExplicitIMEDomain() throws {
        guard #available(macOS 27.0, *) else { return }
        let fixture = try Fixture()
        fixture.defaults.set("https://example.invalid/v1", forKey: ModelPrefs.cloudBaseURLKey)
        fixture.defaults.set("fixture-model", forKey: ModelPrefs.cloudModelKey)
        fixture.defaults.set("anthropic", forKey: ModelPrefs.cloudFormatKey)
        let config = try #require(CloudProviderModel.configured(defaults: fixture.defaults))
        #expect(config.baseURL.absoluteString == "https://example.invalid/v1")
        #expect(config.modelName == "fixture-model")
        #expect(config.wireFormat == "anthropic")
    }

    @Test func cancellingRestoresExactPageHighlightAndCandidateOrder() throws {
        let fixture = try Fixture()
        fixture.type("aa")
        _ = fixture.session.handle(.nextPage)
        _ = fixture.session.handle(.nextCandidate)
        let original = fixture.session.candidates
        let selected = fixture.session.selectedIndex
        let generation = fixture.session.generation
        let request = try #require(fixture.translation.begin())
        #expect(request.source == original[selected])
        #expect(fixture.translation.complete("translated", for: request))
        #expect(fixture.handle(.escape) == QuickResult(consumed: true))
        #expect(fixture.session.pageStart == 9)
        #expect(fixture.session.selectedIndex == selected)
        #expect(fixture.session.candidates == original)
        #expect(fixture.session.generation == generation)
        #expect(fixture.session.rawText == "aa")
    }

    @Test func englishSourceAndEnterKeepOriginalCase() throws {
        let fixture = try Fixture()
        fixture.type("Gmail")
        let request = try #require(fixture.translation.begin())
        #expect(request.source == "Gmail")
        #expect(fixture.translation.complete("郵件", for: request))
        #expect(fixture.handle(.enter) == QuickResult(consumed: true, commits: ["Gmail"]))
        #expect(!fixture.translation.isActive)
        #expect(fixture.session.rawText.isEmpty)
    }

    @Test func oneAndClickCommitOnlyTranslationWithoutLearningOrAssociations() throws {
        for byKey in [true, false] {
            let fixture = try Fixture()
            fixture.type("a")
            let request = try #require(fixture.translation.begin())
            #expect(fixture.translation.complete("the sun", for: request))
            let result = byKey ? fixture.handle(.digit(1, shifted: false)) : fixture.translation.selectTranslation()
            #expect(result == QuickResult(consumed: true, commits: ["the sun"]))
            #expect(!fixture.session.isAssociation)
            #expect(fixture.session.rawText.isEmpty)
            #expect(fixture.store.entries().isEmpty)
        }
    }

    @Test func spaceAndOtherNumbersNeverSelectUnderlyingCandidates() throws {
        let fixture = try Fixture()
        fixture.type("aa")
        let request = try #require(fixture.translation.begin())
        for ready in [false, true] {
            if ready { #expect(fixture.translation.complete("result", for: request)) }
            #expect(fixture.handle(.space) == QuickResult(consumed: true))
            for number in 2...9 {
                #expect(fixture.handle(.digit(number, shifted: false)) == QuickResult(consumed: true))
            }
            #expect(fixture.session.rawText == "aa")
            #expect(fixture.session.pageStart == 0)
        }
    }

    @Test func loadingAndFailureCannotBeCommitted() throws {
        let fixture = try Fixture()
        fixture.type("a")
        let request = try #require(fixture.translation.begin())
        #expect(fixture.handle(.digit(1, shifted: false)).commits.isEmpty)
        #expect(fixture.translation.selectTranslation().commits.isEmpty)
        #expect(fixture.translation.complete(nil, for: request))
        #expect(fixture.translation.phase == .failed)
        #expect(fixture.handle(.digit(1, shifted: false)).commits.isEmpty)
        #expect(fixture.handle(.space).commits.isEmpty)
        #expect(fixture.session.rawText == "a")
    }

    @Test func newInputAndNavigationCancelThenUseOriginalQuickRules() throws {
        let fixture = try Fixture()
        fixture.type("aa")
        _ = fixture.translation.begin()
        _ = fixture.handle(.nextPage)
        #expect(!fixture.translation.isActive)
        #expect(fixture.session.pageStart == 9)
        _ = fixture.translation.begin()
        _ = fixture.handle(.backspace)
        #expect(fixture.session.rawText == "a")
        _ = fixture.translation.begin()
        _ = fixture.handle(.letter("b"))
        #expect(fixture.session.rawText == "ab")
        _ = fixture.translation.begin()
        #expect(fixture.handle(.separator(".")) == QuickResult(consumed: true, commits: ["ab."]))
        #expect(!fixture.translation.isActive)
    }

    @Test func cancelledAndOutOfOrderRepliesCannotReplaceNewestRequest() throws {
        let fixture = try Fixture()
        fixture.type("aa")
        let first = try #require(fixture.translation.begin())
        fixture.translation.cancel()
        let second = try #require(fixture.translation.begin())
        #expect(!fixture.translation.complete("old", for: first))
        #expect(fixture.translation.phase == .loading)
        #expect(fixture.translation.complete("new", for: second))
        #expect(!fixture.translation.complete("late old", for: first))
        #expect(fixture.translation.phase == .ready("new"))
    }

    @Test func changedUnderlyingCompositionInvalidatesReplyAndClick() throws {
        let fixture = try Fixture()
        fixture.type("a")
        let request = try #require(fixture.translation.begin())
        _ = fixture.session.handle(.letter("a"))
        #expect(!fixture.translation.complete("stale", for: request))
        let current = try #require(fixture.translation.begin())
        #expect(fixture.translation.complete("valid before reset", for: current))
        fixture.session.reset()
        #expect(fixture.translation.selectTranslation().commits.isEmpty)
        #expect(!fixture.translation.isActive)
    }

    @Test func idleAndAssociationCannotStartTranslation() throws {
        let fixture = try Fixture()
        #expect(fixture.translation.begin() == nil)
        fixture.type("a")
        _ = fixture.session.select(index: 0)
        #expect(fixture.session.isAssociation)
        #expect(fixture.translation.begin() == nil)
    }

    @Test func quickTranslationCloudPermissionIsIndependentAndDefaultsOff() throws {
        let fixture = try Fixture()
        let defaults = fixture.defaults
        defaults.set(true, forKey: ModelPrefs.cloudEnabledKey)
        defaults.set(true, forKey: QuickPrefs.cloudKey)
        defaults.set(true, forKey: QuickPrefs.aiKey)
        let quick = FMReranker.translationPlan(text: "hello", mode: .quick, defaults: defaults)
        #expect(!quick.allowCloud)
        #expect(quick.instructions == FMReranker.defaultQuickTranslateZHInstructions)
        #expect(FMReranker.translationPlan(text: "hello", mode: .pinyin, defaults: defaults).allowCloud)
        defaults.set(true, forKey: QuickPrefs.translationCloudKey)
        defaults.set(false, forKey: QuickPrefs.aiKey)
        #expect(FMReranker.translationPlan(text: "hello", mode: .quick, defaults: defaults).allowCloud)
        #expect(!FMReranker.translationPlan(text: "hello", mode: .quick, allowCloud: false, defaults: defaults).allowCloud)
    }

    @Test func translationPromptsAndUnicodeDirectionAreModeSpecific() throws {
        let fixture = try Fixture()
        fixture.defaults.set("quick custom", forKey: ModelPrefs.promptQuickTranslateENKey)
        fixture.defaults.set("pinyin custom", forKey: ModelPrefs.promptTranslateENKey)
        for word in ["你", "𠮷", "𰻞"] {
            #expect(FMReranker.containsChinese(word))
            let quick = FMReranker.translationPlan(text: word, mode: .quick, defaults: fixture.defaults)
            #expect(quick.toEnglish && quick.instructions == "quick custom")
            #expect(FMReranker.translationPlan(text: word, mode: .pinyin, defaults: fixture.defaults).instructions == "pinyin custom")
        }
        #expect(!FMReranker.containsChinese("Gmail 123"))
    }

    @Test func modelSnapshotChangesWithCloudPermissionPromptsAndCredentials() throws {
        let fixture = try Fixture()
        for key in [QuickPrefs.translationCloudKey, ModelPrefs.promptQuickTranslateZHKey,
                    ModelPrefs.cloudBaseURLKey, ModelPrefs.cloudAPIKeyKey, ModelPrefs.cloudModelKey] {
            let before = ModelPrefs.requestConfiguration(defaults: fixture.defaults)
            fixture.defaults.set("test-only", forKey: key)
            #expect(before != ModelPrefs.requestConfiguration(defaults: fixture.defaults))
        }
    }

    private final class Fixture {
        let suite = "QuickTranslationTests.\(UUID().uuidString)"
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults: UserDefaults
        let store: QuickLearningStore
        let session: QuickSession
        let translation: QuickTranslationSession

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            store = QuickLearningStore(defaults: defaults, lockURL: folder.appendingPathComponent("lock"))
            let dictionary = QuickDictionary(candidates: ["a": ["日"], "aa": (1...18).map { "候\($0)" }],
                                             associations: ["日": ["子"]])
            session = QuickSession(engine: QuickEngine(dictionary: dictionary, defaults: defaults, learningStore: store), learning: true)
            translation = QuickTranslationSession(session: session)
        }
        deinit {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        func type(_ text: String) { text.forEach { _ = session.handle(.letter($0)) } }
        func handle(_ key: QuickKey) -> QuickResult { translation.handle(key) ?? session.handle(key) }
    }
}
