import Foundation
import Testing
@testable import IMECore

/// 速成（Quick）鍵盤狀態機驗收；候選／聯想資料照 Windows 微軟速成實測樣本自建。
struct QuickSessionTests {

    // MARK: - Fixture

    /// Windows 實測 aa 第 1／2 頁（第 2 頁含補充平面字）。
    private let aaPage1 = ["昌", "晶", "暑", "間", "暗", "曙", "昍", "暙", "闍"]
    private let aaPage2 = ["閶", "閽", "闇", "晿", "暏", "彞", "龧", "𣊫", "𣊭"]

    private var windowsCandidates: [String: [String]] {
        [
            "a": ["日", "曰"],
            "aa": aaPage1 + aaPage2,
            "of": ["我", "你", "他"],
            "za": ["　", "〼", "𠮷"],
            "zz": [],
        ]
    }

    private var windowsAssociations: [String: [String]] {
        [
            "你": ["們", "我", "老", "等", "死我活", "推我讓"],
            "們": ["好"],
            "昌": ["明", "亮"],
            "晶": ["片", "瑩剔透", "瑩"],
            "日": ["本", "出"],
        ]
    }

    /// 根 glyph 表（Windows：單碼預覽用根字；z 的根就是 Z）。
    private var windowsRoots: [String: String] {
        ["a": "日", "k": "大", "z": "Z"]
    }

