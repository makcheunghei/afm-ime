import SwiftUI
import AppKit
import IMECore

/// Quick 輸入法候選面板。資料與互動狀態由 controller 提供，避免使用 CLT 不支援的狀態宏。
struct QuickCandidateView: View {
    var items: [CandidateItem]
    var selectedIndex: Int
    var pageStart: Int
    var pageSize: Int
    var expanded: Bool
    var association: Bool
    var onSelect: (Int) -> Void
    var onPreviousPage: () -> Void
    var onNextPage: () -> Void
    var onToggleExpand: () -> Void

    private var pageCapacity: Int { max(1, pageSize) * (expanded ? 2 : 1) }
    private var visibleStart: Int { max(0, pageStart / pageCapacity * pageCapacity) }
    private var visibleItems: [CandidateItem] {
        let end = visibleStart + pageCapacity
        return items.filter { $0.index >= visibleStart && $0.index < end }
    }
    private var leftColumnItems: [CandidateItem] {
        visibleItems.filter { $0.index < visibleStart + max(1, pageSize) }
    }
    private var rightColumnItems: [CandidateItem] {
        visibleItems.filter { $0.index >= visibleStart + max(1, pageSize) }
    }
    private var canPage: Bool { items.count > max(1, pageSize) }
    private var pageNumber: Int { pageStart / max(1, pageSize) + 1 }
    private var pageCount: Int { max(1, (items.count + max(1, pageSize) - 1) / max(1, pageSize)) }
    private var fontSize: CGFloat { CGFloat(UserPrefs.candidateFontSize) }
    private var columnWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize)
        let textWidth = visibleItems.map { ($0.text as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(300, max(124, ceil(textWidth) + 64))
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                Text(association ? "聯想" : "候選")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if canPage {
                    Text("\(pageNumber)/\(pageCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: onPreviousPage) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canPage)
                .help("上一頁")
                Button(action: onNextPage) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canPage)
                .help("下一頁")
                Button(action: onToggleExpand) {
                    Image(systemName: expanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                }
                .help(expanded ? "收起候選" : "展開候選")
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(alignment: .top, spacing: 2) {
                    VStack(spacing: 2) {
                        ForEach(leftColumnItems) { item in candidate(item) }
                    }
                    .frame(width: columnWidth)
                    VStack(spacing: 2) {
                        ForEach(rightColumnItems) { item in candidate(item) }
                    }
                    .frame(width: columnWidth)
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(visibleItems) { item in candidate(item) }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: columnWidth * (expanded ? 2 : 1) + (expanded ? 2 : 0) + 24, alignment: .leading)
        .background(.clear)
    }

    @ViewBuilder
    private func candidate(_ item: CandidateItem) -> some View {
        Button { onSelect(item.index) } label: {
            HStack(spacing: 7) {
                Text(numberLabel(for: item))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.isAI ? AnyShapeStyle(.cyan) : AnyShapeStyle(.secondary))
                    .frame(width: 28, alignment: .trailing)
                Text(item.text)
                    .font(.system(size: fontSize, weight: item.index == selectedIndex ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .frame(height: max(29, fontSize + 12))
            .background {
                if item.index == selectedIndex {
                    Capsule().fill(.clear).glassEffect(.regular, in: Capsule())
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOnActivePage(item) ? item.text : "\(item.text)（可直接點選，或先翻頁再用數字鍵選字）")
        .accessibilityLabel(numberLabel(for: item).isEmpty ? item.text : "\(numberLabel(for: item))，\(item.text)")
    }

    private func isOnActivePage(_ item: CandidateItem) -> Bool {
        (pageStart..<pageStart + max(1, pageSize)).contains(item.index)
    }

    private func numberLabel(for item: CandidateItem) -> String {
        // 展開時同時展示兩頁；數字鍵只對目前頁生效，其他頁不能顯示同一組快捷鍵。
        guard isOnActivePage(item) else { return item.isAI ? "✦" : "" }
        let digit = "\(item.index - pageStart + 1)"
        let prefix = association ? "⇧" : ""
        return prefix + digit + (item.isAI ? "✦" : "")
    }
}
