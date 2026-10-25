import SwiftUI
import IMECore

// MARK: - 詞庫

private struct DictTableRow: Identifiable {
    let id: String
    let key: String
    let word: String
    let weight: UInt32

    static func rows(from records: [DictStore.RecordInfo]) -> [DictTableRow] {
        var occurrences: [String: Int] = [:]
        return records.map { record in
            let baseID = "\(record.key)\u{1f}\(record.word)\u{1f}\(record.weight)"
            let occurrence = occurrences[baseID, default: 0]
            occurrences[baseID] = occurrence + 1
            return DictTableRow(
                id: "\(baseID)\u{1f}\(occurrence)",
                key: record.key,
                word: record.word,
                weight: record.weight
            )
        }
    }
}

struct DictView: View {
    @ObservedObject var model: AppModel

    private var rows: [DictTableRow] { DictTableRow.rows(from: model.dictRows) }
    private var storeUnavailable: Bool { model.store == nil }

    var body: some View {
        if model.settingsMode == .quick { quickBody } else { pinyinBody }
    }

    private var quickBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("速成詞庫").font(.system(size: 26, weight: .semibold))
                Text("按原始次序瀏覽碼表及聯想詞；搜尋不會改變輸入法設定。")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("詞庫類別", selection: $model.quickDictSection) {
                    Text("碼表").tag(QuickDictionarySection.codes)
                    Text("聯想詞").tag(QuickDictionarySection.associations)
                }.pickerStyle(.segmented).frame(maxWidth: 280)
                if model.quickDictSection == .codes {
                    Toggle("檢視完整字集", isOn: $model.quickDictFullCharset).toggleStyle(.switch)
                }
            }.padding(.bottom, 12)
            Table(model.quickDictRows) {
                TableColumn(model.quickDictSection == .codes ? "字碼" : "前字", value: \.key).width(min: 90, ideal: 130)
                if model.quickDictSection == .codes {
                    TableColumn("字根", value: \.roots).width(min: 100, ideal: 150)
                }
                TableColumn(model.quickDictSection == .codes ? "候選" : "續文") { row in
                    Text(row.text).font(Font(CandidateFont.system(size: 13)))
                }.width(min: 120, ideal: 200)
                TableColumn("原序") { row in Text("\(row.position)").monospacedDigit().foregroundStyle(.secondary) }
                    .width(min: 65, ideal: 75)
            }
            .overlay {
                if model.quickDictUnavailable {
                    SettingsEmptyState(title: "未能載入速成詞庫", systemImage: "character.book.closed",
                                       description: "請使用 AFM輸入法安裝包重新安裝，再查看詞庫內容。")
                } else if model.quickDictRows.isEmpty {
                    SettingsEmptyState(title: model.isSearchingQuickDict ? "找不到相符詞條" : "詞庫暫無內容",
                                       systemImage: "magnifyingglass", description: "試試其他字碼或字詞。")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 12) {
                    Button("上一頁") { if model.quickDictPage > 0 { model.quickDictPage -= 1 } }
                        .disabled(model.quickDictPage == 0)
                    Text("第 \(model.quickDictPage + 1) 頁，共 \(model.quickDictPageCount) 頁")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("下一頁") { if model.quickDictPage + 1 < model.quickDictPageCount { model.quickDictPage += 1 } }
                        .disabled(model.quickDictPage + 1 >= model.quickDictPageCount)
                if model.isSearchingQuickDict {
                    Text("搜尋結果：\(model.quickDictTotalCount) 條").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.top, 12)
        }
        .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 12)
        .searchable(text: $model.quickDictSearch, placement: .toolbar,
                    prompt: model.quickDictSection == .codes ? "搜尋字碼或中文字" : "搜尋前字或續文")
    }

    private var pinyinBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader

            Table(rows) {
                TableColumn("詞語", value: \.word)
                    .width(min: 120, ideal: 180)
                TableColumn("拼音鍵", value: \.key)
                    .width(min: 150, ideal: 220)
                TableColumn("詞頻") { row in
                    Text(row.weight.formatted())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(min: 90, ideal: 110)
            }
            .overlay {
                if storeUnavailable {
                    SettingsEmptyState(
                        title: "未能載入詞庫",
                        systemImage: "character.book.closed",
                        description: "請使用 AFM輸入法安裝包重新安裝，再查看詞庫內容。"
                    )
                    .padding(24)
                } else if model.dictRows.isEmpty {
                    SettingsEmptyState(
                        title: model.isSearchingDict ? "找不到相符詞條" : "詞庫暫無內容",
                        systemImage: "magnifyingglass",
                        description: !model.isSearchingDict
                            ? "目前沒有可顯示的詞條。"
                            : "試試其他拼音前綴，例如 nihao、nh 或 meibeng。"
                    )
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            pageFooter
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .searchable(text: $model.dictSearch, placement: .toolbar, prompt: "搜尋拼音前綴，例如 nihao、nh")
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("詞庫")
                .font(.system(size: 26, weight: .semibold))
            Text("瀏覽拼音詞條，或按拼音前綴搜尋。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
    }

    private var pageFooter: some View {
        HStack(spacing: 12) {
            if !model.isSearchingDict {
                Button("上一頁") {
                    if model.dictPage > 0 { model.dictPage -= 1 }
                }
                .disabled(model.dictPage == 0)

                Text("第 \(model.dictPage + 1) 頁，共 \(model.dictPageCount) 頁")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("下一頁") {
                    if model.dictPage < model.dictPageCount - 1 { model.dictPage += 1 }
                }
                .disabled(model.dictPage >= model.dictPageCount - 1)
            } else {
                Text("搜尋結果：\(model.dictRows.count) 條")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            if !storeUnavailable, let store = model.store {
                Text("共 \(store.recordCount.formatted()) 條詞庫記錄")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }
}

// MARK: - 個人詞語

struct UserWordsView: View {
    @ObservedObject var model: AppModel

    private var filteredPinyinRows: [AppModel.UserRow] {
        let term = model.userSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return model.userRows }
        return model.userRows.filter { $0.word.localizedCaseInsensitiveContains(term) || $0.pinyin.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        if model.settingsMode == .quick { quickBody } else { pinyinBody }
    }

    private var quickBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("速成個人詞語").font(.system(size: 26, weight: .semibold))
                Text("管理速成選字學習記錄；此頁不會啟用學習功能。")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(.bottom, 12)
            if !model.userMessage.isEmpty { SettingsNotice(model.userMessage).padding(.bottom, 10) }
            Table(model.quickUserRows) {
                TableColumn("字碼", value: \.code).width(min: 90, ideal: 130)
                TableColumn("字根", value: \.roots).width(min: 100, ideal: 150)
                TableColumn("字詞") { row in
                    Text(row.text).font(Font(CandidateFont.system(size: 13, weight: .medium))).contextMenu {
                        Button("刪除「\(row.text)」", role: .destructive) { model.confirmQuickDelete = row }
                    }
                }.width(min: 120, ideal: 200)
                TableColumn("使用次數") { row in Text("\(row.count.formatted()) 次").monospacedDigit().foregroundStyle(.secondary) }
                    .width(min: 100, ideal: 120)
            }
            .overlay {
                if model.quickUserRows.isEmpty {
                    SettingsEmptyState(title: model.quickUserSearch.isEmpty ? "尚未有速成個人詞語" : "找不到相符記錄", systemImage: "person.text.rectangle",
                                       description: model.quickUserSearch.isEmpty ? "開啟速成選字學習後，記錄會顯示在這裡；也可匯入已有記錄。" : "試試其他字碼、字根或字詞。")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 12)
        .searchable(text: $model.quickUserSearch, placement: .toolbar, prompt: "搜尋字碼、字根或字詞")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { model.importQuickUsers() } label: { Label("匯入個人詞語…", systemImage: "square.and.arrow.down") } }
            ToolbarItem { Button { model.confirmQuickClear = true } label: { Label("清空全部", systemImage: "trash") }.disabled(model.quickUserRows.isEmpty) }
            ToolbarItem { Button { model.reloadUserRows() } label: { Label("重新整理", systemImage: "arrow.clockwise") } }
        }
        .confirmationDialog("清空全部速成個人詞語？", isPresented: $model.confirmQuickClear, titleVisibility: .visible) {
            Button("清空全部", role: .destructive) { model.clearQuickUsers() }
            Button("取消", role: .cancel) { }
        } message: { Text("速成個人詞語及其使用次數會一併清除。") }
        .confirmationDialog("刪除速成個人詞語？", item: $model.confirmQuickDelete, titleVisibility: .visible) { entry in
            Button("刪除「\(entry.text)」", role: .destructive) { model.deleteQuickUser(entry) }
            Button("取消", role: .cancel) { }
        } message: { entry in Text("會刪除「\(entry.text)」及其速成學習記錄。") }
    }

    private var pinyinBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("個人詞語")
                    .font(.system(size: 26, weight: .semibold))
                Text("管理拼音已學習的詞語；速成選字學習使用獨立記錄。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)

            if !model.userMessage.isEmpty {
                SettingsNotice(model.userMessage)
                    .padding(.bottom, 10)
            }

            Table(filteredPinyinRows) {
                TableColumn("詞語") { row in
                    Text(row.word)
                        .fontWeight(.medium)
                        .contextMenu {
                            Button("刪除「\(row.word)」", role: .destructive) {
                                model.deleteUser(row.word)
                            }
                        }
                }
                .width(min: 120, ideal: 180)

                TableColumn("拼音鍵", value: \.pinyin)
                    .width(min: 150, ideal: 220)

                TableColumn("使用次數") { row in
                    Text("\(row.count.formatted()) 次")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 120)

                TableColumn("優先分") { row in
                    Text(row.score.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 85, ideal: 100)

                TableColumn("詞頻加成") { row in
                    Text(String(format: "×%.2f", row.boost))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 90)
            }
            .overlay {
                if model.userRows.isEmpty {
                    SettingsEmptyState(
                        title: "尚未有個人詞語",
                        systemImage: "person.text.rectangle",
                        description: "使用輸入法選詞後會自動學習，也可以匯入現有個人詞語。"
                    )
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .searchable(text: $model.userSearch, placement: .toolbar, prompt: "搜尋拼音鍵或詞語")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.importUsers() } label: {
                    Label("匯入個人詞語…", systemImage: "square.and.arrow.down")
                }
                .accessibilityLabel("匯入個人詞語")
            }
            ToolbarItem {
                Button { model.confirmClear = true } label: {
                    Label("清空全部", systemImage: "trash")
                }
                .accessibilityLabel("清空全部個人詞語")
                .disabled(model.userRows.isEmpty)
            }
            ToolbarItem {
                Button { model.reloadUserRows() } label: {
                    Label("重新整理", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel("重新整理個人詞語")
            }
        }
        .confirmationDialog("清空全部個人詞語？", isPresented: $model.confirmClear, titleVisibility: .visible) {
            Button("清空全部", role: .destructive) { model.clearUsers() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("個人詞語及其使用記錄會一併清除。")
        }
    }
}