    private func makeSession(
        fullCharset: Bool = false,
        learning: Bool = false,
        candidates: [String: [String]]? = nil,
        fullCandidates: [String: [String]] = [:],
        associations: [String: [String]]? = nil,
        roots: [String: String]? = nil
    ) -> (session: QuickSession, defaults: UserDefaults) {
        let defaults = isolatedDefaults()
        let dictionary = QuickDictionary(
            candidates: candidates ?? windowsCandidates,
            fullCandidates: fullCandidates,
            associations: associations ?? windowsAssociations,
            roots: roots ?? windowsRoots
        )
        let engine = QuickEngine(dictionary: dictionary, defaults: defaults)
        return (QuickSession(engine: engine, fullCharset: fullCharset, learning: learning), defaults)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "QuickSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @discardableResult
    private func type(_ letters: String, _ session: QuickSession) -> QuickResult {
        var last = QuickResult(consumed: false)
        for character in letters { last = session.handle(.letter(character)) }
        return last
    }

    /// 選字後打開「你」的聯想窗（Windows：of2→你）。
    @discardableResult
    private func startAssociation(_ session: QuickSession) -> QuickResult {
        type("of", session)
        return session.handle(.digit(2, shifted: false))
    }

    // MARK: - 單碼預覽與開窗

    @Test(arguments: Array(zip([UInt16(18), 19, 20, 21, 23, 22, 26, 28, 25], Array("!@#$%^&*("))))
    func shiftedNumberSymbolsSelectAssociationByPhysicalKey(keyCode: UInt16, symbol: Character) {
        let (session, _) = makeSession()
        startAssociation(session)
        let digit = QuickKey.digitValue(keyCode: keyCode, characters: String(symbol), shifted: true)
        let expectedDigit = [UInt16(18): 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9][keyCode]!
        #expect(digit == expectedDigit)
        if let digit, digit <= session.candidates.count {
            let expectedText = session.candidates[digit - 1]
            #expect(session.handle(.digit(digit, shifted: true)).commits == [expectedText])
            #expect(!session.isAssociation)
        }
    }

    @Test func digitMappingPreservesLayoutAndDoesNotTreatPlainSymbolsAsSelections() {
        #expect(QuickKey.digitValue(keyCode: 18, characters: "2", shifted: false) == 2)
        #expect(QuickKey.digitValue(keyCode: 18, characters: "!", shifted: false) == nil)
        #expect(QuickKey.digitValue(keyCode: 1, characters: "S", shifted: true) == nil)
        #expect(QuickKey.digitValue(keyCode: 82, characters: ")", shifted: true) == 0)
    }

    @Test func singleCodeShowsPreviewWithoutWindowAndSpaceOpensCandidates() {
        let (session, _) = makeSession()

        #expect(type("a", session).consumed)
        #expect(session.code == "a")
        #expect(session.candidates == ["日", "曰"])
        #expect(session.markedText == "日")
        #expect(!session.isCandidateWindowVisible, "1 字碼有 preview 不開窗")

        let space = session.handle(.space)
        #expect(space.consumed)
        #expect(space.commits.isEmpty, "Space 開候選窗，不直接上屏")
        #expect(session.isCandidateWindowVisible)
        #expect(session.code == "a")
        #expect(session.pageStart == 0)
        #expect(session.selectedIndex == 0)
        #expect(session.markedText == "日")

        // 只有一頁時再按 Space wrap 回首頁，窗照留。
        #expect(session.handle(.space).consumed)
        #expect(session.pageStart == 0)
        #expect(session.isCandidateWindowVisible)
    }

    @Test func singleCodeSpaceThenDigitCommitsThatCandidate() {
        let (session, _) = makeSession()
        type("a", session)
        session.handle(.space)

        let result = session.handle(.digit(2, shifted: false))
        #expect(result.commits == ["曰"])
        #expect(result.consumed)
    }

    // MARK: - aa → Space → Enter 閶

    @Test func secondLetterOpensWindowAndSpacePagesThenEnterCommits() {
        let (session, _) = makeSession()

        type("aa", session)
        #expect(session.isCandidateWindowVisible, "第 2 字碼自動開窗")
        #expect(session.candidates == aaPage1 + aaPage2)
        #expect(session.selectedIndex == 0)
        #expect(session.markedText == "昌")
        #expect(!session.orderLocked)

        let space = session.handle(.space)
        #expect(space.consumed)
        #expect(space.commits.isEmpty)
        #expect(session.pageStart == 9)
        #expect(session.selectedIndex == 9)
        #expect(session.markedText == "閶")
        #expect(session.orderLocked, "翻頁後鎖序")

        let enter = session.handle(.enter)
        #expect(enter.consumed)
        #expect(enter.commits == ["閶"])
        #expect(session.code == "")
        #expect(session.candidates == [], "閶 無聯想資料 → 回到 idle")
        #expect(!session.isAssociation)
        #expect(!session.isCandidateWindowVisible)
        #expect(!session.orderLocked)
    }

    @Test func twoPageCodeWrapsBackToFirstPage() {
        let (session, _) = makeSession()
        type("aa", session)

        session.handle(.nextPage)
        #expect(session.pageStart == 9)
        #expect(session.handle(.nextPage).consumed)
        #expect(session.pageStart == 0, "尾頁之後 wrap 首頁")
        #expect(session.handle(.previousPage).consumed)
        #expect(session.pageStart == 9, "首頁之前 wrap 尾頁")
    }

    // MARK: - 第 3 個字母

    @Test func thirdLetterCommitsSelectionAndStartsNewCodeWithoutAssociation() {
        let (session, _) = makeSession()

        let third = type("aaa", session)
        #expect(third.consumed)
        #expect(third.commits == ["昌"], "第 3 字母先提交目前選字")
        #expect(session.code == "a")
        #expect(session.candidates == ["日", "曰"])
        #expect(session.markedText == "日", "新一碼只有 preview")
        #expect(!session.isAssociation, "今次不開前字聯想（昌 有聯想資料）")
        #expect(!session.isCandidateWindowVisible)
    }

    @Test func thirdLetterCommitsRawCodeWhenNoCandidates() {
        let (session, _) = makeSession()

        let third = type("zzz", session)
        #expect(third.commits == ["zz"], "無候選時提交原碼")
        #expect(session.code == "z")
        #expect(session.markedText == "Z")
        #expect(!session.isCandidateWindowVisible)
    }

    // MARK: - 聯想

    @Test func selectionOpensAssociationWindowWithoutMarkedText() {
        let (session, _) = makeSession()

        let result = startAssociation(session)
        #expect(result.consumed)
        #expect(result.commits == ["你"])
        #expect(session.isAssociation)
        #expect(session.isCandidateWindowVisible)
        #expect(session.code == "")
        #expect(session.markedText == "", "聯想態沒有 marked text")
        #expect(session.candidates == ["們", "我", "老", "等", "死我活", "推我讓"])
        #expect(session.pageStart == 0)
        #expect(session.selectedIndex == 0)
        #expect(!session.orderLocked)
        #expect(session.aiRecommendation == nil)
    }

    @Test func associationShiftDigitCommitsContinuationAndClosesWindowForGood() {
        let (session, _) = makeSession()
        startAssociation(session)

        let shifted = session.handle(.digit(1, shifted: true))
        #expect(shifted.consumed)
        #expect(shifted.commits == ["們"])
        #expect(!session.isAssociation, "續文提交後立即關窗")
        #expect(!session.isCandidateWindowVisible)
        #expect(session.candidates == [], "們 另有聯想資料亦不再查（不串接）")
        #expect(session.code == "")
        #expect(session.markedText == "")
    }

    @Test func associationShiftDigitBeyondPageIsNotConsumed() {
        let (session, _) = makeSession()
        startAssociation(session)

        let shifted = session.handle(.digit(8, shifted: true))
        #expect(!shifted.consumed, "本頁沒有的 Shift＋數字交回 controller 當符號")
        #expect(shifted.commits.isEmpty)
        #expect(session.isAssociation)
    }

    @Test func associationPlainDigitAndEnterResetWithoutCommit() {
        let (digitSession, _) = makeSession()
        startAssociation(digitSession)

        let digit = digitSession.handle(.digit(3, shifted: false))
        #expect(digit.commits.isEmpty, "聯想普通數字不選字")
        #expect(!digit.consumed)
        #expect(!digitSession.isAssociation)
        #expect(!digitSession.isCandidateWindowVisible)
        #expect(digitSession.candidates == [])

        let (enterSession, _) = makeSession()
        startAssociation(enterSession)

        let enter = enterSession.handle(.enter)
        #expect(enter.commits.isEmpty)
        #expect(!enter.consumed)
        #expect(!enterSession.isAssociation)
        #expect(enterSession.candidates == [])
    }

    @Test func associationSpaceIsConsumedWithoutChange() {
        let (session, _) = makeSession()
        startAssociation(session)
        let before = session.candidates
        let generationBefore = session.generation

        let space = session.handle(.space)
        #expect(space.consumed)
        #expect(space.commits.isEmpty)
        #expect(session.candidates == before)
        #expect(session.selectedIndex == 0)
        #expect(session.isAssociation)
        #expect(session.isCandidateWindowVisible)
        #expect(session.generation == generationBefore)
    }

    @Test func associationNavigationAndNewLetter() {
        let (session, _) = makeSession()
        startAssociation(session)

        #expect(session.handle(.nextCandidate).consumed)
        #expect(session.selectedIndex == 1)
        #expect(session.orderLocked)
        #expect(session.handle(.previousCandidate).consumed)
        #expect(session.selectedIndex == 0)

        // 聯想態打字母 = 開新字碼。
        let letter = session.handle(.letter("a"))
        #expect(letter.consumed)
        #expect(session.code == "a")
        #expect(session.candidates == ["日", "曰"])
        #expect(!session.isAssociation)
        #expect(!session.isCandidateWindowVisible)
    }

    @Test func associationEscapeClosesWindow() {
        let (session, _) = makeSession()
        startAssociation(session)

        let escape = session.handle(.escape)
        #expect(escape.consumed)
        #expect(!session.isAssociation)
        #expect(!session.isCandidateWindowVisible)
        #expect(session.candidates == [])
    }

    // MARK: - Backspace / Esc / idle

    @Test func backspaceClearsWholeCodeThenPreviewReturns() {
        let (session, _) = makeSession()
        type("aa", session)

        let backspace = session.handle(.backspace)
        #expect(backspace.consumed)
        #expect(backspace.commits.isEmpty)
        #expect(session.code == "")
        #expect(session.candidates == [])
        #expect(!session.isCandidateWindowVisible)
        #expect(session.markedText == "")

        type("a", session)
        #expect(session.code == "a")
        #expect(session.markedText == "日", "aa Backspace 後再打 a 是全新一碼")
        #expect(!session.isCandidateWindowVisible)
    }

    @Test func escapeCancelsCompositionThenIdleEscapeAndSpecialKeysPassThrough() {
        let (session, _) = makeSession()
        type("aa", session)
        let generationBefore = session.generation

        let escape = session.handle(.escape)
        #expect(escape.consumed)
        #expect(session.code == "")
        #expect(session.candidates == [])
        #expect(session.generation > generationBefore, "reset 令 generation 增加")

        let idleKeys: [QuickKey] = [
            .space, .enter, .backspace, .escape,
            .previousPage, .nextPage, .previousCandidate, .nextCandidate, .expand,
            .digit(0, shifted: false), .digit(1, shifted: false), .digit(1, shifted: true),
        ]
        for key in idleKeys {
            let result = session.handle(key)
            #expect(!result.consumed, "idle 特殊鍵不 consume：\(key)")
            #expect(result.commits.isEmpty)
        }
        #expect(session.code == "")
        #expect(session.candidates == [])
        #expect(!session.isCandidateWindowVisible)
    }

    @Test func nonLetterKeyDoesNotStartCode() {
        let (session, _) = makeSession()
        #expect(!session.handle(.letter("1")).consumed)
        #expect(!session.handle(.letter("中")).consumed)
        #expect(session.code == "")
    }

    // MARK: - 根 glyph 預覽

    @Test func previewUsesRootGlyphButCommitKeepsTypedCode() {
        let (session, _) = makeSession()   // k 無候選，根 glyph 大

        #expect(type("k", session).consumed)
        #expect(session.code == "k")
        #expect(session.candidates == [])
        #expect(session.markedText == "大", "無候選時預覽根 glyph")
        #expect(!session.isCandidateWindowVisible)

        #expect(session.finishComposition() == "k", "無候選提交實際 code 文字，不用 preview glyph 頂替、不丟輸入")
    }

    @Test func previewFallsBackToUppercasedCode() {
        let (single, _) = makeSession()
        type("z", single)
        #expect(single.markedText == "Z", "root z = Z")
        #expect(single.finishComposition() == "z")

        let (twoLetters, _) = makeSession()
        type("zz", twoLetters)
        #expect(twoLetters.code == "zz")
        #expect(twoLetters.markedText == "ZZ", "兩字母無候選 → code.uppercased()")
        #expect(twoLetters.finishComposition() == "zz")

        let (noRoot, _) = makeSession(candidates: ["ab": ["常0"]], roots: [:])
        type("q", noRoot)
        #expect(noRoot.markedText == "Q", "字典沒有該根就用原碼大寫")
        #expect(noRoot.finishComposition() == "q")
    }

    @Test func thirdLetterRawCodeCommitKeepsTypedCodeNotPreviewGlyph() {
        let (session, _) = makeSession()

        let third = type("zkz", session)   // zk 無候選（亦無根 glyph）→ 提交實際 code
        #expect(third.commits == ["zk"])
        #expect(session.code == "z")
        #expect(session.markedText == "Z")
    }

    // MARK: - 數字選字

    @Test func digitsSelectWithinPageAndZeroCommitsSelection() {
        let (session, _) = makeSession()
        type("of", session)

        let third = session.handle(.digit(3, shifted: false))
        #expect(third.commits == ["他"])
        #expect(third.consumed)

        let (zeroSession, _) = makeSession()
        type("of", zeroSession)
        zeroSession.handle(.nextCandidate)
        let zero = zeroSession.handle(.digit(0, shifted: false))
        #expect(zero.commits == ["你"], "0 提交目前選中項")
        #expect(zero.consumed)
        #expect(!zero.commits.contains("0"), "不傳 literal 0")
    }

    @Test func digitBeyondPageIsConsumedWithoutCommit() {
        let (session, _) = makeSession()
        type("of", session)

        let beyond = session.handle(.digit(5, shifted: false))
        #expect(beyond.consumed)
        #expect(beyond.commits.isEmpty, "超頁內數字吞鍵不提交")
        #expect(session.code == "of")
        #expect(session.markedText == "我")
        #expect(session.isCandidateWindowVisible)
    }

    @Test func shiftDigitInCodeStateIsLeftToController() {
        let (session, _) = makeSession()
        type("of", session)

        let shifted = session.handle(.digit(2, shifted: true))
        #expect(!shifted.consumed, "字碼 Shift＋數字留 controller 當符號")
        #expect(shifted.commits.isEmpty)
        #expect(session.code == "of")
        #expect(session.markedText == "我")
    }

    // MARK: - 導航 / 展開

    @Test func candidateNavigationCyclesWithinPageAndLocksOrder() {
        let (session, _) = makeSession()
        type("aa", session)

        #expect(session.handle(.nextCandidate).consumed)
        #expect(session.selectedIndex == 1)
        #expect(session.markedText == "晶")
        #expect(session.orderLocked)

        session.handle(.previousCandidate)
        #expect(session.selectedIndex == 0)
        session.handle(.previousCandidate)
        #expect(session.selectedIndex == 8, "前後候選在當頁循環")
        session.handle(.nextCandidate)
        #expect(session.selectedIndex == 0)

        session.handle(.nextPage)
        #expect(session.selectedIndex == 9)
        session.handle(.previousCandidate)
        #expect(session.selectedIndex == 17)
        session.handle(.nextCandidate)
        #expect(session.selectedIndex == 9)
    }

    @Test func expandTogglesTwoColumnWindowAndLocksOrder() {
        let (session, _) = makeSession()
        type("aa", session)

        let expand = session.handle(.expand)
        #expect(expand.consumed)
        #expect(session.expanded)
        #expect(session.orderLocked)
        #expect(session.handle(.expand).consumed)
        #expect(!session.expanded)

        // 單碼：Tab 開窗並展開。
        let (single, _) = makeSession()
        type("a", single)
        #expect(!single.isCandidateWindowVisible)
        #expect(single.handle(.expand).consumed)
        #expect(single.isCandidateWindowVisible)
        #expect(single.expanded)
    }

    // MARK: - 超過 100 個候選的尾頁 wrap

    @Test func pageWrapBeyondOneHundredCandidates() {
        let full = (0..<125).map { "全\($0)" }
        let (session, _) = makeSession(
            fullCharset: true,
            candidates: ["ab": ["常0", "常1", "常2"]],
            fullCandidates: ["ab": full]
        )
        type("ab", session)
        #expect(session.candidates == full)
        #expect(session.candidates.count == 125)

        for _ in 0..<13 { session.handle(.nextPage) }
        #expect(session.pageStart == 117, "14 頁中的尾頁")
        #expect(session.selectedIndex == 117)

        #expect(session.handle(.nextPage).consumed)
        #expect(session.pageStart == 0, "尾頁 PageDown wrap 首頁")
        #expect(session.selectedIndex == 0)

        for _ in 0..<13 { session.handle(.space) }
        #expect(session.pageStart == 117, "Space 與 PageDown 同款")
        #expect(session.handle(.space).consumed)
        #expect(session.pageStart == 0)

        #expect(session.handle(.previousPage).consumed)
        #expect(session.pageStart == 117, "首頁 PageUp wrap 尾頁")
        #expect(session.candidates.count - session.pageStart == 8, "尾頁不足 9 格")
    }

    // MARK: - 補充平面

    @Test func supplementaryPlaneCandidateSurvivesNavigationAndCommit() throws {
        let (session, _) = makeSession()
        type("za", session)

        #expect(session.handle(.nextCandidate).consumed)
        #expect(session.handle(.nextCandidate).consumed)
        #expect(session.selectedIndex == 2)
        #expect(session.markedText == "𠮷")
        #expect(session.markedText.unicodeScalars.count == 1)
        let scalar = try #require(session.markedText.unicodeScalars.first)
        #expect(scalar.value > 0xFFFF)

        let enter = session.handle(.enter)
        #expect(enter.commits == ["𠮷"])
        let committed = try #require(enter.commits.first)
        #expect(committed.utf16.count == 2, "代理對完整保留")
    }

    @Test func supplementaryPlaneCandidateOnSecondPageCommits() {
        let (session, _) = makeSession()
        type("aa", session)
        session.handle(.space)
        for _ in 0..<7 { session.handle(.nextCandidate) }   // 第 2 頁第 8 項

        #expect(session.selectedIndex == 16)
        #expect(session.markedText == "𣊫")
        #expect(session.handle(.enter).commits == ["𣊫"])
    }

    // MARK: - 學習

    @Test func learningRecordsCodeSelectionOnlyWhenEnabled() {
        let (session, defaults) = makeSession(learning: true)
        startAssociation(session)   // of2 → 你

        let counts = defaults.dictionary(forKey: QuickPrefs.learningDataKey) as? [String: [String: Int]]
        #expect(counts == ["of": ["你": 1]], "字碼選字以原字碼記錄")

        #expect(session.handle(.digit(1, shifted: true)).commits == ["們"])
        let countsAfterAssociation = defaults.dictionary(forKey: QuickPrefs.learningDataKey) as? [String: [String: Int]]
        #expect(countsAfterAssociation == ["of": ["你": 1]], "聯想續文沒有字碼 → 不寫學習")

        let (offSession, offDefaults) = makeSession(learning: false)
        startAssociation(offSession)
        #expect(offDefaults.dictionary(forKey: QuickPrefs.learningDataKey) == nil, "關學習不寫入")
    }

    // MARK: - 設定快照（controller 每鍵都會回報目前選項）

    @Test func updateOptionsRecomputesActiveCodeAndResetsSelection() {
        let full = (0..<125).map { "全\($0)" }
        let (session, _) = makeSession(
            candidates: ["ab": ["常0", "常1", "常2"]],
            fullCandidates: ["ab": full]
        )
        type("ab", session)
        #expect(session.candidates.count == 3)
        session.handle(.nextCandidate)
        #expect(session.selectedIndex == 1)
        let generationBefore = session.generation

        session.updateOptions(fullCharset: true, learning: false)
        #expect(session.candidates == full)
        #expect(session.selectedIndex == 0, "options 變動後 selection 歸 0")
        #expect(session.pageStart == 0)
        #expect(session.generation > generationBefore)
        #expect(session.isCandidateWindowVisible)
        #expect(session.aiRecommendation == nil)

        session.updateOptions(fullCharset: false, learning: false)
        #expect(session.candidates.count == 3)
        #expect(session.code == "ab")
    }

    @Test func updateOptionsWithoutActiveCodeOnlyStoresFlags() {
        let full = (0..<125).map { "全\($0)" }
        let (session, _) = makeSession(
            candidates: ["ab": ["常0", "常1", "常2"]],
            fullCandidates: ["ab": full]
        )
        let generationBefore = session.generation

        session.updateOptions(fullCharset: true, learning: true)
        #expect(session.generation == generationBefore)
        #expect(session.candidates == [])

        type("ab", session)
        #expect(session.candidates == full, "新開字碼已用新選項查表")
    }

    /// controller 每鍵都會交目前選項快照；同選項等於無改動，不可重設翻頁／選中項／AI 鎖／代際。
    @Test func sameOptionsUpdateKeepsSecondPageSelectionOrderLockAndGeneration() {
        let (session, _) = makeSession()
        type("aa", session)
        session.handle(.nextPage)
        #expect(session.pageStart == 9)
        #expect(session.selectedIndex == 9)
        #expect(session.orderLocked)
        let generation = session.generation

        session.updateOptions(fullCharset: false, learning: false)   // 與現行選項完全相同

        #expect(session.code == "aa")
        #expect(session.candidates == aaPage1 + aaPage2)
        #expect(session.pageStart == 9, "同選項不可重置返第 1 頁")
        #expect(session.selectedIndex == 9, "同選項不可重置選中項")
        #expect(session.generation == generation, "同選項不可增代際")
        #expect(session.orderLocked, "AI 鎖要保持")
        #expect(session.isCandidateWindowVisible)
        #expect(!session.applyRecommendation("曙", generation: generation), "鎖仍在 → 建議拒收")

        // 真正有改動（learning）才重查表、歸 0、增代際。
        session.updateOptions(fullCharset: false, learning: true)
        #expect(session.pageStart == 0)
        #expect(session.selectedIndex == 0)
        #expect(session.generation > generation)
    }

    /// 同選項亦不可還原 AI 建議排序，代際與未鎖狀態照樣保留。
    @Test func sameOptionsUpdateKeepsAIRecommendationOrder() {
        let (session, _) = makeSession()
        type("aa", session)
        let generation = session.generation
        #expect(session.applyRecommendation("曙", generation: generation))
        #expect(session.aiRecommendation == "曙")
        let ordered = session.candidates

        session.updateOptions(fullCharset: false, learning: false)

        #expect(session.candidates == ordered, "同選項不可還原 AI 排序")
        #expect(session.aiRecommendation == "曙")
        #expect(session.generation == generation)
        #expect(!session.orderLocked)
        #expect(session.selectedIndex == 0)

        // 未鎖、代際未變 → 同一代際的建議仍然有效。
        #expect(session.applyRecommendation("晶", generation: generation))
        #expect(session.candidates[1] == "晶")
        #expect(session.candidates[0] == "昌", "第一候選不變")
    }

    // MARK: - AI 建議

    @Test func applyRecommendationKeepsFirstCandidateAndRejectsBadInput() {
        let (session, _) = makeSession()
        type("aa", session)
        let generation = session.generation

        #expect(session.applyRecommendation("曙", generation: generation))
        #expect(session.candidates.count == 18, "不新增生成字")
        #expect(session.candidates[0] == "昌", "第一候選不變")
        #expect(session.candidates[1] == "曙")
        #expect(session.aiRecommendation == "曙")
        #expect(session.selectedIndex == 0, "選中項仍是原本的昌")
        #expect(session.candidates.contains("晶"))

        #expect(!session.applyRecommendation("昌", generation: generation), "第一候選不搬")
        #expect(!session.applyRecommendation("龍", generation: generation), "候選外文字拒收")
        #expect(!session.applyRecommendation("曙", generation: generation &- 1), "舊代際拒收")
        #expect(!session.applyRecommendation("", generation: generation))
    }

    @Test func applyRecommendationRejectedAfterNavigationExpandOrSelection() {
        let (session, _) = makeSession()
        type("aa", session)
        let generation = session.generation
        session.handle(.nextCandidate)
        #expect(!session.applyRecommendation("曙", generation: generation), "導航後鎖序")

        let (expandSession, _) = makeSession()
        type("aa", expandSession)
        let expandGeneration = expandSession.generation
        expandSession.handle(.expand)
        #expect(!expandSession.applyRecommendation("曙", generation: expandGeneration))

        let (pageSession, _) = makeSession()
        type("aa", pageSession)
        let pageGeneration = pageSession.generation
        pageSession.handle(.nextPage)
        #expect(!pageSession.applyRecommendation("曙", generation: pageGeneration))
    }

    @Test func generationCounterNeverRepeatsAcrossCommitRecomputeAndReset() {
        let (session, _) = makeSession()
        var seen: Set<UInt64> = [session.generation]

        func record() {
            #expect(seen.insert(session.generation).inserted, "generation 不可以重複：\(session.generation)")
        }

        type("a", session); record()
        type("a", session); record()
        let aaGeneration = session.generation

        session.handle(.digit(2, shifted: false))   // 選字 → 聯想態
        record()
        #expect(session.generation != aaGeneration)
        #expect(!session.applyRecommendation("們", generation: aaGeneration), "選字後舊代際拒收")
        #expect(!session.applyRecommendation("們", generation: session.generation), "聯想態不吃 AI 建議")

        session.handle(.escape)
        record()
        type("aa", session)
        record()
        #expect(session.generation > aaGeneration)
        #expect(!session.applyRecommendation("曙", generation: aaGeneration))
    }

    // MARK: - select / finishComposition

    @Test func selectByIndexCommitsAndOpensAssociation() {
        let (session, _) = makeSession()
        type("aa", session)

        let result = session.select(index: 1)
        #expect(result.consumed)
        #expect(result.commits == ["晶"])
        #expect(session.isAssociation)
        #expect(session.candidates == ["片", "瑩剔透", "瑩"])

        let continuation = session.select(index: 0)
        #expect(continuation.commits == ["片"])
        #expect(continuation.consumed)
        #expect(!session.isAssociation, "續文提交後關窗")
        #expect(!session.isCandidateWindowVisible)

        #expect(!session.select(index: 42).consumed, "範圍外 index 不 consume")
        #expect(session.select(index: 42).commits.isEmpty)
    }

    @Test func finishCompositionCommitsCurrentPageSelectionAndClearsState() {
        let (session, _) = makeSession()
        type("aa", session)
        session.handle(.space)

        #expect(session.finishComposition() == "閶")
        #expect(session.code == "")
        #expect(session.candidates == [])
        #expect(!session.isCandidateWindowVisible)
        #expect(!session.isAssociation)
        #expect(session.finishComposition() == nil, "已無狀態時沒有提交")
    }

    @Test func finishCompositionDoesNotCommitAssociationAndFallsBackToRawCode() {
        let (associationSession, _) = makeSession()
        startAssociation(associationSession)
        #expect(associationSession.isAssociation)
        #expect(associationSession.finishComposition() == nil, "不提交聯想")
        #expect(!associationSession.isAssociation)
        #expect(associationSession.candidates == [])

        let (rawSession, _) = makeSession()
        type("zz", rawSession)
        #expect(rawSession.markedText == "ZZ", "無候選預覽原碼大寫")
        #expect(!rawSession.isCandidateWindowVisible)
        #expect(rawSession.finishComposition() == "zz", "無候選提交原碼")
        #expect(rawSession.code == "")
    }
}
