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
    var translation: QuickTranslationSession.Phase? = nil
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
        if let translation {
            switch translation {
            case .ready(let text):
                return min(280, max(160, ceil((text as NSString).size(withAttributes: [.font: font]).width) + 56))
            case .failed: return 230
            default: return 180
            }
        }
        let textWidth = visibleItems.map { ($0.text as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let recommendationWidth: CGFloat = visibleItems.contains(where: \.isAI) ? 14 : 0
        return min(280, max(120, ceil(textWidth) + 56 + recommendationWidth))
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
                } else {
                    ForEach(visibleItems) { item in candidate(item) }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .frame(width: columnWidth, alignment: .leading)
        .foregroundStyle(.primary)
        .background(.clear)
    }

    @ViewBuilder
    private func candidate(_ item: CandidateItem, isTranslation: Bool = false) -> some View {
        Button { onSelect(item.index) } label: {
            HStack(spacing: 10) {
                Text(numberLabel(for: item))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .frame(width: 12, alignment: .leading)
                Text(item.text)
                    .font(.system(size: fontSize, weight: item.index == selectedIndex ? .semibold : .regular))
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
