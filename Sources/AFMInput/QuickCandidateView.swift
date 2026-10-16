import SwiftUI
import AppKit
import IMECore

/// 速成候選／聯想共用精簡單欄。玻璃只由外層 NSGlassEffectView 提供，選中列不疊玻璃。
struct QuickCandidateView: View {
    var items: [CandidateItem]
    var selectedIndex: Int
    var pageStart: Int
    var pageSize: Int
    var association: Bool
    var onSelect: (Int) -> Void

    private var pageLength: Int { max(1, min(pageSize, QuickSession.pageSize)) }
    private var visibleItems: [CandidateItem] {
        items.filter { $0.index >= pageStart && $0.index < pageStart + pageLength }
    }
    private var pageNumber: Int { pageStart / pageLength + 1 }
    private var pageCount: Int { max(1, (items.count + pageLength - 1) / pageLength) }
    private var fontSize: CGFloat { CGFloat(UserPrefs.candidateFontSize) }
    private var columnWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let textWidth = visibleItems.map { ($0.text as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let recommendationWidth: CGFloat = visibleItems.contains(where: \.isAI) ? 14 : 0
        return min(280, max(120, ceil(textWidth) + 56 + recommendationWidth))
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("\(pageNumber)/\(pageCount)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel("第 \(pageNumber) 頁，共 \(pageCount) 頁")
            VStack(spacing: 2) {
                ForEach(visibleItems) { item in candidate(item) }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .frame(width: columnWidth, alignment: .leading)
        .foregroundStyle(.primary)
        .background(.clear)
    }

    @ViewBuilder
    private func candidate(_ item: CandidateItem) -> some View {
        Button { onSelect(item.index) } label: {
            HStack(spacing: 10) {
                Text(numberLabel(for: item))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .frame(width: 12, alignment: .leading)
                Text(item.text)
                    .font(.system(size: fontSize, weight: item.index == selectedIndex ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.isAI {
                    Text("✦").font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: max(28, fontSize + 10))
            .background(.primary.opacity(item.index == selectedIndex ? 0.09 : 0),
                        in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.text)
        .accessibilityLabel("\(association ? "聯想" : "候選") \(numberLabel(for: item))，\(item.text)\(item.isAI ? "，AI 推薦" : "")")
        .accessibilityAddTraits(item.index == selectedIndex ? [.isSelected] : [])
    }

    private func numberLabel(for item: CandidateItem) -> String {
        "\(item.index - pageStart + 1)"
    }
}
