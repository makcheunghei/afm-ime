import Foundation
import Testing
@testable import IMECore

struct QuickDictionaryBrowserTests {
    @Test func codesSortKeysKeepCandidateOrderAndPaginate() {
        let dict = QuickDictionary(
            candidates: ["b": ["乙", "丙"], "a": ["甲", "乙"]],
            fullCandidates: ["a": ["全甲", "全乙"]],
            roots: ["a": "日", "b": "月"]
        )
        let browser = QuickDictionaryBrowser(dictionary: dict)
        let page = browser.page(section: .codes, fullCharset: false, search: "", page: 0, pageSize: 3)
        #expect(page.rows.map(\.key) == ["a", "a", "b"])
        #expect(page.rows.map(\.position) == [1, 2, 1])
        #expect(page.rows.map(\.roots) == ["日", "日", "月"])
        #expect(page.totalCount == 4 && page.pageCount == 2)
        #expect(browser.page(section: .codes, fullCharset: true, search: "a", page: 0).rows.map(\.text) == ["全甲", "全乙"])
    }

    @Test func codeSearchIsAsciiPrefixOrChineseContainsAndRejectsMixedText() {
        let browser = QuickDictionaryBrowser(dictionary: QuickDictionary(candidates: ["ab": ["甲字", "乙"]]))
        #expect(browser.page(section: .codes, fullCharset: false, search: "A", page: 0).rows.map(\.text) == ["甲字", "乙"])
        #expect(browser.page(section: .codes, fullCharset: false, search: "字", page: 0).rows.map(\.text) == ["甲字"])
        #expect(browser.page(section: .codes, fullCharset: false, search: "a字", page: 0).totalCount == 0)
    }

    @Test func associationsSearchPrefixOrContinuationAndPreserveOrder() {
        let browser = QuickDictionaryBrowser(dictionary: QuickDictionary(
            candidates: [:], associations: ["天": ["氣象", "晴天", "雨"]]
        ))
        #expect(browser.page(section: .associations, fullCharset: false, search: "晴", page: 0).rows.map(\.text) == ["晴天"])
        #expect(browser.page(section: .associations, fullCharset: false, search: "天", page: 0).rows.map(\.text) == ["氣象", "晴天", "雨"])
        #expect(browser.page(section: .associations, fullCharset: false, search: "天氣", page: 0).rows.isEmpty)
        #expect(browser.page(section: .associations, fullCharset: false, search: "", page: 0).rows.map(\.position) == [1, 2, 3])
    }
}
