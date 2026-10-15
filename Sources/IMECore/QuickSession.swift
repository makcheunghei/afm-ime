import Foundation

/// 速成（Quick）鍵盤狀態機：純 Foundation，不涉及 AppKit／UI。
///
/// 英文優先的組字狀態：
/// - **idle**：無字碼、無聯想窗（`code.isEmpty && !isAssociation`）；特殊鍵全部不 consume，交回 controller。
/// - **組字**：保留原文及大小寫；1–2 字母提供速成候選，第 3 字母起只保留英文，絕不自動選中文。
/// - **聯想**：選字後顯示續文（`isAssociation`、`code` 為空、無 marked text）。
///
/// 候選與聯想一律經 `QuickEngine` 查表；學習只寫回 `engine.recordSelection`（無字碼可記時不寫）。
public final class QuickSession {

    /// 每頁候選數；翻頁、數字選字都以這個單位計算。
    public static let pageSize = 9
    public let pageSize = QuickSession.pageSize

    private let engine: QuickEngine
    private var fullCharset: Bool
    private var learning: Bool

    public private(set) var code: String = ""
    public private(set) var rawText: String = ""
    public private(set) var candidates: [String] = []
    public private(set) var selectedIndex: Int = 0
    public private(set) var pageStart: Int = 0
    public private(set) var isAssociation: Bool = false
    public private(set) var isCandidateWindowVisible: Bool = false
    public private(set) var orderLocked: Bool = false
    public private(set) var generation: UInt64 = 0
    public private(set) var aiRecommendation: String? = nil

    public init(engine: QuickEngine, fullCharset: Bool = false, learning: Bool = false) {
        self.engine = engine
        self.fullCharset = fullCharset
        self.learning = learning
    }

    /// 行內只顯示使用者輸入；中文要由數字或點選明確確認。
    public var markedText: String { isAssociation ? "" : rawText }

    // MARK: - 按鍵入口

    public func handle(_ key: QuickKey) -> QuickResult {
        switch key {
        case .letter(let character):
            return handleLetter(character)
        case .digit(let value, let shifted):
            return handleDigit(value, shifted: shifted)
        case .space:
            return handleSpace()
        case .enter:
            return handleEnter()
        case .backspace:
            return handleBackspace()
        case .escape:
            return handleEscape()
        case .previousPage:
            return movePage(step: -1)
        case .nextPage:
            return movePage(step: 1)
        case .previousCandidate:
            return moveCandidate(step: -1)
        case .nextCandidate:
            return moveCandidate(step: 1)
        }
    }

    /// 直接選第 `index` 項（滑鼠點選／controller 指定）；聯想態同樣是提交續文後關窗。
    public func select(index: Int) -> QuickResult {
        guard candidates.indices.contains(index) else { return QuickResult(consumed: false) }
        let text = candidates[index]
        if isAssociation {
            reset()
            return QuickResult(consumed: true, commits: [text])
        }
        guard hasActiveCode else { return QuickResult(consumed: false) }
        recordLearning(code: code, text: text)
        openAssociations(after: text)
        return QuickResult(consumed: true, commits: [text])
    }

    /// 清空全部狀態（取消組字、失焦、模式切換）。generation 只增不減。
    public func reset() {
        code = ""
        rawText = ""
        candidates = []
        selectedIndex = 0
        pageStart = 0
        isAssociation = false
        isCandidateWindowVisible = false
        orderLocked = false
        aiRecommendation = nil
        generation &+= 1
    }

    /// 失焦、標點或模式切換只提交英文原文，不隱式選中文或聯想。
    public func finishComposition() -> String? {
        let text = rawText
        reset()
        return text.isEmpty ? nil : text
    }

    /// 開關變動：現行字碼即時重查表、generation 增、選中項回到當頁首項。
    public func updateOptions(fullCharset: Bool, learning: Bool) {
        guard self.fullCharset != fullCharset || self.learning != learning else { return }
        self.fullCharset = fullCharset
        self.learning = learning
        guard hasActiveCode else { return }
        candidates = chineseCandidates(for: rawText)
        selectedIndex = 0
        pageStart = 0
        aiRecommendation = nil
        isCandidateWindowVisible = isCandidateWindowVisible && !candidates.isEmpty
        generation &+= 1
    }

