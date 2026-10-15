import SwiftUI
import AppKit
import IMECore

/// 速成候選／聯想固定以九項單欄呈現；資料與互動狀態由 controller 提供。
struct QuickCandidateView: View {
    var items: [CandidateItem]
    var selectedIndex: Int
    var pageStart: Int
    var pageSize: Int
    var association: Bool
    var onSelect: (Int) -> Void

    private var pageLength: Int { max(1, pageSize) }
    private var visibleItems: [CandidateItem] {
        items.filter { $0.index >= pageStart && $0.index < pageStart + pageLength }
    }
    private var pageNumber: Int { pageStart / pageLength + 1 }
    private var pageCount: Int { max(1, (items.count + pageLength - 1) / pageLength) }
    private var fontSize: CGFloat { CGFloat(UserPrefs.candidateFontSize) }
    private var columnWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let textWidth = visibleItems.map { ($0.text as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(280, max(96, ceil(textWidth) + 42))
    }

    var body: some View {
        VStack(spacing: 4) {
            Text("\(pageNumber)/\(pageCount)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("第 \(pageNumber) 頁，共 \(pageCount) 頁")
            VStack(spacing: 1) {
                ForEach(visibleItems) { item in candidate(item) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: columnWidth + 16, alignment: .leading)
        .background(.clear)
    }

    @ViewBuilder
    private func candidate(_ item: CandidateItem) -> some View {
        Button { onSelect(item.index) } label: {
            HStack(spacing: 6) {
                Text(numberLabel(for: item))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.isAI ? AnyShapeStyle(.cyan) : AnyShapeStyle(.secondary))
                    .frame(width: 24, alignment: .trailing)
                Text(item.text)
                    .font(.system(size: fontSize, weight: item.index == selectedIndex ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 6)
            .frame(height: max(25, fontSize + 8))
            .background {
                if item.index == selectedIndex {
                    Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.text)
        .accessibilityLabel("\(numberLabel(for: item))，\(item.text)")
    }

    private func numberLabel(for item: CandidateItem) -> String {
        let digit = "\(item.index - pageStart + 1)"
        let prefix = association ? "⇧" : ""
        return prefix + digit + (item.isAI ? "✦" : "")
    }
}
