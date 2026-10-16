import SwiftUI
import IMECore

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SettingsPageHeader(title: model.settingsMode == .quick ? "繁體速成" : "拼音輸入",
                                       subtitle: model.settingsMode == .quick
                                       ? "保留熟悉的選字次序，中文英文自然接續。"
                                       : "拼音輸入、個人詞語與 AI 輔助。")
                    if geometry.size.width >= 870 {
                        HStack(alignment: .top, spacing: 28) {
                            settingsForm.frame(maxWidth: .infinity)
                            previewColumn.frame(width: 240)
                                .padding(.leading, 24)
                                .overlay(alignment: .leading) { Divider() }
                        }
                    } else {
                        settingsForm
                        Divider()
                        previewColumn.frame(maxWidth: 420, alignment: .leading)
                    }
                }
                .frame(maxWidth: 1060, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("設定的輸入法", selection: $model.settingsMode) {
                    ForEach(InputSettingsMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented).frame(width: 216)
                .help("選擇要調整的模式，不會切換系統輸入來源")
            }
        }
        .onAppear { updatePreview() }
        .onChange(of: model.settingsMode) { _, _ in updatePreview() }
        .onChange(of: model.quickFullCharset) { _, _ in updatePreview() }
        .onChange(of: model.quickLearning) { _, _ in updatePreview() }
        .onDisappear { model.stopRecording() }
    }

    private var previewColumn: some View {
        InputPreview(preview: model.preview, mode: model.settingsMode, fontSize: model.fontSize)
    }

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: 24) {
            if model.settingsMode == .quick { quickOptions } else { pinyinOptions }
            aiOptions
            if model.settingsMode == .pinyin || model.quickAI {
                SettingsNotice("啟用雲端 AI 會向指定服務商傳送字碼、候選及光標前的部分文字。連線於「AI 模型」管理。")
            }
            SettingsSection(title: "外觀") {
                SettingsRow(title: "候選字體") {
                    HStack(spacing: 10) {
                        Slider(value: $model.fontSize, in: 13...22, step: 1)
                            .frame(minWidth: 90, idealWidth: 150, maxWidth: 180)
                            .accessibilityLabel("候選字體大小")
                        Text("\(Int(model.fontSize)) pt").monospacedDigit()
                            .font(.callout).foregroundStyle(.secondary).frame(width: 35)
                    }
                }
            }
            SettingsNotice("更改即時生效。玻璃外觀及輔助使用效果跟隨 macOS。", systemImage: "checkmark.circle")
            DisclosureGroup("快捷鍵與操作說明") {
                VStack(alignment: .leading, spacing: 20) {
                    shortcuts
                    inputGuide
                }
                .padding(.top, 14)
            }
            .font(.subheadline)
        }
    }

    private var quickOptions: some View {
        SettingsSection(title: "候選與字集") {
            SettingsRow(title: "候選排序", detail: model.quickLearning ? "已啟用個人選字學習" : "沿用 Windows 速成原始次序") {
                Label(model.quickLearning ? "個人次序" : "固定次序", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            Divider()
            SettingsRow(title: "完整字集", detail: "加入擴展字；預設維持 Windows 字集") {
                option("完整字集", $model.quickFullCharset)
            }
            Divider()
            SettingsRow(title: "個人選字學習", detail: "只影響速成排序，與拼音分開") {
                option("個人選字學習", $model.quickLearning)
            }
        }
    }

    private var pinyinOptions: some View {
        SettingsSection(title: "拼音輸入") {
            SettingsRow(title: "模糊拼音", detail: "支援平翹舌音及前後鼻音") { option("模糊拼音", $model.fuzzy) }
            Divider()
            SettingsRow(title: "全形標點", detail: "拼音模式使用中文標點；速成維持半形") { option("拼音全形標點", $model.fullWidthPunct) }
            Divider()
            SettingsRow(title: "個人詞語學習", detail: "記住常用詞語及選字習慣") { option("個人詞語學習", $model.userFreqEnabled) }
        }
    }

    private var aiOptions: some View {
        SettingsSection(title: "AI 輔助") {
            if model.settingsMode == .quick {
                SettingsRow(title: "AI 候選推薦", detail: "保留第一候選，推薦放在第二位 ✦") { option("速成 AI 候選推薦", $model.quickAI) }
                Divider()
                SettingsRow(title: "使用雲端 AI", detail: "預設以本機模型處理") {
                    option("速成使用雲端 AI", $model.quickCloud)
                        .disabled(!model.quickAI || !ModelPrefs.supportsCloudModels)
                }
            } else {
                SettingsRow(title: "AI 候選推薦", detail: "本機模型輔助重排及整句預測") { option("拼音 AI 候選推薦", $model.fmEnhance) }
                Divider()
                SettingsRow(title: "使用雲端 AI", detail: "雲端連線於「AI 模型」管理") {
                    option("拼音使用雲端 AI", $model.cloudEnabled).disabled(!ModelPrefs.supportsCloudModels)
                }
            }
        }
    }

    private var shortcuts: some View {
        SettingsSection(title: "快捷鍵") {
            ForEach(model.hotkeyRows) { row in
                SettingsRow(title: row.title, detail: row.custom ? "已自訂" : nil) {
                    HStack(spacing: 10) {
                        ShortcutKey(text: row.display)
                        if model.recordingHotkey == row.id {
                            Button("取消") { model.stopRecording() }
                        } else {
                            Button("修改") { model.startRecording(row.id) }
                                .accessibilityLabel("修改\(row.title)快捷鍵")
                        }
                    }
                }
                if row.id != model.hotkeyRows.last?.id { Divider() }
            }
            Divider()
            HStack {
                Button("恢復預設快捷鍵") { model.resetHotkeys() }
                Spacer()
            }.padding(16)
            if !model.hotkeyHint.isEmpty {
                Text(model.hotkeyHint).font(.callout).foregroundStyle(.secondary).padding([.horizontal, .bottom], 16)
            }
        }
    }

    private var inputGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.settingsMode == .quick {
                guide("Space", "單字碼直接出字；雙字碼循環翻頁，只有一頁時不作確認。")
                guide("Enter", "輸出原有英文字元，保留大小寫。")
                guide("← →", "切換候選頁。數字或點選確認中文字。")
                guide("1–9", "選擇中文字或聯想詞，兩者操作相同。")
                SettingsNotice("沒有中文候選的英文，遇空白、半形標點或 Delete 即確認。")
                SettingsNotice("開啟雲端 AI 後，會向已設定的服務商傳送速成碼、候選及光標前的部分文字。")
            } else {
                SettingsNotice("輕按 Shift 切換中英文。組詞時按 Control＋F 使用行內翻譯。")
                SettingsNotice("開啟雲端 AI 後，會向已設定的服務商傳送拼音、候選及光標前的部分文字。")
            }
        }
    }

    private func guide(_ key: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ShortcutKey(text: key).frame(width: 66, alignment: .leading)
            Text(text).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func option(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding).toggleStyle(.switch).labelsHidden().accessibilityLabel(label)
    }

    private func updatePreview() { model.preview.configure(mode: model.settingsMode, model: model) }
}
