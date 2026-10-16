import Foundation
import FoundationModels

/// 端侧 FM 候选重排:根据上文语境把最合适的候选提到首位。
/// 设计:每次新建 session(创建仅 ~1ms,无 transcript 增长,延迟稳定 ~0.3s);
/// 失败/不可用一律静默返回 nil,绝不阻塞打字。
/// kb36:提示词可经设置中心「模型」页整段覆盖(留空用内置默认);云端模型启用时经
/// FoundationModels Provider 协议(CloudProviderModel)走同一 LanguageModelSession 代码路径,
/// 失败自动回落端侧 FM,端侧也不可用 → nil → 纯词典。
public final class FMReranker {
    public static let shared = FMReranker()

    // MARK: 内置默认提示词(「模型」页四段编辑框留空即用这些;改动请保留"只输出结果"约束,否则解析回退)

    public static let defaultRerankInstructions = "你是中文输入法的候选排序引擎。根据上文语境和拼音,从候选列表中选出最符合语境的一个。只输出该候选的序号数字,禁止输出任何其他内容。"
    public static let defaultSentenceInstructions = "你是中文拼音输入法的整句预测引擎。把用户输入的拼音串转成最通顺的中文。只输出中文结果,禁止解释、禁止重复拼音。"
    public static let defaultTranslateENInstructions = "你是翻译引擎。把用户输入的中文翻译成地道的英文。只输出译文,不要解释、不要加引号。"
    public static let defaultTranslateZHInstructions = "你是翻译引擎。把用户输入的外文翻译成通顺的简体中文。只输出译文,不要解释、不要加引号。"
    public static let defaultQuickRerankInstructions = "你是香港繁體速成輸入法的候選推薦引擎。根據上文、速成碼和候選列表，選出最符合語境的一項。只能選列表內已有候選。只輸出序號數字，不要解釋。"
    public static let defaultQuickTranslateENInstructions = "你是翻譯引擎。把使用者輸入的中文翻譯成自然的英文。只輸出譯文，不要解釋、不要加引號。"
    public static let defaultQuickTranslateZHInstructions = "你是香港繁體中文翻譯引擎。把使用者輸入的外文翻譯成自然的繁體中文，採用香港慣用詞彙及繁體字。只輸出譯文，不要解釋、不要加引號。"

    /// 提示词解析顺序:设置中心覆盖 → 内置默认(每次调用现读,cfprefsd 跨进程失效即时生效)
    private static var rerankInstructions: String {
        ModelPrefs.promptOverride(ModelPrefs.promptRerankKey) ?? defaultRerankInstructions
    }
    private static var sentenceInstructions: String {
        ModelPrefs.promptOverride(ModelPrefs.promptSentenceKey) ?? defaultSentenceInstructions
    }

