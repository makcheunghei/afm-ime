import Foundation
import SwiftUI
import IMECore

enum InputSettingsMode: String, CaseIterable, Identifiable {
    case pinyin, quick
    var id: String { rawValue }
    var title: String { self == .quick ? "AFM速成" : "AFM拼音" }
}

/// 設定中心的唯讀預覽：查詢正式詞庫，不提交文字、不記錄選字，也不呼叫 AI。
@MainActor
final class InputPreviewModel: ObservableObject {
    @Published var code = "aa" {
        didSet {
            let cleaned = String(code.lowercased().filter { $0.isASCII && $0.isLetter }.prefix(mode == .quick ? 2 : 32))
            if code != cleaned { code = cleaned }
            page = 0
            reload()
        }
    }
    @Published private(set) var candidates: [String] = []
    @Published private(set) var page = 0
    @Published private(set) var selectedIndex = 0
    @Published private(set) var unavailable = false
    private(set) var mode: InputSettingsMode = .quick
    private var quickEngine: QuickEngine?
    private var pinyinStore: DictStore?
    private var fullCharset = false
    private var learning = false

    var pageSize: Int { mode == .quick ? QuickSession.pageSize : 8 }
    var pageCount: Int { max(1, (candidates.count + pageSize - 1) / pageSize) }
    var visibleIndices: Range<Int> {
        let start = min(page * pageSize, candidates.count)
        return start..<min(start + pageSize, candidates.count)
    }

    func configure(mode: InputSettingsMode, model: AppModel) {
        fullCharset = model.quickFullCharset
        learning = model.quickLearning
        pinyinStore = model.store
        if quickEngine == nil, let dictionary = model.quickDictionary {
            quickEngine = QuickEngine(dictionary: dictionary, defaults: model.previewDefaults,
                                      learningStore: model.quickLearningStore)
        }
        if self.mode != mode {
            self.mode = mode
            code = mode == .quick ? "aa" : "nihao"
        } else {
            page = 0
            reload()
        }
    }

    func movePage(_ step: Int) {
        guard pageCount > 1 else { return }
        page = (page + step + pageCount) % pageCount
        selectedIndex = page * pageSize
        DebugLog.log("設定候選預覽翻頁：\(page + 1)/\(pageCount)")
    }

    func select(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        selectedIndex = index
    }

    private func reload() {
        if mode == .quick {
            unavailable = quickEngine == nil
            candidates = quickEngine?.candidates(for: code, fullCharset: fullCharset, learning: learning) ?? []
        } else {
            unavailable = pinyinStore == nil
            if let store = pinyinStore, !code.isEmpty {
                let segmenter = PinyinSegmenter(syllables: store.syllables)
                let key = segmenter.segment(code).first?.syllables.joined(separator: " ") ?? code
                var seen = Set<String>()
                candidates = store.query(prefix: key, exactCap: 8, extCap: 8, scanBudget: 20_000)
                    .map(\.word).filter { seen.insert($0).inserted }
            } else {
                candidates = []
            }
        }
        page = min(page, pageCount - 1)
        selectedIndex = page * pageSize
    }
}

struct InputPreview: View {
    @ObservedObject var preview: InputPreviewModel
    @FocusState private var candidatesFocused: Bool
    let mode: InputSettingsMode
    let fontSize: Double
    var quickLayout: QuickCandidateLayout = .vertical

    private struct PreviewCandidate: Identifiable {
        let index: Int
        let text: String
        var id: String { text }
    }

    private var visibleCandidates: [PreviewCandidate] {
        preview.visibleIndices.map { PreviewCandidate(index: $0, text: preview.candidates[$0]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("候選窗預覽", systemImage: "eye")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Text("今日").font(.system(size: 17))
                    TextField(mode == .quick ? "aa" : "nihao", text: $preview.code)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("預覽字碼")
                        .help("只查詢預覽詞庫，不會提交文字或記錄學習")
                }
                if preview.unavailable {
                    SettingsNotice("未能載入預覽詞庫，請重新安裝 AFM輸入法。", systemImage: "exclamationmark.triangle")
                } else if preview.candidates.isEmpty {
                    SettingsNotice("沒有中文候選，輸入內容會保留為英文。")
                } else if mode == .quick {
                    quickCandidates
                } else {
                    pinyinCandidates
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: mode == .quick && quickLayout == .vertical ? 405 : 160, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5) }
            if mode == .quick {
                Text("每頁最多 9 個候選 · \(quickLayout.title)")
                    .font(.caption).foregroundStyle(.secondary)
                shortcut("← →", "切換候選頁")
                shortcut("1–9", "選字或選聯想")
                shortcut("⌃F", "翻譯目前字詞；1 選譯文")
                shortcut("Space", "不確認翻譯")
                shortcut("Enter", "輸出原文字碼")
                shortcut("Esc", "返回原文字碼")
            } else {
                Text("拼音候選條的字體及詞庫預覽。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("預覽不會改動文件或選字記錄。")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var quickCandidates: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Spacer()
                Text("\(preview.page + 1)/\(preview.pageCount)").monospacedDigit()
            }
            .font(.caption).padding(.horizontal, 8).padding(.bottom, 5)
            let layout = quickLayout == .horizontal
                ? AnyLayout(HStackLayout(spacing: 2)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
            layout {
              ForEach(visibleCandidates) { candidate in
                let index = candidate.index
                Button {
                    preview.select(index)
                    candidatesFocused = true
                } label: {
                    HStack(spacing: quickLayout == .horizontal ? 5 : 12) {
                        Text("\(index % preview.pageSize + 1)")
                            .font(.system(size: 11)).frame(width: 10)
                        Text(preview.candidates[index])
                            .font(Font(CandidateFont.system(size: fontSize, weight: preview.selectedIndex == index ? .semibold : .regular)))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .frame(minHeight: 28)
                    .background(.primary.opacity(preview.selectedIndex == index ? 0.09 : 0), in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("候選 \(index % preview.pageSize + 1)，\(preview.candidates[index])")
                .accessibilityAddTraits(preview.selectedIndex == index ? [.isSelected] : [])
              }
            }
        }
        .foregroundStyle(.primary)
        .padding(9)
        .frame(width: quickLayout == .vertical ? 152 : nil)
        .frame(maxWidth: quickLayout == .horizontal ? .infinity : nil)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .focusable()
        .focused($candidatesFocused)
        .onKeyPress(.leftArrow) { preview.movePage(-1); return .handled }
        .onKeyPress(.rightArrow) { preview.movePage(1); return .handled }
        .help("聚焦此預覽後，使用左右方向鍵翻頁")
    }

    private var pinyinCandidates: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
            ForEach(visibleCandidates) { candidate in
                let index = candidate.index
                    HStack(spacing: 5) {
                        Text("\(index + 1)").font(.caption)
                        Text(preview.candidates[index]).font(.system(size: fontSize))
                    }
                    .fixedSize()
                }
            }
            .padding(12)
        }
        .scrollIndicators(.hidden)
        .glassEffect(.regular, in: .capsule)
    }

    private func shortcut(_ key: String, _ title: String) -> some View {
        HStack(spacing: 10) {
            ShortcutKey(text: key)
            Text(title).font(.callout).foregroundStyle(.secondary)
        }
    }
}
