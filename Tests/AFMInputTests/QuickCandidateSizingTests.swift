import Foundation
import Testing
@testable import afm_input

/// 純尺寸計算，不建立 NSPanel、視窗或啟動 App。
struct QuickCandidateSizingTests {
    @Test func longAssociationsFitWithoutDroppingAnyPageItems() {
        let widths: [CGFloat] = [44, 44, 44, 180, 180, 180, 180, 180, 180]
        let fitted = QuickCandidateView.fittedWidths(widths, available: 480)
        #expect(fitted.count == 9)
        #expect(fitted.reduce(0, +) <= 480)
        #expect(fitted.prefix(3) == [44, 44, 44])
        #expect(fitted.allSatisfy { $0 > 0 })
    }

    @Test func shortLastPageKeepsNaturalWidthsAndNarrowScreenStillFits() {
        #expect(QuickCandidateView.fittedWidths([44, 60], available: 600) == [44, 60])
        let fitted = QuickCandidateView.fittedWidths(Array(repeating: 180, count: 9), available: 260)
        #expect(fitted.count == 9)
        #expect(fitted.reduce(0, +) <= 260)
        #expect(QuickCandidateView.fittedWidths([], available: 260).isEmpty)
    }
}
