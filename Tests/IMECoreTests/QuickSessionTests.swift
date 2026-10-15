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
            "m": ["一"],
            "o": ["人"],
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

    /// 保留原字典根表作資料 fixture；英文優先模式不以根字取代行內原文。
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

    @Test func singleCodeDigitCommitsCandidateWithoutSpace() {
        let (session, _) = makeSession()
        type("a", session)
        let result = session.handle(.digit(2, shifted: false))
        #expect(result.commits == ["曰"])
        #expect(result.consumed)
    }

    // MARK: - 翻頁

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
        #expect(session.isCandidateWindowVisible)
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
            .space, .enter, .backspace, .forwardDelete, .escape,
            .previousPage, .nextPage, .previousCandidate, .nextCandidate,
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

    // MARK: - 數字選字

    @Test func shiftDigitInCodeStateIsLeftToController() {
        let (session, _) = makeSession()
        type("of", session)

        let shifted = session.handle(.digit(2, shifted: true))
        #expect(!shifted.consumed, "字碼 Shift＋數字留 controller 當符號")
        #expect(shifted.commits.isEmpty)
        #expect(session.code == "of")
        #expect(session.candidates[session.selectedIndex] == "我")
    }

    // MARK: - 導航 / 鍵盤翻頁

    @Test func candidateNavigationCyclesWithinPageAndLocksOrder() {
        let (session, _) = makeSession()
        type("aa", session)

        #expect(session.handle(.nextCandidate).consumed)
        #expect(session.selectedIndex == 1)
        #expect(session.candidates[session.selectedIndex] == "晶")
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

    @Test func physicalArrowKeysPageAndSelectWithinOneColumn() throws {
        let (session, _) = makeSession()
        type("aa", session)
        let right = try #require(QuickKey.navigationKey(keyCode: 124))
        let left = try #require(QuickKey.navigationKey(keyCode: 123))
        let down = try #require(QuickKey.navigationKey(keyCode: 125))
        let up = try #require(QuickKey.navigationKey(keyCode: 126))

        #expect(session.handle(right).commits.isEmpty)
        #expect(session.pageStart == 9)
        #expect(session.candidates[session.selectedIndex] == "閶")
        session.handle(down)
        #expect(session.candidates[session.selectedIndex] == "閽")
        session.handle(up)
        #expect(session.candidates[session.selectedIndex] == "閶")
        session.handle(right)
        #expect(session.pageStart == 0, "右鍵由尾頁循環回首頁")
        session.handle(left)
        #expect(session.pageStart == 9, "左鍵由首頁循環到尾頁")
        #expect(session.handle(.digit(2, shifted: false)).commits == ["閽"])
        #expect(QuickKey.navigationKey(keyCode: 48) == nil, "Tab 不再攔截作候選展開")
    }

    @Test func associationRightArrowPagesBeforeShiftDigitSelection() throws {
        let continuations = (0..<11).map { "續\($0)" }
        let (session, _) = makeSession(associations: ["你": continuations])
        startAssociation(session)
        let right = try #require(QuickKey.navigationKey(keyCode: 124))
        session.handle(right)
        #expect(session.pageStart == 9)
        #expect(session.handle(.digit(2, shifted: true)).commits == ["續10"])
        #expect(!session.isAssociation)
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
        #expect(session.candidates[session.selectedIndex] == "𠮷")
        #expect(session.candidates[session.selectedIndex].unicodeScalars.count == 1)
        let scalar = try #require(session.candidates[session.selectedIndex].unicodeScalars.first)
        #expect(scalar.value > 0xFFFF)

        let enter = session.select(index: session.selectedIndex)
        #expect(enter.commits == ["𠮷"])
        let committed = try #require(enter.commits.first)
        #expect(committed.utf16.count == 2, "代理對完整保留")
    }

    @Test func supplementaryPlaneCandidateOnSecondPageCommits() {
        let (session, _) = makeSession()
        type("aa", session)
        session.handle(.nextPage)
        for _ in 0..<7 { session.handle(.nextCandidate) }   // 第 2 頁第 8 項

        #expect(session.selectedIndex == 16)
        #expect(session.candidates[session.selectedIndex] == "𣊫")
        #expect(session.select(index: session.selectedIndex).commits == ["𣊫"])
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

    @Test func applyRecommendationRejectedAfterNavigationOrPaging() {
        let (session, _) = makeSession()
        type("aa", session)
        let generation = session.generation
        session.handle(.nextCandidate)
        #expect(!session.applyRecommendation("曙", generation: generation), "導航後鎖序")

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

    @Test func finishCompositionDoesNotCommitAssociationAndFallsBackToRawCode() {
        let (associationSession, _) = makeSession()
        startAssociation(associationSession)
        #expect(associationSession.isAssociation)
        #expect(associationSession.finishComposition() == nil, "不提交聯想")
        #expect(!associationSession.isAssociation)
        #expect(associationSession.candidates == [])

        let (rawSession, _) = makeSession()
        type("zz", rawSession)
        #expect(rawSession.markedText == "zz", "行內保留原文")
        #expect(!rawSession.isCandidateWindowVisible)
        #expect(rawSession.finishComposition() == "zz", "無候選提交原碼")
        #expect(rawSession.code == "")
    }

    // MARK: - 英文優先混輸

    @Test(arguments: ["m", "o", "I", "a", "am", "of", "AI", "ma", "zz", "makcheunghei", "MakCheungHei"])
    func enterCommitsExactEnglish(text: String) {
        let (session, defaults) = makeSession(learning: true)
        for character in text {
            #expect(session.handle(.letter(character)).commits.isEmpty)
        }
        #expect(session.markedText == text)
        #expect(session.handle(.enter).commits == [text])
        #expect(session.rawText.isEmpty)
        #expect(session.candidates.isEmpty)
        #expect(!session.isAssociation)
        #expect(!session.handle(.space).consumed)
        #expect(defaults.dictionary(forKey: QuickPrefs.learningDataKey) == nil)
    }

    @Test(arguments: ["ma", "Ma", "MA"])
    func chineseRequiresExplicitDigitOrClick(text: String) {
        let (session, _) = makeSession(candidates: ["ma": ["百", "頁"]])
        type(text, session)
        #expect(session.markedText == text)
        #expect(session.isCandidateWindowVisible)
        #expect(session.handle(.digit(1, shifted: false)).commits == ["百"])
        type(text, session)
        #expect(session.select(index: 1).commits == ["頁"])
    }

    @Test func thirdLetterNeverCommitsChineseAndRejectsStaleAI() {
        let (session, _) = makeSession()
        type("aa", session)
        let generation = session.generation
        #expect(session.handle(.letter("A")).commits.isEmpty)
        #expect(session.markedText == "aaA")
        #expect(session.candidates.isEmpty)
        #expect(!session.isCandidateWindowVisible)
        #expect(!session.applyRecommendation("晶", generation: generation))
        #expect(!session.select(index: 0).consumed)
    }

    @Test func backspaceStillEditsChineseCodeOneCharacterAtATime() {
        let (session, _) = makeSession()
        type("aa", session)
        #expect(session.handle(.backspace).commits.isEmpty)
        #expect(session.markedText == "a")
        #expect(session.isCandidateWindowVisible)
        #expect(session.candidates == ["日", "曰"])
        session.handle(.backspace)
        #expect(session.rawText.isEmpty)
        #expect(!session.handle(.backspace).consumed)
    }

    @Test func enterAndFinishNeverChooseHighlightedChinese() {
        let (session, defaults) = makeSession(learning: true)
        type("AA", session)
        session.handle(.nextPage)
        #expect(session.handle(.enter).commits == ["AA"])
        #expect(!session.handle(.enter).consumed)
        type("AA", session)
        session.handle(.nextPage)
        #expect(session.finishComposition() == "AA")
        #expect(session.finishComposition() == nil)
        #expect(defaults.dictionary(forKey: QuickPrefs.learningDataKey) == nil)
    }

    @Test func spacePagesDoubleCodeAndEnterStillCommitsEnglish() {
        let (session, _) = makeSession()
        type("aa", session)
        #expect(session.handle(.space).commits.isEmpty)
        #expect(session.pageStart == 9)
        #expect(session.markedText == "aa")
        #expect(session.handle(.space).commits.isEmpty)
        #expect(session.pageStart == 0)
        #expect(session.handle(.enter).commits == ["aa"])
        type("aa", session)
        session.handle(.nextPage)
        #expect(session.handle(.digit(1, shifted: false)).commits == ["閶"])
    }

    @Test func singleCodeSpaceSelectsChineseAndOpensAssociations() {
        let (session, _) = makeSession()
        for (code, expected) in [("o", "人"), ("M", "一"), ("a", "日")] {
            session.reset()
            type(code, session)
            #expect(session.handle(.space).commits == [expected])
            #expect(session.rawText.isEmpty)
        }
        #expect(session.isAssociation)
        #expect(session.candidates == ["本", "出"])
    }

    @Test func singlePageSpaceDoesNotConfirmOrResetHighlight() {
        let (session, _) = makeSession()
        type("of", session)
        session.handle(.nextCandidate)
        for _ in 0..<3 {
            #expect(session.handle(.space).commits.isEmpty)
            #expect(session.rawText == "of")
            #expect(session.selectedIndex == 1)
            #expect(session.pageStart == 0)
        }
        #expect(session.handle(.digit(2, shifted: false)).commits == ["你"])
    }

    @Test func englishSpaceCommitsImmediatelyAndStartsANewWord() {
        let (session, _) = makeSession()
        type("MakCheungHei", session)
        #expect(session.handle(.space).commits == ["MakCheungHei "])
        #expect(session.rawText.isEmpty)
        type("Hello", session)
        #expect(session.markedText == "Hello")
        #expect(session.handle(.enter).commits == ["Hello"])
    }

    @Test(arguments: ["z", "zz", "com", "COM"])
    func spaceWithoutCandidatesCommitsRawAndSpace(text: String) {
        let (session, _) = makeSession()
        type(text, session)
        #expect(session.handle(.space).commits == [text + " "])
        #expect(session.rawText.isEmpty)
        #expect(!session.handle(.space).consumed)
    }

    @Test(arguments: [false, true])
    func deleteConfirmsLiteralAndNextDeleteReturnsToClient(forward: Bool) {
        let (session, defaults) = makeSession(learning: true)
        type("com", session)
        let key: QuickKey = forward ? .forwardDelete : .backspace
        let result = session.handle(key)
        #expect(result.consumed)
        #expect(result.commits == ["com"])
        #expect(session.markedText.isEmpty)
        #expect(!session.handle(key).consumed)
        #expect(defaults.dictionary(forKey: QuickPrefs.learningDataKey) == nil)
    }

    @Test(arguments: Array(".@/_-+:?&=#%!;,'\""))
    func punctuationConfirmsLiteralOnceWithoutConvertingItsWidth(character: Character) {
        let (session, _) = makeSession()
        type("Com", session)
        #expect(QuickKey.separatorCharacter(String(character)) == character)
        let result = session.handle(.separator(character))
        #expect(result.consumed)
        #expect(result.commits == ["Com" + String(character)])
        #expect(session.rawText.isEmpty)
        let next = session.handle(.separator(character))
        #expect(next.consumed)
        #expect(next.commits == [String(character)], "下一個標點不重複前面的英文")
    }

    @Test func gmailDomainConfirmsWithSpaceDotAndDelete() {
        for boundary: QuickKey in [.space, .separator("."), .backspace] {
            let (session, _) = makeSession()
            var committed = ""
            type("gmail", session)
            committed += session.handle(.separator(".")).commits.joined()
            #expect(committed == "gmail.")
            type("com", session)
            committed += session.handle(boundary).commits.joined()
            let suffix = boundary == .space ? " " : boundary == .separator(".") ? "." : ""
            #expect(committed == "gmail.com" + suffix)
            #expect(session.rawText.isEmpty)
        }
    }

    @Test func shiftedDigitSymbolCanConfirmEnglishWithoutSelectingChinese() {
        let (session, _) = makeSession()
        type("gmail", session)
        #expect(!session.handle(.digit(2, shifted: true)).consumed)
        #expect(session.handle(.separator("@")).commits == ["gmail@"])
    }

    @Test func punctuationWithChineseCandidatesKeepsTypedLettersAndHalfWidth() {
        let (session, defaults) = makeSession(learning: true)
        type("aa", session)
        let result = session.handle(.separator("."))
        #expect(result.consumed)
        #expect(result.commits == ["aa."])
        #expect(session.rawText.isEmpty)
        #expect(defaults.dictionary(forKey: QuickPrefs.learningDataKey) == nil)
        for text in ["a", "1", " ", "\t", "\r", "中"] {
            #expect(QuickKey.separatorCharacter(text) == nil)
        }
    }

    @Test(arguments: Array(".,;:?!()[]{}<>\\`~$_^'\""))
    func idlePunctuationStaysHalfWidth(character: Character) {
        let (session, _) = makeSession()
        let result = session.handle(.separator(character))
        #expect(result.consumed)
        #expect(result.commits == [String(character)])
        #expect(session.markedText.isEmpty)
    }

    @Test func punctuationAfterChineseSelectionStaysHalfWidthAndClosesAssociation() {
        let (session, _) = makeSession()
        #expect(startAssociation(session).commits == ["你"])
        #expect(session.isAssociation)
        #expect(session.handle(.separator(".")).commits == ["."])
        #expect(!session.isAssociation)
        #expect(session.handle(.separator("'")).commits == ["'"])
    }

    @Test func englishDigitsAndZeroRemainLiteral() {
        let (session, _) = makeSession()
        type("abc", session)
        for n in [1, 2, 3, 0] { #expect(session.handle(.digit(n, shifted: false)).commits.isEmpty) }
        #expect(session.markedText == "abc1230")
        #expect(session.handle(.enter).commits == ["abc1230"])
        type("of", session)
        session.handle(.digit(0, shifted: false))
        #expect(session.handle(.enter).commits == ["of0"])
        type("of", session)
        session.handle(.digit(9, shifted: false))
        #expect(session.handle(.enter).commits == ["of9"])
    }

    @Test func arrowsWithoutCandidatesReturnToClientWithoutChangingText() {
        let (session, _) = makeSession()
        type("makcheunghei", session)
        for key: QuickKey in [.previousPage, .nextPage, .previousCandidate, .nextCandidate] {
            #expect(!session.handle(key).consumed)
        }
        #expect(session.finishComposition() == "makcheunghei")
    }

    @Test func associationSpaceInsertsSpaceAndClosesWindow() {
        let (session, _) = makeSession()
        startAssociation(session)
        #expect(session.handle(.space).commits == [" "])
        #expect(!session.isAssociation)
        #expect(session.candidates.isEmpty)
    }

    @Test func chineseEnglishAndChineseCanAlternate() {
        let (session, _) = makeSession(candidates: ["ma": ["百"], "of": ["我", "你"]])
        type("ma", session)
        #expect(session.handle(.digit(1, shifted: false)).commits == ["百"])
        type("MakCheungHei", session)
        #expect(session.handle(.enter).commits == ["MakCheungHei"])
        #expect(startAssociation(session).commits == ["你"])
        #expect(session.handle(.digit(1, shifted: true)).commits == ["們"])
    }

    @Test func changingOptionsDuringEnglishDoesNotCreateCandidatesOrChangeCase() {
        let (session, _) = makeSession()
        type("MakCheungHei", session)
        session.updateOptions(fullCharset: true, learning: true)
        #expect(session.markedText == "MakCheungHei")
        #expect(session.candidates.isEmpty)
        #expect(session.finishComposition() == "MakCheungHei")
    }

    @Test func physicalLetterCaseHandlesShiftAndCapsLock() {
        #expect(QuickKey.letterCharacter("m", shifted: false, capsLock: false) == "m")
        #expect(QuickKey.letterCharacter("m", shifted: true, capsLock: false) == "M")
        #expect(QuickKey.letterCharacter("m", shifted: false, capsLock: true) == "M")
        #expect(QuickKey.letterCharacter("M", shifted: true, capsLock: true) == "m")
        #expect(QuickKey.letterCharacter("1", shifted: false, capsLock: false) == nil)
    }

}
