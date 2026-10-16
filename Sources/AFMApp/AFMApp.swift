import AppKit
import SwiftUI
import UniformTypeIdentifiers
import IMECore

// AFM輸入法設定中心：系統維護、詞庫及模型設定。安裝／更新由 .pkg 管理。
// 写设置走 IME 域(UserDefaults(suiteName: moe.bemly.inputmethod.AfmIME) = 输入法进程的
// UserDefaults.standard 域),输入法每次按键现读现判,改动即时生效。
// 键名与 IMECore/UserPrefs.swift 逐字一致——两边都要改。
// 注意: 禁用 @State/@StateObject 等宏包装器(保持 CLT 回退构建可用),用 ObservableObject 家族。

private let imeDomain = "moe.bemly.inputmethod.AfmIME"

// MARK: - 数据模型

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    typealias TranslateOperation = (String) async -> String?
    typealias ModeAwareTranslateOperation = (String, InputMethodMode, Bool) async -> String?
    typealias CloudProbeOperation = (String, String, String, String) async -> String

    private let defaults: UserDefaults
    private let navigationDefaults: UserDefaults
    private let broadcastsConfigurationChanges: Bool
    private let modeAwareTranslateOperation: ModeAwareTranslateOperation
    private let cloudProbeOperation: CloudProbeOperation
    private(set) var translateTask: Task<Void, Never>?
    private(set) var cloudProbeTask: Task<Void, Never>?

    enum Tab: String, Identifiable, CaseIterable {
        case settings, dict, user, translate, model, test, maintenance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .maintenance: return "系統維護"
            case .dict: return "詞庫"
            case .user: return "個人詞語"
            case .translate: return "翻譯"
            case .model: return "AI 模型"
            case .test: return "實驗功能"
            case .settings: return "輸入設定"
            }
        }
        var icon: String {
            switch self {
            case .maintenance: return "wrench.and.screwdriver"
            case .dict: return "character.book.closed"
            case .user: return "person.text.rectangle"
            case .translate: return "translate"
            case .model: return "cpu"
            case .test: return "flask"
            case .settings: return "keyboard"
            }
        }
    }

    @Published var tab: Tab = .settings {
        didSet {
            navigationDefaults.set(tab.rawValue, forKey: "AFMSettingsLastPane")
            if tab != .settings { stopRecording() }
        }
    }
    struct ModeSnapshot {
        var translateInput = ""
        var translateResult = ""
    }
    @Published var settingsMode: InputSettingsMode = .quick {
        didSet {
            guard settingsMode != oldValue else { return }
            navigationDefaults.set(settingsMode.rawValue, forKey: "AFMSettingsMode")
            saveModeSnapshot(oldValue)
            cancelTranslation()
            restoreModeSnapshot(settingsMode)
            reloadDict()
            reloadUserRows()
        }
    }
    private var modeSnapshots: [InputSettingsMode: ModeSnapshot] = [:]
    let preview = InputPreviewModel()

    // 系統維護；不複製或刪除 App，不更改詞庫及模型偏好。
    @Published var status = IMEInstaller.statusSummary()
    @Published var maintenanceLog = ""
    @Published var maintenanceBusy = false

    // 词库
    @Published var dictSearch = "" { didSet { dictPage = 0; reloadDict() } }
    @Published var dictRows: [DictStore.RecordInfo] = []
    @Published var dictPage = 0 { didSet { reloadDict() } }
    @Published var dictStats = ""
    private(set) var store: DictStore?
    private(set) var quickDictionary: QuickDictionary?
    private var quickDictionaryBrowser: QuickDictionaryBrowser?
    private(set) var quickLearningStore: QuickLearningStore?
    var previewDefaults: UserDefaults { defaults }
    @Published var quickDictSection: QuickDictionarySection = .codes {
        didSet { if quickDictSection != oldValue { quickDictPage = 0; reloadQuickDict() } }
    }
    @Published var quickDictFullCharset = false {
        didSet { if quickDictFullCharset != oldValue { quickDictPage = 0; reloadQuickDict() } }
    }
    @Published var quickDictSearch = "" {
        didSet { if quickDictSearch != oldValue { quickDictPage = 0; reloadQuickDict() } }
    }
    @Published var quickDictPage = 0 {
        didSet { if quickDictPage != oldValue { reloadQuickDict() } }
    }
    @Published var quickDictRows: [QuickDictionaryRow] = []
    @Published var quickDictTotalCount = 0
    @Published var quickDictPageCount = 1
    @Published var quickDictUnavailable = false

    // 用户词
    struct UserRow: Identifiable {
        let id: String
        let word: String
        let pinyin: String
        let count: Int
        let score: Int
        let boost: Double
    }
    struct QuickUserRow: Identifiable {
        let id: String
        let code: String
        let roots: String
        let text: String
        let count: Int
    }
    @Published var userRows: [UserRow] = []
    @Published var quickUserRows: [QuickUserRow] = []
    @Published var userSearch = ""
    @Published var quickUserSearch = "" { didSet { reloadUserRows() } }
    @Published var userMessage = ""   // 导入结果等一次性提示

    // 设置(键名 = UserPrefs)
    @Published var fuzzy: Bool { didSet { write("AFMFuzzyPinyin", fuzzy) } }
    @Published var fullWidthPunct: Bool { didSet { write("AFMFullWidthPunct", fullWidthPunct) } }
    @Published var fmEnhance: Bool { didSet { write("AFMFMEnhance", fmEnhance) } }
    @Published var userFreqEnabled: Bool { didSet { write("AFMUserFreqEnabled", userFreqEnabled) } }
    @Published var quickFullCharset: Bool { didSet { write(QuickPrefs.fullCharsetKey, quickFullCharset) } }
    @Published var quickLearning: Bool { didSet { write(QuickPrefs.learningKey, quickLearning) } }
    @Published var quickAI: Bool { didSet { write(QuickPrefs.aiKey, quickAI) } }
    @Published var quickCloud: Bool { didSet { write(QuickPrefs.cloudKey, quickCloud) } }
    @Published var quickTranslationCloud: Bool {
        didSet {
            guard quickTranslationCloud != oldValue else { return }
            cancelTranslation(clearResult: true)
            defaults.set(quickTranslationCloud, forKey: QuickPrefs.translationCloudKey)
            defaults.synchronize()
            postConfigurationChange()
        }
    }
    @Published var fontSize: Double { didSet { write("AFMCandidateFontSize", Int(fontSize)) } }
    // 测试:固定透镜拖拽(droplet-relative-motion 支线移植)——键名与 UserPrefs.dropletFixedLens 逐字一致
    @Published var dropletFixedLens: Bool { didSet { write("AFMDropletFixedLens", dropletFixedLens) } }
    @Published var confirmPrepareRemoval = false
    @Published var confirmClear = false
    @Published var confirmQuickClear = false
    @Published var confirmQuickDelete: QuickUserRow?

    // 快捷键(kb35): IME handle 现读现判,defaults 只存 keyCode(+显示字符免查键码表);
    // 修饰固定为 ⌃(IME 拦截层只拦 ⌃ 组合),录制时强制校验
    struct HotkeyRow: Identifiable {
        let id: String        // defaults 键(AFMHotkey…)
        let title: String
        let display: String   // 如 "⌃V"
        let custom: Bool      // 是否已被用户改过
    }
    static let hotkeySlots: [(key: String, displayKey: String, fallback: Int, fallbackDisplay: String, title: String)] = [
        ("AFMHotkeyClipboard", "AFMHotkeyClipboardDisplay", 9, "V", "剪貼簿記錄"),
        ("AFMHotkeyTranslate", "AFMHotkeyTranslateDisplay", 3, "F", "行內翻譯"),
        ("AFMHotkeySettings", "AFMHotkeySettingsDisplay", 1, "S", "設定中心"),
    ]
    @Published var hotkeyRows: [HotkeyRow] = []
    @Published var recordingHotkey: String? = nil   // 正在录制的槽(nil=未在录)
    @Published var hotkeyHint = ""
    private var hotkeyMonitor: Any?

    // 模型(kb36):云端模型(Provider 协议接入)+ 端侧 FM 提示词;键名 = IMECore.ModelPrefs 常量(单一来源)
    static let cloudPresets: [(id: String, name: String, baseURL: String, format: String, model: String)] = [
        ("openai", "OpenAI", "https://api.openai.com/v1", "openai", "gpt-4o-mini"),
        ("anthropic", "Anthropic", "https://api.anthropic.com", "anthropic", "claude-sonnet-4-5"),
        ("deepseek", "DeepSeek", "https://api.deepseek.com/v1", "openai", "deepseek-chat"),
        ("kimi", "Kimi（月之暗面）", "https://api.moonshot.cn/v1", "openai", "moonshot-v1-8k"),
        ("zhipu", "智譜 GLM", "https://open.bigmodel.cn/api/paas/v4", "openai", "glm-4-flash"),
        ("qwen", "通義千問", "https://dashscope.aliyuncs.com/compatible-mode/v1", "openai", "qwen-plus"),
        ("ark", "豆包（火山方舟）", "https://ark.cn-beijing.volces.com/api/v3", "openai", ""),
        ("ollama", "Ollama（本機）", "http://127.0.0.1:11434/v1", "openai", ""),
        ("custom", "自訂", "", "openai", ""),
    ]
    @Published var cloudEnabled: Bool { didSet { write(ModelPrefs.cloudEnabledKey, cloudEnabled) } }
    @Published var cloudProvider: String {
        didSet { guard cloudProvider != oldValue else { return }; cancelTranslation(clearResult: true); writeConfiguration(ModelPrefs.cloudProviderKey, cloudProvider); invalidateCloudTest(); applyCloudPreset() }
    }
    @Published var cloudBaseURL: String {
        didSet { guard cloudBaseURL != oldValue else { return }; cancelTranslation(clearResult: true); writeConfiguration(ModelPrefs.cloudBaseURLKey, cloudBaseURL); invalidateCloudTest() }
    }
    @Published var cloudAPIKey: String {
        didSet { guard cloudAPIKey != oldValue else { return }; cancelTranslation(clearResult: true); writeConfiguration(ModelPrefs.cloudAPIKeyKey, cloudAPIKey); invalidateCloudTest() }
    }
    @Published var cloudModel: String {
        didSet { guard cloudModel != oldValue else { return }; cancelTranslation(clearResult: true); writeConfiguration(ModelPrefs.cloudModelKey, cloudModel); invalidateCloudTest() }
    }
    @Published var cloudFormat: String {
        didSet { guard cloudFormat != oldValue else { return }; cancelTranslation(clearResult: true); writeConfiguration(ModelPrefs.cloudFormatKey, cloudFormat); invalidateCloudTest() }
    }
    // 提示词 = 草稿-应用模式(kb36.1):编辑框预填当前生效值(覆盖 ?? 内置默认),编辑不落盘,
    // 点「应用」才写入(与内置一致的草稿会清掉覆盖键,保证内置更新可跟随);引擎/helper 现读现判
    @Published var promptRerank = ""
    @Published var promptSentence = ""
    @Published var promptTranslateEN = ""
    @Published var promptTranslateZH = ""
    @Published var promptQuickRerank = ""
    @Published var promptQuickTranslateEN = ""
    @Published var promptQuickTranslateZH = ""
    @Published var promptAppliedHint = ""
    @Published var cloudTestResult = ""
    @Published var cloudTesting = false
    private var cloudTestGeneration = 0

    /// 选预设 → 自动填接口地址/格式/模型名(自訂不覆盖已填内容)
    private func applyCloudPreset() {
        guard let p = Self.cloudPresets.first(where: { $0.id == cloudProvider }), !p.baseURL.isEmpty else { return }
        cloudBaseURL = p.baseURL
        cloudFormat = p.format
        if !p.model.isEmpty { cloudModel = p.model }
    }

    private func invalidateCloudTest() {
        cloudTestGeneration &+= 1
        cloudProbeTask?.cancel()
        cloudProbeTask = nil
        cloudTesting = false
        cloudTestResult = ""
    }

    func testCloud() {
        guard !cloudTesting else { return }
        cloudTesting = true
        cloudTestResult = ""
        cloudTestGeneration &+= 1
        let generation = cloudTestGeneration
        let baseURL = cloudBaseURL
        let apiKey = cloudAPIKey
        let modelName = cloudModel
        let wireFormat = cloudFormat
        let operation = cloudProbeOperation
        cloudProbeTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let out = await operation(baseURL, apiKey, modelName, wireFormat)
            guard !Task.isCancelled, let self,
                  generation == self.cloudTestGeneration else { return }
            self.cloudTesting = false
            self.cloudTestResult = out
            self.cloudProbeTask = nil
        }
    }

    /// 应用提示词草稿:与内置默认一致的段落清掉覆盖键(跟随内置更新),其余写入
    func applyPrompts() {
        let d = defaults
        let pairs: [(key: String, value: String, def: String)] = settingsMode == .quick ? [
            (ModelPrefs.promptQuickRerankKey, promptQuickRerank, FMReranker.defaultQuickRerankInstructions),
            (ModelPrefs.promptQuickTranslateENKey, promptQuickTranslateEN, FMReranker.defaultQuickTranslateENInstructions),
            (ModelPrefs.promptQuickTranslateZHKey, promptQuickTranslateZH, FMReranker.defaultQuickTranslateZHInstructions),
        ] : [
            (ModelPrefs.promptRerankKey, promptRerank, FMReranker.defaultRerankInstructions),
            (ModelPrefs.promptSentenceKey, promptSentence, FMReranker.defaultSentenceInstructions),
            (ModelPrefs.promptTranslateENKey, promptTranslateEN, FMReranker.defaultTranslateENInstructions),
            (ModelPrefs.promptTranslateZHKey, promptTranslateZH, FMReranker.defaultTranslateZHInstructions),
        ]
        for p in pairs {
            let blank = p.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if blank || p.value == p.def {
                d.removeObject(forKey: p.key)
            } else {
                d.set(p.value, forKey: p.key)
            }
            NSLog("[AFMApp] 提示詞應用 \(p.key)(\(blank || p.value == p.def ? "預設" : "自訂"))")
        }
        cancelTranslation(clearResult: true)
        defaults.synchronize()
        postConfigurationChange()
        promptAppliedHint = "已套用，輸入法即時生效"
    }

    /// 全部恢复默认:草稿填回内置默认并立即应用
    func resetPrompts() {
        if settingsMode == .quick {
            promptQuickRerank = FMReranker.defaultQuickRerankInstructions
            promptQuickTranslateEN = FMReranker.defaultQuickTranslateENInstructions
            promptQuickTranslateZH = FMReranker.defaultQuickTranslateZHInstructions
        } else {
            promptRerank = FMReranker.defaultRerankInstructions
            promptSentence = FMReranker.defaultSentenceInstructions
            promptTranslateEN = FMReranker.defaultTranslateENInstructions
            promptTranslateZH = FMReranker.defaultTranslateZHInstructions
        }
        applyPrompts()
        NSLog("[AFMApp] FM 提示词全部恢复默认")
    }

    // 翻译(端侧 FM,与引擎进程共用 IMECore.FMReranker;方向自动:含中文→英,否则→中)
    @Published var translateInput = "" {
        didSet {
            guard translateInput != oldValue else { return }
            cancelTranslation(clearResult: true)
        }
    }
    @Published var translateResult = ""
    @Published var translating = false
    private var translateRequestGeneration = 0
    private var translateMode: InputMethodMode { settingsMode == .quick ? .quick : .pinyin }
    private var allowCloudTranslation: Bool { settingsMode == .quick ? quickTranslationCloud : cloudEnabled }

    var translateDirection: String {
        if translateInput.trimmingCharacters(in: .whitespaces).isEmpty { return "自動" }
        let hasCJK = FMReranker.containsChinese(translateInput)
        return hasCJK ? "中文 → 英文" : (settingsMode == .quick ? "外文 → 繁體中文" : "外文 → 簡體中文")
    }

    func submitTranslate() {
        let text = translateInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !translating else { return }
        translateTask?.cancel()
        translating = true
        translateResult = ""
        translateRequestGeneration &+= 1
        let generation = translateRequestGeneration
        let operation = modeAwareTranslateOperation
        let mode = translateMode
        let allowCloud = allowCloudTranslation
        translateTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let out = await operation(text, mode, allowCloud)
            guard !Task.isCancelled, let self,
                  generation == self.translateRequestGeneration else { return }
            self.translating = false
            self.translateResult = out ?? "翻譯未完成，本機模型暫時不可用或未有回應。"
            self.translateTask = nil
        }
    }

    private func writeConfiguration(_ key: String, _ value: String) {
        defaults.set(value, forKey: key)
        defaults.synchronize()
        NSLog("[AFMApp] 設定已更新：\(key)")
        postConfigurationChange()
    }

    private func postConfigurationChange() {
        guard broadcastsConfigurationChanges else { return }
        ModelPrefs.postConfigurationChange()
    }

    private func cancelTranslation(clearResult: Bool = false) {
        translateRequestGeneration &+= 1
        translateTask?.cancel()
        translateTask = nil
        translating = false
        if clearResult { translateResult = "" }
    }

    private func saveModeSnapshot(_ mode: InputSettingsMode) {
        // 搜尋、頁碼及提示詞各自已有獨立屬性；只有共用編輯器需要切換快照。
        modeSnapshots[mode] = ModeSnapshot(translateInput: translateInput, translateResult: translateResult)
    }

    private func restoreModeSnapshot(_ mode: InputSettingsMode) {
        let snapshot = modeSnapshots[mode] ?? ModeSnapshot()
        translateInput = snapshot.translateInput
        translateResult = snapshot.translateResult
    }

    static var imeDefaults: UserDefaults {
        UserDefaults(suiteName: imeDomain) ?? .standard
    }

    init(
        defaults: UserDefaults? = nil,
        translate: TranslateOperation? = nil,
        translateModeAware: ModeAwareTranslateOperation? = nil,
        cloudProbe: @escaping CloudProbeOperation = { baseURL, apiKey, modelName, wireFormat in
            guard #available(macOS 27.0, *) else {
                return "雲端 AI 需要 macOS 27 或以上；目前可使用本機 AI 及詞庫輸入。"
            }
            return await CloudProviderModel.probe(baseURL: baseURL, apiKey: apiKey,
                                                  modelName: modelName, wireFormat: wireFormat)
        },
        loadDictionary: Bool = true,
        dictionary injectedQuickDictionary: QuickDictionary? = nil,
        learningStore injectedLearningStore: QuickLearningStore? = nil
    ) {
        let d = defaults ?? Self.imeDefaults
        self.defaults = d
        self.navigationDefaults = defaults ?? .standard
        self.broadcastsConfigurationChanges = defaults == nil
        if let translate {
            self.modeAwareTranslateOperation = { text, _, _ in await translate(text) }
        } else {
            self.modeAwareTranslateOperation = translateModeAware ?? { text, mode, allowCloud in
                await FMReranker.shared.translate(text, mode: mode, allowCloud: allowCloud, defaults: d)
            }
        }
        self.cloudProbeOperation = cloudProbe
        tab = Tab(rawValue: navigationDefaults.string(forKey: "AFMSettingsLastPane") ?? "") ?? .settings
        settingsMode = InputSettingsMode(rawValue: navigationDefaults.string(forKey: "AFMSettingsMode") ?? "quick") ?? .quick
        fuzzy = d.object(forKey: "AFMFuzzyPinyin") as? Bool ?? true
        fullWidthPunct = d.object(forKey: "AFMFullWidthPunct") as? Bool ?? true
        fmEnhance = d.object(forKey: "AFMFMEnhance") as? Bool ?? true
        userFreqEnabled = d.object(forKey: "AFMUserFreqEnabled") as? Bool ?? true
        quickFullCharset = d.bool(forKey: QuickPrefs.fullCharsetKey)
        quickLearning = d.bool(forKey: QuickPrefs.learningKey)
        quickAI = d.bool(forKey: QuickPrefs.aiKey)
        quickCloud = d.bool(forKey: QuickPrefs.cloudKey)
        quickTranslationCloud = d.bool(forKey: QuickPrefs.translationCloudKey)
        fontSize = Double(d.object(forKey: "AFMCandidateFontSize") as? Int ?? 16)
        dropletFixedLens = d.object(forKey: "AFMDropletFixedLens") as? Bool ?? false
        cloudEnabled = d.object(forKey: ModelPrefs.cloudEnabledKey) as? Bool ?? false
        cloudProvider = d.string(forKey: ModelPrefs.cloudProviderKey) ?? "openai"
        cloudBaseURL = d.string(forKey: ModelPrefs.cloudBaseURLKey) ?? ""
        cloudAPIKey = d.string(forKey: ModelPrefs.cloudAPIKeyKey) ?? ""
        cloudModel = d.string(forKey: ModelPrefs.cloudModelKey) ?? ""
        cloudFormat = d.string(forKey: ModelPrefs.cloudFormatKey) ?? "openai"
        promptRerank = (d.string(forKey: ModelPrefs.promptRerankKey) ?? "").isEmpty ? FMReranker.defaultRerankInstructions : d.string(forKey: ModelPrefs.promptRerankKey)!
        promptSentence = (d.string(forKey: ModelPrefs.promptSentenceKey) ?? "").isEmpty ? FMReranker.defaultSentenceInstructions : d.string(forKey: ModelPrefs.promptSentenceKey)!
        promptTranslateEN = (d.string(forKey: ModelPrefs.promptTranslateENKey) ?? "").isEmpty ? FMReranker.defaultTranslateENInstructions : d.string(forKey: ModelPrefs.promptTranslateENKey)!
        promptTranslateZH = (d.string(forKey: ModelPrefs.promptTranslateZHKey) ?? "").isEmpty ? FMReranker.defaultTranslateZHInstructions : d.string(forKey: ModelPrefs.promptTranslateZHKey)!
        promptQuickRerank = (d.string(forKey: ModelPrefs.promptQuickRerankKey) ?? "").isEmpty ? FMReranker.defaultQuickRerankInstructions : d.string(forKey: ModelPrefs.promptQuickRerankKey)!
        promptQuickTranslateEN = (d.string(forKey: ModelPrefs.promptQuickTranslateENKey) ?? "").isEmpty ? FMReranker.defaultQuickTranslateENInstructions : d.string(forKey: ModelPrefs.promptQuickTranslateENKey)!
        promptQuickTranslateZH = (d.string(forKey: ModelPrefs.promptQuickTranslateZHKey) ?? "").isEmpty ? FMReranker.defaultQuickTranslateZHInstructions : d.string(forKey: ModelPrefs.promptQuickTranslateZHKey)!
        quickDictionary = injectedQuickDictionary ?? (loadDictionary ? Self.loadQuickDictionary(engineBundleURL: engineBundleURL) : nil)
        quickDictionaryBrowser = quickDictionary.map(QuickDictionaryBrowser.init)
        quickLearningStore = injectedLearningStore
        if quickLearningStore == nil {
            let lockURL = defaults == nil ? nil : FileManager.default.temporaryDirectory
                .appendingPathComponent("AFMAppTests-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("quick-learning.lock")
            quickLearningStore = QuickLearningStore(defaults: d, lockURL: lockURL)
        }
        if loadDictionary { loadStore() }
        reloadQuickDict()
        reloadUserRows()
        loadHotkeys()
    }

    deinit {
        translateTask?.cancel()
        cloudProbeTask?.cancel()
    }

    private func write(_ key: String, _ value: Bool) {
        defaults.set(value, forKey: key)
        NSLog("[AFMApp] 设置 \(key) = \(value)")
        if [ModelPrefs.cloudEnabledKey, QuickPrefs.aiKey, QuickPrefs.cloudKey].contains(key) {
            cancelTranslation(clearResult: true)
            defaults.synchronize()
            postConfigurationChange()
        }
    }

    func setSettingsMode(_ mode: InputSettingsMode) {
        settingsMode = mode
        navigationDefaults.set(mode.rawValue, forKey: "AFMSettingsMode")
        preview.configure(mode: mode, model: self)
    }
    private func write(_ key: String, _ value: Int) {
        defaults.set(value, forKey: key)
        NSLog("[AFMApp] 设置 \(key) = \(value)")
    }
    private func write(_ key: String, _ value: String) {
        cancelTranslation(clearResult: true)
        writeConfiguration(key, value)
    }

    // MARK: 快捷键(kb35)

    private func loadHotkeys() {
        let d = defaults
        hotkeyRows = Self.hotkeySlots.map { slot in
            let storedCode = d.object(forKey: slot.key) as? Int
            let reserved = storedCode == 39
            let custom = storedCode != nil && !reserved
            let disp = reserved ? slot.fallbackDisplay : (d.string(forKey: slot.displayKey) ?? slot.fallbackDisplay)
            return HotkeyRow(id: slot.key, title: slot.title, display: "⌃\(disp)", custom: custom)
        }
    }

    static func resolvedHotkeyCode(stored: Int?, fallback: Int) -> Int {
        stored == 39 ? fallback : (stored ?? fallback)
    }

    private func effectiveCode(_ slot: (key: String, displayKey: String, fallback: Int, fallbackDisplay: String, title: String)) -> Int {
        Self.resolvedHotkeyCode(stored: defaults.object(forKey: slot.key) as? Int, fallback: slot.fallback)
    }

    func startRecording(_ id: String) {
        stopRecording()
        recordingHotkey = id
        hotkeyHint = "按下 Control＋字母、數字或符號；按 Esc 取消。"
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] ev in
            guard let self, self.recordingHotkey != nil else { return ev }
            self.handleRecordEvent(ev)
            return nil // 录制期间吞掉按键
        }
    }

    func stopRecording() {
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m); hotkeyMonitor = nil }
        recordingHotkey = nil
        hotkeyHint = ""
    }

    func resetHotkeys() {
        for slot in Self.hotkeySlots {
            defaults.removeObject(forKey: slot.key)
            defaults.removeObject(forKey: slot.displayKey)
        }
        NSLog("[AFMApp] 快捷键全部恢复默认")
        loadHotkeys()
        stopRecording()
    }

    private func handleRecordEvent(_ ev: NSEvent) {
        if ev.keyCode == 53 { stopRecording(); return } // Esc 取消
        let mods = ev.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.control), !mods.contains(.option), !mods.contains(.command), !mods.contains(.shift),
              let display = displayChar(for: ev) else {
            hotkeyHint = "請按 Control＋單個字母、數字或符號；不支援其他修飾鍵或功能鍵。按 Esc 取消。"
            return
        }
        guard ev.keyCode != 39 else {
            hotkeyHint = "Control＋; 已保留，請選擇其他按鍵。"
            return
        }
        guard let slot = Self.hotkeySlots.first(where: { $0.key == recordingHotkey }) else {
            stopRecording(); return
        }
        if let dup = Self.hotkeySlots.first(where: { $0.key != slot.key && effectiveCode($0) == Int(ev.keyCode) }) {
            hotkeyHint = "與「\(dup.title)」重複，請選另一個按鍵。"
            return
        }
        defaults.set(Int(ev.keyCode), forKey: slot.key)
        defaults.set(display, forKey: slot.displayKey)
        NSLog("[AFMApp] 快捷键 \(slot.key) = ⌃\(display) (keyCode \(ev.keyCode))")
        loadHotkeys()
        stopRecording()
    }

    /// 录制显示字符: 字母大写、数字/可打印符号原样;功能键/方向键等显示不出的不支持
    private func displayChar(for ev: NSEvent) -> String? {
        guard let chars = ev.charactersIgnoringModifiers, !chars.isEmpty,
              let scalar = chars.unicodeScalars.first else { return nil }
        let v = scalar.value
        if (97...122).contains(v) { return String(scalar).uppercased() } // a-z
        if (48...57).contains(v) || (32...47).contains(v) || (58...64).contains(v)
            || (91...96).contains(v) || (123...126).contains(v) { return chars } // 数字与可打印符号
        return nil
    }

    // MARK: 词库

    /// 本 helper 位于 引擎.app/Contents/PlugIns/AFMSettings.app → 上三级即引擎 bundle
    var engineBundleURL: URL {
        Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// 词库数据源: 已装输入法 bundle → 本 helper 的父引擎 bundle → 仓库 Data/(开发)
    private func loadStore() {
        let candidates = [
            IMEInstaller.installedIMEURL().appendingPathComponent("Contents/Resources/dict.bin").path,
            engineBundleURL.appendingPathComponent("Contents/Resources/dict.bin").path,
            "Data/dict.bin",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if let s = try? DictStore(url: URL(fileURLWithPath: path)) {
                store = s
                dictStats = "共 \(s.recordCount.formatted()) 條 · \(s.syllables.count.formatted()) 個音節"
                reloadDict()
                return
            }
        }
        dictStats = "未能載入拼音詞庫，請使用安裝包重新安裝 AFM輸入法。"
    }

    func reloadDict() {
        guard settingsMode == .pinyin else { return }
        guard let store else { return }
        let rawTerm = dictSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let term = rawTerm.filter { ("a"..."z").contains($0) }
        if rawTerm.isEmpty {
            // 浏览模式: 按存储序分页(每页 100 条)
            dictRows = store.records(from: dictPage * 100, limit: 100)
        } else if term.isEmpty {
            dictRows = []
        } else {
            let hits = store.query(prefix: term, exactCap: 40, extCap: 40, scanBudget: 200_000)
            dictRows = hits.map { DictStore.RecordInfo(key: $0.key, word: $0.word, weight: $0.weight) }
        }
    }

    var dictPageCount: Int {
        guard let store else { return 1 }
        return max(1, (store.recordCount + 99) / 100)
    }

    var isSearchingDict: Bool {
        !dictSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func reloadQuickDict() {
        guard settingsMode == .quick else { return }
        guard let browser = quickDictionaryBrowser else {
            quickDictUnavailable = true; quickDictRows = []; quickDictTotalCount = 0; quickDictPageCount = 1
            return
        }
        quickDictUnavailable = false
        let page = browser.page(
            section: quickDictSection, fullCharset: quickDictFullCharset,
            search: quickDictSearch, page: quickDictPage, pageSize: 100
        )
        quickDictRows = page.rows
        quickDictTotalCount = page.totalCount
        quickDictPageCount = max(1, page.pageCount)
        let boundedPage = min(max(0, quickDictPage), quickDictPageCount - 1)
        if quickDictPage != boundedPage { quickDictPage = boundedPage }
    }

    var isSearchingQuickDict: Bool { !quickDictSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private static func loadQuickDictionary(engineBundleURL: URL) -> QuickDictionary? {
        let paths = [
            IMEInstaller.installedIMEURL().appendingPathComponent("Contents/Resources/quick.json"),
            engineBundleURL.appendingPathComponent("Contents/Resources/quick.json"),
            URL(fileURLWithPath: "Data/quick.json"),
        ]
        for url in paths where FileManager.default.fileExists(atPath: url.path) {
            if let dictionary = try? QuickDictionary(url: url) { return dictionary }
        }
        return nil
    }

    // MARK: 用户词

    func reloadUserRows() {
        if settingsMode == .quick {
            quickUserRows = quickLearningStore?.entries().filter { entry in
                let term = quickUserSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let roots = entry.code.map { quickDictionary?.roots[String($0)] ?? "" }.joined()
                return term.isEmpty || entry.code.localizedCaseInsensitiveContains(term)
                    || roots.localizedCaseInsensitiveContains(term)
                    || entry.text.localizedCaseInsensitiveContains(term)
            }.map { entry in
                QuickUserRow(id: entry.id, code: entry.code,
                             roots: entry.code.map { quickDictionary?.roots[String($0)] ?? "" }.joined(),
                             text: entry.text, count: entry.count)
            } ?? []
            return
        }
        let uf = UserFreq(defaults: defaults, observesExternalChanges: false)
        let counts = defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] ?? [:]
        let pins = defaults.dictionary(forKey: "AFMUserPinyin") as? [String: String] ?? [:]
        userRows = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (word, count) in
                UserRow(id: word, word: word, pinyin: pins[word] ?? "（未記錄）",
                        count: count, score: Int(uf.userScore(count: count)), boost: uf.boost(word))
            }
    }

    func deleteQuickUser(_ entry: QuickUserRow) {
        guard quickLearningStore?.remove(code: entry.code, text: entry.text) == true else {
            userMessage = "刪除失敗，請重新整理後再試。"; return
        }
        userMessage = "已刪除「\(entry.text)」。"
        reloadUserRows()
    }

    func clearQuickUsers() {
        guard quickLearningStore?.clear() == true else {
            userMessage = "清空失敗，請稍後再試。"; return
        }
        userMessage = "已清空速成個人詞語。"
        reloadUserRows()
    }

    func importQuickUsers(from url: URL) {
        guard let quickDictionary else { userMessage = "未能載入速成詞庫，無法驗證匯入內容。"; return }
        do {
            let result = try quickLearningStore?.importJSON(Data(contentsOf: url), dictionary: quickDictionary)
            guard let result else { throw QuickLearningImportError.storageUnavailable }
            userMessage = "匯入完成：新增 \(result.added) 條、更新 \(result.updated) 條、略過 \(result.skipped) 條。"
            reloadUserRows()
        } catch {
            userMessage = "匯入失敗：\(error.localizedDescription)"
        }
    }

    func importQuickUsers() {
        let panel = NSOpenPanel()
        panel.title = "匯入速成個人詞語"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importQuickUsers(from: url)
    }

    func deleteUser(_ word: String) {
        var counts = defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] ?? [:]
        var pins = defaults.dictionary(forKey: "AFMUserPinyin") as? [String: String] ?? [:]
        counts.removeValue(forKey: word)
        pins.removeValue(forKey: word)
        defaults.set(counts, forKey: "AFMUserFreq")
        defaults.set(pins, forKey: "AFMUserPinyin")
        UserFreq.tombstone(words: [word], defaults: defaults) // 删过的不随内置种子版本升级复活
        NSLog("[AFMApp] 删除用户词 '\(word)'")
        if broadcastsConfigurationChanges { UserFreq.postExternalChange() } // 正式引擎重讀，測試保持隔離
        reloadUserRows()
    }

    func clearUsers() {
        let counts = defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] ?? [:]
        UserFreq.tombstone(words: Array(counts.keys), defaults: defaults) // 清空前全部记墓碑
        defaults.removeObject(forKey: "AFMUserFreq")
        defaults.removeObject(forKey: "AFMUserPinyin")
        defaults.set(UUID().uuidString, forKey: UserFreq.clearMarkerKey)
        NSLog("[AFMApp] 清空用户词库(墓碑 \(counts.count) 条)")
        if broadcastsConfigurationChanges { UserFreq.postExternalChange() }
        reloadUserRows()
    }

    /// 导入用户词:JSON 文件(与内置 builtin-user-words.json 同格式,见 Data/builtin-user-words.json
    /// 头部 note),合并进 IME 域——已有词取次数较大者、拼音仅缺省才补(本机数据优先,同文不降档),
    /// 导入的词解除墓碑(显式带回=用户改主意),写完广播引擎重读(kb40)
    func importUsers() {
        let panel = NSOpenPanel()
        panel.title = "匯入個人詞語"
        panel.message = "JSON 檔案，格式與內置個人詞語相同：{\"version\":1,\"words\":[{\"word\":\"词\",\"pinyin\":\"pin yin\",\"count\":3}]}"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = doc["words"] as? [[String: Any]] else {
            userMessage = "匯入失敗：JSON 格式不正確或缺少 words 陣列。"
            return
        }
        var counts = defaults.dictionary(forKey: "AFMUserFreq") as? [String: Int] ?? [:]
        var pins = defaults.dictionary(forKey: "AFMUserPinyin") as? [String: String] ?? [:]
        var added = 0, updated = 0, skipped = 0
        var importedWords: [String] = []
        for item in items {
            guard let word = item["word"] as? String, !word.isEmpty, word.count <= 50,
                  let count = item["count"] as? Int, count > 0 else {
                skipped += 1
                continue
            }
            importedWords.append(word)
            if let existing = counts[word] {
                if count > existing { counts[word] = count; updated += 1 }
            } else {
                counts[word] = count
                added += 1
            }
            if let p = item["pinyin"] as? String, UserFreq.isValidPinyin(p), pins[word] == nil {
                pins[word] = p
            }
        }
        defaults.set(counts, forKey: "AFMUserFreq")
        defaults.set(pins, forKey: "AFMUserPinyin")
        UserFreq.untombstone(words: importedWords, defaults: defaults)
        if broadcastsConfigurationChanges { UserFreq.postExternalChange() }
        NSLog("[AFMApp] 导入用户词: 新增 \(added) 更新 \(updated) 跳过 \(skipped)(源 \(url.lastPathComponent))")
        userMessage = "匯入完成：新增 \(added) 條、更新 \(updated) 條\(skipped > 0 ? "、略過無效資料 \(skipped) 條" : "")；共 \(counts.count) 條。"
        reloadUserRows()
    }

    // MARK: 系統維護

    func performMaintenance(_ action: SystemMaintenance.Action) {
        guard !maintenanceBusy else { return }
        maintenanceBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = SystemMaintenance.perform(action)
            DispatchQueue.main.async {
                self.maintenanceLog = (result.ok ? "✓ " : "⚠︎ ") + result.log
                self.maintenanceBusy = false
                self.refreshStatus()
            }
        }
    }

    func openInputSourceSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshStatus() {
        status = IMEInstaller.statusSummary()
    }

}
