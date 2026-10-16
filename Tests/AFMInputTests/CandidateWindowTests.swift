import AppKit
import SwiftUI
import Testing
import IMECore
@testable import afm_input

@Suite(.serialized)
@MainActor
struct CandidateWindowTests {
    @Test func quickPanelNeverTakesKeyboardFocus() throws {
        _ = NSApplication.shared
        let controller = CandidateWindowController()
        defer { controller.hide() }
        controller.showQuick(items: [CandidateItem(index: 0, text: "測", isAI: false)],
                             selectedIndex: 0, pageStart: 0, association: false,
                             caretRect: .null, onSelect: { _ in })
        let panel = try #require(NSApplication.shared.windows.first {
            $0.title == "AFM速成候選" && $0.isVisible
        })
        #expect(!panel.canBecomeKey, "點候選時，輸入中的應用程式保留鍵盤焦點")
        #expect(!panel.isKeyWindow)
    }

    @Test(arguments: QuickCandidateLayout.allCases)
    func quickPanelShowsAtMostNineItemsAndResizesLastPage(layout: QuickCandidateLayout) {
        _ = NSApplication.shared
        let controller = CandidateWindowController()
        defer { controller.hide() }
        let items = (0..<11).map { CandidateItem(index: $0, text: "字\($0)", isAI: false) }
        controller.showQuick(items: items, selectedIndex: 0, pageStart: 0,
                             association: false, layout: layout, caretRect: .null, onSelect: { _ in })
        let firstPage = controller.currentFrame
        controller.showQuick(items: items, selectedIndex: 9, pageStart: 9,
                             association: false, layout: layout, caretRect: .null, onSelect: { _ in })
        let lastPage = controller.currentFrame
        #expect(firstPage.width >= 120)
        if layout == .vertical {
            #expect(firstPage.height - lastPage.height >= 7 * 28)
            #expect(lastPage.height > 2 * 28)
        } else {
            #expect(firstPage.width > lastPage.width)
            #expect(firstPage.height == lastPage.height)
        }
    }

    @Test func candidateIdentitySurvivesAIReranking() {
        let original = CandidateItem(index: 5, text: "測試", isAI: false)
        let reranked = CandidateItem(index: 1, text: "測試", isAI: true)
        #expect(original.id == reranked.id)
        #expect(original.id != CandidateItem(index: 5, text: "其他", isAI: false).id)
    }

    @Test func pinyinPanelFollowsEveryAvailableCaretScreen() throws {
        _ = NSApplication.shared
        #expect(!NSScreen.screens.isEmpty)
        let controller = CandidateWindowController()
        defer { controller.hide() }
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            controller.show(items: [CandidateItem(index: 0, text: "測試", isAI: false)],
                        selectedIndex: 0, expanded: false, translation: nil,
                        droplet: CandidateDropletModel.shared,
                        caretRect: NSRect(x: visible.midX, y: visible.midY, width: 1, height: 18),
                        onSelect: { _ in })
            let frame = controller.currentFrame
            #expect(visible.contains(NSPoint(x: frame.midX, y: frame.midY)))
        }
    }
}
