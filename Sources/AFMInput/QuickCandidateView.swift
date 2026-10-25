import SwiftUI
import AppKit
import IMECore

/// 速成候選／聯想共用直排及橫排。玻璃由外層提供，排列不影響選字和翻頁。
struct QuickCandidateView: View {
    var items: [CandidateItem]
    var selectedIndex: Int
    var pageStart: Int
    var pageSize: Int
    var association: Bool
    var translation: QuickTranslationSession.Phase? = nil
    var layout: QuickCandidateLayout = .vertical
    var maximumWidth: CGFloat = 1200
    var fontSize: CGFloat = 16
    var onSelect: (Int) -> Void

    private var pageLength: Int { max(1, min(pageSize, QuickSession.pageSize)) }
    private var visibleItems: [CandidateItem] {
        items.filter { $0.index >= pageStart && $0.index < pageStart + pageLength }
    }
    private var pageNumber: Int { pageStart / pageLength + 1 }
    private var pageCount: Int { max(1, (items.count + pageLength - 1) / pageLength) }
    private var panelWidth: CGFloat {
        min(max(1, maximumWidth), preferredWidth)
    }
    private var preferredWidth: CGFloat {
        let font = CandidateFont.system(size: fontSize, weight: .semibold)
        if let translation {
            switch translation {
            case .ready(let text):
                return min(280, max(160, ceil((text as NSString).size(withAttributes: [.font: font]).width) + 56))
            case .failed: return 230
            default: return 180
            }
        }
        if layout == .horizontal {
            return max(120, horizontalCellWidths.reduce(0, +) + 16 + CGFloat(max(0, visibleItems.count - 1)) * 2)
        }
        let textWidth = visibleItems.map { ($0.text as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let recommendationWidth: CGFloat = visibleItems.contains(where: \.isAI) ? 14 : 0
        return min(280, max(120, ceil(textWidth) + 56 + recommendationWidth))
    }

    private var horizontalCellWidths: [CGFloat] {
        let font = CandidateFont.system(size: fontSize, weight: .semibold)
        let natural = visibleItems.map { item in
            min(180, max(44, ceil((item.text as NSString).size(withAttributes: [.font: font]).width)
                         + 35 + (item.isAI ? 19 : 0)))
        }
        return Self.fittedWidths(natural, available: max(1, maximumWidth - 16 - CGFloat(max(0, natural.count - 1)) * 2))
    }

    /// 空間不足時只收窄較長候選，保留短字寬度；仍顯示同一頁全部項目。
    static func fittedWidths(_ natural: [CGFloat], available: CGFloat) -> [CGFloat] {
        guard !natural.isEmpty, natural.reduce(0, +) > available else { return natural }
        var lower: CGFloat = 0
        var upper = natural.max() ?? 0
        for _ in 0..<24 {
            let limit = (lower + upper) / 2
            if natural.reduce(0, { $0 + min($1, limit) }) > available { upper = limit }
            else { lower = limit }
        }
        return natural.map { min($0, lower) }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(translation == nil ? "\(pageNumber)/\(pageCount)" : "1/1")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityLabel(translation == nil ? "第 \(pageNumber) 頁，共 \(pageCount) 頁" : "翻譯，第 1 頁，共 1 頁")
            VStack(spacing: 2) {
                if let translation {
                    switch translation {
                    case .loading:
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("翻譯中…").font(.system(size: fontSize))
                        }.padding(9)
                    case .ready(let text):
                        candidate(CandidateItem(index: 0, text: text, isAI: false), isTranslation: true)
                    case .failed:
                        Text("翻譯未完成，按 Esc 返回")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).padding(9)
                    case .idle: EmptyView()
                    }
                } else if layout == .horizontal {
                    let widths = horizontalCellWidths
                    HStack(spacing: 2) {
                        ForEach(visibleItems) { item in
                            candidate(item)
                                .frame(width: widths[item.index - pageStart])
                                .clipped()
                        }
                    }
                } else {
                    ForEach(visibleItems) { item in candidate(item) }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .frame(width: panelWidth, alignment: .leading)
        .foregroundStyle(.primary)
        .background(.clear)
    }

    @ViewBuilder
    private func candidate(_ item: CandidateItem, isTranslation: Bool = false) -> some View {
        Button { onSelect(item.index) } label: {
            HStack(spacing: layout == .horizontal && !isTranslation ? 5 : 10) {
                Text(numberLabel(for: item))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .frame(width: 12, alignment: .leading)
                Text(item.text)
                    .font(Font(CandidateFont.system(size: fontSize, weight: item.index == selectedIndex ? .semibold : .regular)))
                    .lineLimit(isTranslation ? 4 : 1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: isTranslation)
                if item.isAI {
                    Text("✦").font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, isTranslation ? 6 : 0)
            .frame(minHeight: max(28, fontSize + 10),
                   maxHeight: isTranslation ? nil : max(28, fontSize + 10))
            .background(.primary.opacity(item.index == selectedIndex ? 0.09 : 0),
                        in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.text)
        .accessibilityLabel("\(isTranslation ? "翻譯" : association ? "聯想" : "候選") \(numberLabel(for: item))，\(item.text)\(item.isAI ? "，AI 推薦" : "")")
        .accessibilityAddTraits(item.index == selectedIndex ? [.isSelected] : [])
    }

    private func numberLabel(for item: CandidateItem) -> String {
        "\(item.index - pageStart + 1)"
    }
}
