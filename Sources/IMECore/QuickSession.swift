import Foundation

/// 速成（Quick）鍵盤狀態機：純 Foundation，不涉及 AppKit／UI。
///
/// 三種狀態：
/// - **idle**：無字碼、無聯想窗（`code.isEmpty && !isAssociation`）；特殊鍵全部不 consume，交回 controller。
/// - **字碼**：1–2 個字母碼。1 碼只有預覽不開窗；第 2 碼自動開窗；第 3 個字母先提交目前選字再開新一碼。
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

    /// 預覽字：聯想態沒有 marked text；有候選用目前選中項，否則用該碼的根 glyph，再退回原碼大寫
    /// （實測：a → 日；Z 未有單碼候選時預覽 Z）。
    ///
    /// 根 glyph 只作 preview；上屏一律用候選文字或實際 code 文字（見 `commitCurrentSelection`）。
    public var markedText: String {
        if isAssociation { return "" }
        if candidates.indices.contains(selectedIndex) { return candidates[selectedIndex] }
        return engine.roots[code] ?? code.uppercased()
    }

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
        candidates = []
        selectedIndex = 0
        pageStart = 0
        isAssociation = false
        isCandidateWindowVisible = false
        orderLocked = false
        aiRecommendation = nil
        generation &+= 1
    }

    /// 完成組字：提交現行字碼當頁選字（無候選時提交原碼），不提交聯想；之後清狀態。
    public func finishComposition() -> String? {
        if isAssociation {
            reset()
            return nil
        }
        guard hasActiveCode else { return nil }
        let committed = commitCurrentSelection(openAssociation: false)
        reset()
        return committed.first
    }

    /// 開關變動：現行字碼即時重查表、generation 增、選中項回到當頁首項。
    public func updateOptions(fullCharset: Bool, learning: Bool) {
        guard self.fullCharset != fullCharset || self.learning != learning else { return }
        self.fullCharset = fullCharset
        self.learning = learning
        guard hasActiveCode else { return }
        candidates = engine.candidates(for: code, fullCharset: fullCharset, learning: learning)
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

        if isAssociation {
            startCode(letter)
            return QuickResult(consumed: true)
        }
        if code.count >= 2 {
            // 第 3 個字母：先提交目前選字（無候選時提交原碼），再開新一碼；今次不開前字聯想。
            let commits = commitCurrentSelection(openAssociation: false)
            startCode(letter)
            return QuickResult(consumed: true, commits: commits)
        }
        startCode(code + letter)
        return QuickResult(consumed: true)
    }

    /// 只收 a–z／A–Z，其餘字元交回 controller。
    private static func letterCode(_ character: Character) -> String? {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let scalar = scalars.first else { return nil }
        guard (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value) else { return nil }
        return String(character).lowercased()
    }

    private func startCode(_ newCode: String) {
        code = newCode
        candidates = engine.candidates(for: newCode, fullCharset: fullCharset, learning: learning)
        selectedIndex = 0
        pageStart = 0
        isAssociation = false
        orderLocked = false
        aiRecommendation = nil
        // 1 碼只有預覽不開窗；第 2 碼起自動開窗。
        isCandidateWindowVisible = newCode.count >= 2 && !candidates.isEmpty
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

        if value == 0 {
            // 0 提交目前選中項（不傳 literal 0）。
            return QuickResult(consumed: true, commits: commitCurrentSelection(openAssociation: true))
        }
        guard (1...QuickSession.pageSize).contains(value) else { return QuickResult(consumed: false) }
        let index = pageStart + value - 1
        guard candidates.indices.contains(index) else {
            // 超出本頁的數字：吞鍵但不提交。
            return QuickResult(consumed: true)
        }
        let text = candidates[index]
        recordLearning(code: code, text: text)
        openAssociations(after: text)
        return QuickResult(consumed: true, commits: [text])
    }

    // MARK: - 空白 / 確定 / 退格 / Esc

    private func handleSpace() -> QuickResult {
        if isAssociation {
            // 聯想窗 Space：吞鍵、不選第一項、窗照留。
            return QuickResult(consumed: true)
        }
        // 字碼態空白立即確認目前候選，包括只有預覽、尚未開窗的一碼。
        guard hasActiveCode else { return QuickResult(consumed: false) }
        return QuickResult(consumed: true, commits: commitCurrentSelection(openAssociation: true))
    }

    private func handleEnter() -> QuickResult {
        if isAssociation {
            // 聯想態 Enter 不選字：放行給 controller。
            reset()
            return QuickResult(consumed: false)
        }
        guard hasActiveCode else { return QuickResult(consumed: false) }
        return QuickResult(consumed: true, commits: commitCurrentSelection(openAssociation: true))
    }

    private func handleBackspace() -> QuickResult {
        if isIdle { return QuickResult(consumed: false) }
        if isAssociation {
            // 聯想態：關窗清狀態，退格本身交回 controller。
            reset()
            return QuickResult(consumed: false)
        }
        // 字碼態一次清全部字碼（不是逐字母退）。
        reset()
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
        guard !candidates.isEmpty else { return QuickResult(consumed: true) }
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
        guard !candidates.isEmpty else { return QuickResult(consumed: true) }
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

    /// 提交目前選中候選；無候選時提交實際 code 文字（原樣，不會用 preview 的根 glyph 頂替，亦不丟輸入）。
    private func commitCurrentSelection(openAssociation: Bool) -> [String] {
        guard !code.isEmpty else { return [] }
        let activeCode = code
        let selectedFromCandidates = candidates.indices.contains(selectedIndex)
        let text = selectedFromCandidates ? candidates[selectedIndex] : activeCode
        if selectedFromCandidates { recordLearning(code: activeCode, text: text) }
        if openAssociation { openAssociations(after: text) }
        return [text]
    }

    /// 選字後開聯想窗（無聯想資料則完全回到 idle）；聯想窗沒有 marked text、由第 0 頁開始。
    private func openAssociations(after word: String) {
        let list = engine.associations(after: word)
        generation &+= 1
        code = ""
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