    /// 延遲到達的 AI 建議：代際要相同、仍在字碼態、未被導航／翻頁鎖定，
    /// 該字必須已在候選內且不是第一候選；只把它搬到 index 1，第一候選不動、不新增生成字。
    public func applyRecommendation(_ text: String, generation: UInt64) -> Bool {
        guard generation == self.generation,
              hasActiveCode,
              !orderLocked,
              let index = candidates.firstIndex(of: text),
              index != 0 else { return false }

        let previouslySelected = candidates.indices.contains(selectedIndex) ? candidates[selectedIndex] : text
        candidates.remove(at: index)
        candidates.insert(text, at: 1)
        aiRecommendation = text
        selectedIndex = candidates.firstIndex(of: previouslySelected) ?? 0
        return true
    }

    // MARK: - 狀態判斷

    private var isIdle: Bool { code.isEmpty && !isAssociation }
    private var hasActiveCode: Bool { !isAssociation && !code.isEmpty }

    // MARK: - 字母

    private func handleLetter(_ character: Character) -> QuickResult {
        guard let letter = Self.letterCode(character) else { return QuickResult(consumed: false) }

        startCode((isAssociation ? "" : rawText) + letter)
        return QuickResult(consumed: true)
    }

    /// 只收 ASCII 字母，保留大小寫；查字碼時另作小寫正規化。
    private static func letterCode(_ character: Character) -> String? {
        guard character.isASCII, character.isLetter else { return nil }
        return String(character)
    }

    private func chineseCandidates(for text: String) -> [String] {
        guard (1...2).contains(text.count), text.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
        return engine.candidates(for: text.lowercased(), fullCharset: fullCharset, learning: learning)
    }

    private func startCode(_ text: String) {
        rawText = text
        code = text.lowercased()
        candidates = chineseCandidates(for: text)
        selectedIndex = 0
        pageStart = 0
        isAssociation = false
        orderLocked = false
        aiRecommendation = nil
        isCandidateWindowVisible = !candidates.isEmpty
        generation &+= 1
    }

    // MARK: - 數字

    private func handleDigit(_ value: Int, shifted: Bool) -> QuickResult {
        if isAssociation {
            guard shifted else {
                // 聯想普通數字不選字：放行給 controller（會插入字元），順手關窗清狀態。
                reset()
                return QuickResult(consumed: false)
            }
            let index = pageStart + value - 1
            guard (1...QuickSession.pageSize).contains(value), candidates.indices.contains(index) else {
                // 本頁沒有對應續文：Shift＋數字留給 controller 當符號。
                return QuickResult(consumed: false)
            }
            let text = candidates[index]
            reset()
            return QuickResult(consumed: true, commits: [text])
        }

        guard hasActiveCode else { return QuickResult(consumed: false) }
        // 字碼態 Shift＋數字不處理，留 controller 當符號。
        guard !shifted else { return QuickResult(consumed: false) }

        guard (0...9).contains(value) else { return QuickResult(consumed: false) }
        let index = pageStart + value - 1
        guard value != 0, candidates.indices.contains(index) else {
            // 沒有對應中文選項的數字屬於英文原文（例如 abc123、of0）。
            startCode(rawText + String(value))
            return QuickResult(consumed: true)
        }
        let text = candidates[index]
        recordLearning(code: code, text: text)
        openAssociations(after: text)
        return QuickResult(consumed: true, commits: [text])
    }

    // MARK: - 空白 / 確定 / 退格 / Esc

    private func handleSpace() -> QuickResult {
        guard !isIdle else { return QuickResult(consumed: false) }
        if isAssociation {
            reset()
            return QuickResult(consumed: true, commits: [" "])
        }
        if rawText.count == 1, candidates.indices.contains(selectedIndex) {
            return select(index: selectedIndex)
        }
        if rawText.count <= 2, rawText.allSatisfy({ $0.isASCII && $0.isLetter }) {
            // 完整雙碼空白只翻頁；單頁或無候選保持原碼及高亮。
            guard candidates.count > Self.pageSize else {
                orderLocked = true
                return QuickResult(consumed: true)
            }
            return movePage(step: 1)
        }
        // 英文中的空白保留在組字內，統一由 Enter 確認整段原文。
        startCode(rawText + " ")
        return QuickResult(consumed: true)
    }

    private func handleEnter() -> QuickResult {
        if isAssociation {
            reset()
            return QuickResult(consumed: false)
        }
        guard let text = finishComposition() else { return QuickResult(consumed: false) }
        return QuickResult(consumed: true, commits: [text])
    }

    private func handleBackspace() -> QuickResult {
        if isIdle { return QuickResult(consumed: false) }
        if isAssociation {
            // 聯想態：關窗清狀態，退格本身交回 controller。
            reset()
            return QuickResult(consumed: false)
        }
        let remaining = String(rawText.dropLast())
        if remaining.isEmpty { reset() } else { startCode(remaining) }
        return QuickResult(consumed: true)
    }