    private var available: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// 统一出入口:云端启用且配置完整 → 云端(Provider 协议);失败/未启用/配置不全 → 端侧 FM;
    /// 都失败 → nil。label 仅用于日志区分(重排/整句/翻译)。
    private func respond(label: String, instructions: String, prompt: String,
                         cloudOverride: Bool? = nil, defaults: UserDefaults = .standard) async -> String? {
        guard !Task.isCancelled else { return nil }
        if #available(macOS 27.0, *), cloudOverride ?? ModelPrefs.cloudEnabled,
           let cfg = CloudProviderModel.configured(defaults: defaults) {
            let t0 = Date()
            do {
                let session = LanguageModelSession(model: CloudProviderModel(config: cfg),
                                                   instructions: instructions)
                let resp = try await session.respond(to: prompt)
                guard !Task.isCancelled else { return nil }
                let ms = String(format: "%.0f", -t0.timeIntervalSinceNow * 1000)
                DebugLog.log("云端响应[\(label)](\(ms)ms, \(cfg.modelName)): '\(resp.content.prefix(40))'")
                return resp.content
            } catch is CancellationError {
                return nil
            } catch {
                guard !Task.isCancelled else { return nil }
                let ms = String(format: "%.0f", -t0.timeIntervalSinceNow * 1000)
                DebugLog.error("云端[\(label)]失败(\(ms)ms) → 回落端侧 FM: \(error)")
            }
        }
        guard !Task.isCancelled, available else {
            DebugLog.log("FM 不可用 available=false [\(label)](云端未启用或已回落)")
            return nil
        }
        let t0 = Date()
        do {
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: instructions)
            let resp = try await session.respond(to: prompt)
            guard !Task.isCancelled else { return nil }
            let ms = String(format: "%.0f", -t0.timeIntervalSinceNow * 1000)
            DebugLog.log("FM 响应[\(label)](\(ms)ms): '\(resp.content.prefix(40))'")
            return resp.content
        } catch is CancellationError {
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            DebugLog.error("FM [\(label)]失败: \(error) (耗时\(String(format: "%.0f", -t0.timeIntervalSinceNow * 1000))ms)")
            return nil
        }
    }

    /// 返回 FM 选中的候选在入参 candidates 中的下标;不可用/失败/无法解析返回 nil
    public func rerank(context: String, pinyin: String, candidates: [String]) async -> Int? {
        guard !candidates.isEmpty else {
            DebugLog.log("FM 重排跳过: 无候选")
            return nil
        }
        let numbered = candidates.enumerated()
            .map { "\($0.offset + 1).\($0.element)" }
            .joined(separator: " ")
        let prompt = """
        上文:\(context.isEmpty ? "(句首)" : context)
        拼音:\(pinyin)
        候选:\(numbered)
        """
        DebugLog.log("FM 请求: \(prompt.replacingOccurrences(of: "\n", with: " | "))")
        guard let out = await respond(label: "重排", instructions: Self.rerankInstructions, prompt: prompt) else {
            return nil
        }
        let idx = Self.firstIndex(in: out, upperBound: candidates.count)
        DebugLog.log("FM 解析: idx=\(idx.map(String.init) ?? "nil")")
        return idx
    }

    /// 速成的雲端授權獨立於拼音；只能推薦已有候選，不生成替代字。
    public func rerankQuick(context: String, code: String, candidates: [String],
                            allowCloud: Bool) async -> Int? {
        guard candidates.count > 1 else { return nil }
        let instructions = ModelPrefs.promptOverride(ModelPrefs.promptQuickRerankKey)
            ?? Self.defaultQuickRerankInstructions
        let numbered = candidates.enumerated().map { "\($0.offset + 1).\($0.element)" }.joined(separator: " ")
        let prompt = "上文：\(context.isEmpty ? "（句首）" : context)\n速成碼：\(code)\n候選：\(numbered)"
        guard let response = await respond(label: "速成推薦", instructions: instructions,
                                           prompt: prompt, cloudOverride: allowCloud) else { return nil }
        return Self.firstIndex(in: response, upperBound: candidates.count)
    }

    /// FM 整句预测:长拼音词典覆盖不住时,直接让模型出句子
    public func predictSentence(context: String, pinyin: String) async -> String? {
        guard pinyin.count >= 4 else {
            DebugLog.log("FM 整句跳过: 长度=\(pinyin.count)")
            return nil
        }
        let prompt = """
        \(context.isEmpty ? "" : "上文:\(context)\n")拼音:\(pinyin)
        把拼音转成中文,只输出中文本身,不要解释。
        """
        DebugLog.log("FM 整句请求: 拼音='\(pinyin)' 上文='\(context)'")
        guard let out = await respond(label: "整句", instructions: Self.sentenceInstructions, prompt: prompt) else {
            return nil
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.looksLikeChinese(trimmed) else {
            DebugLog.log("FM 整句拒绝: 不像中文输出")
            return nil
        }
        return trimmed
    }

    static func looksLikeChinese(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 60 else { return false }
        let cjk = s.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        return Double(cjk) >= Double(s.unicodeScalars.count) * 0.5
    }

    /// FM 翻译(⌃F 面板): 含中文 → 译英,否则 → 译中;失败/不可用静默 nil
    public func translate(_ text: String, mode: InputMethodMode = .pinyin,
                          allowCloud: Bool? = nil, defaults: UserDefaults = .standard) async -> String? {
        guard !text.isEmpty else {
            DebugLog.log("FM 翻译跳过: 空输入")
            return nil
        }
        let plan = Self.translationPlan(text: text, mode: mode, allowCloud: allowCloud, defaults: defaults)
        guard let out = await respond(label: plan.toEnglish ? "翻譯中→英" : "翻譯→中",
                                      instructions: plan.instructions, prompt: text,
                                      cloudOverride: plan.allowCloud, defaults: defaults) else {
            return nil
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != text else { return nil }
        return trimmed
    }

    /// Unicode Han 包含擴展平面的漢字，不把速成擴展字誤當成外文。
    public static func containsChinese(_ text: String) -> Bool {
        text.range(of: "\\p{Han}", options: .regularExpression) != nil
    }

    struct TranslationPlan: Equatable {
        let toEnglish: Bool
        let instructions: String
        let allowCloud: Bool
    }

    /// 純配置解析可用隔離偏好測試，不建立模型 session 或發送網絡請求。
    static func translationPlan(text: String, mode: InputMethodMode, allowCloud: Bool? = nil,
                                defaults: UserDefaults = .standard) -> TranslationPlan {
        let toEnglish = containsChinese(text)
        let key: String
        let fallback: String
        if mode == .quick {
            key = toEnglish ? ModelPrefs.promptQuickTranslateENKey : ModelPrefs.promptQuickTranslateZHKey
            fallback = toEnglish ? defaultQuickTranslateENInstructions : defaultQuickTranslateZHInstructions
        } else {
            key = toEnglish ? ModelPrefs.promptTranslateENKey : ModelPrefs.promptTranslateZHKey
            fallback = toEnglish ? defaultTranslateENInstructions : defaultTranslateZHInstructions
        }
        let custom = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranslationPlan(toEnglish: toEnglish,
            instructions: custom.flatMap { $0.isEmpty ? nil : $0 } ?? fallback,
            allowCloud: allowCloud ?? defaults.bool(forKey: mode == .quick
                ? QuickPrefs.translationCloudKey : ModelPrefs.cloudEnabledKey))
    }

    static func firstIndex(in text: String, upperBound: Int) -> Int? {
        var digits = ""
        for ch in text {
            if ch.isNumber { digits.append(ch) }
            else if !digits.isEmpty { break }
        }
        guard let n = Int(digits), (1...upperBound).contains(n) else { return nil }
        return n - 1
    }
}