    private func handleEscape() -> QuickResult {
        if isIdle { return QuickResult(consumed: false) }
        reset()
        return QuickResult(consumed: true)
    }

    // MARK: - 翻頁 / 導航

    private func movePage(step: Int) -> QuickResult {
        if isIdle { return QuickResult(consumed: false) }
        guard !candidates.isEmpty else { return QuickResult(consumed: false) }
        if isCandidateWindowVisible {
            advancePage(by: step)
        } else {
            // 只有預覽時，翻頁鍵先開出首頁（不會跳過最常用的一頁）。
            isCandidateWindowVisible = true
            orderLocked = true
        }
        return QuickResult(consumed: true)
    }

    private func advancePage(by step: Int) {
        let lastPageStart = ((candidates.count - 1) / QuickSession.pageSize) * QuickSession.pageSize
        var next = pageStart + step * QuickSession.pageSize
        if next > lastPageStart { next = 0 }        // 尾頁之後 wrap 回首頁
        if next < 0 { next = lastPageStart }        // 首頁之前 wrap 到尾頁
        pageStart = next
        selectedIndex = next
        orderLocked = true
    }

    private func moveCandidate(step: Int) -> QuickResult {
        if isIdle { return QuickResult(consumed: false) }
        guard !candidates.isEmpty else { return QuickResult(consumed: false) }
        isCandidateWindowVisible = true
        let last = min(pageStart + QuickSession.pageSize, candidates.count) - 1
        var next = selectedIndex + step
        if next > last { next = pageStart }         // 當頁循環
        if next < pageStart { next = last }
        selectedIndex = next
        orderLocked = true
        return QuickResult(consumed: true)
    }

    // MARK: - 提交 / 聯想 / 學習

    /// 選字後開聯想窗（無聯想資料則完全回到 idle）；聯想窗沒有 marked text、由第 0 頁開始。
    private func openAssociations(after word: String) {
        let list = engine.associations(after: word)
        generation &+= 1
        code = ""
        rawText = ""
        candidates = list
        selectedIndex = 0
        pageStart = 0
        orderLocked = false
        aiRecommendation = nil
        isAssociation = !list.isEmpty
        isCandidateWindowVisible = !list.isEmpty
    }

    private func recordLearning(code activeCode: String, text: String) {
        guard !activeCode.isEmpty else { return }
        engine.recordSelection(code: activeCode, text: text, enabled: learning)
    }
}

/// 速成狀態機認得的按鍵。
public enum QuickKey: Equatable {
    case letter(Character)
    case digit(Int, shifted: Bool)
    case space
    case enter
    case backspace
    case escape
    case previousPage
    case nextPage
    case previousCandidate
    case nextCandidate

    /// charactersIgnoringModifiers 在部分客戶端不含 Shift 的大小寫效果。
    public static func letterCharacter(_ characters: String, shifted: Bool, capsLock: Bool) -> Character? {
        guard characters.count == 1, let character = characters.first,
              character.isASCII, character.isLetter else { return nil }
        return (shifted != capsLock ? characters.uppercased() : characters.lowercased()).first
    }

    /// 左右固定翻頁、上下選字；Tab 不屬於速成按鍵，交回應用程式。
    public static func navigationKey(keyCode: UInt16) -> QuickKey? {
        switch keyCode {
        case 116, 123: return .previousPage
        case 121, 124: return .nextPage
        case 126: return .previousCandidate
        case 125: return .nextCandidate
        default: return nil
        }
    }

    /// AppKit 的 charactersIgnoringModifiers 仍可包含 Shift 產生的符號。
    /// 普通數字尊重鍵盤配置；Shift＋數字以數字列／數字鍵盤鍵碼識別。
    public static func digitValue(keyCode: UInt16, characters: String, shifted: Bool) -> Int? {
        if characters.utf8.count == 1, let byte = characters.utf8.first,
           (48...57).contains(byte) { return Int(byte - 48) }
        guard shifted else { return nil }
        switch keyCode {
        case 18, 83: return 1
        case 19, 84: return 2
        case 20, 85: return 3
        case 21, 86: return 4
        case 23, 87: return 5
        case 22, 88: return 6
        case 26, 89: return 7
        case 28, 91: return 8
        case 25, 92: return 9
        case 29, 82: return 0
        default: return nil
        }
    }
}

/// 狀態機回應：`consumed` 為 true 時 controller 不應再把該鍵交給應用；`commits` 為要上屏的文字。
public struct QuickResult: Equatable {
    public let consumed: Bool
    public let commits: [String]

    public init(consumed: Bool, commits: [String] = []) {
        self.consumed = consumed
        self.commits = commits
    }
}
