import AppKit
import SwiftUI
import IMECore

// 設定中心:維護／翻譯／模型／測試四頁。
// 一律走共用 Settings* 元件(頁面、分區、列、提示、空狀態);玻璃只交給系統
// navigation/toolbar chrome,內容區使用標準實色表面。
// 模型綁定與動作與舊版逐字一致(鍵名／寫入域見 AFMApp.swift 開頭註解)。
// 注意: 禁用 @State/@StateObject 等宏包裝器(保持 CLT 回退構建可用)。

// MARK: - 系統維護

struct MaintenanceView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage(title: "系統維護", subtitle: "檢查輸入來源狀態，整理系統配置及移除前的註冊。") {
            SettingsSection(title: "系統狀態", subtitle: "安裝及更新請使用 AFM輸入法安裝包。") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.status).font(.callout)
                    if model.maintenanceBusy {
                        ProgressView("正在處理系統配置…").controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }

            SettingsSection(title: "重新設定系統配置",
                            subtitle: "重新整理系統登記及選單圖示，保留目前已啟用的輸入來源、詞庫及模型設定。") {
                HStack(spacing: 10) {
                    Button("重新設定系統配置") { model.performMaintenance(.resetConfiguration) }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.maintenanceBusy)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }

            SettingsSection(title: "移除前準備",
                            subtitle: "停用 AFM 輸入來源並取消 App 的系統登記，保留 App 檔案及個人設定。準備移除或重新安裝時使用。") {
                HStack(spacing: 10) {
                    Button("預先移除系統註冊…", role: .destructive) { model.confirmPrepareRemoval = true }
                        .buttonStyle(.bordered)
                        .disabled(model.maintenanceBusy)
                        .confirmationDialog("預先移除 AFM 的系統註冊？",
                                            isPresented: $model.confirmPrepareRemoval,
                                            titleVisibility: .visible) {
                            Button("停用並移除註冊", role: .destructive) { model.performMaintenance(.prepareRemoval) }
                            Button("取消", role: .cancel) { }
                        } message: {
                            Text("會先切換至其他鍵盤，再停用 AFM 來源。不會刪除 App、詞庫或模型設定；App 檔案移除前，macOS 仍可能重新收錄輸入法。")
                        }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }

            if !model.maintenanceLog.isEmpty {
                SettingsSection(title: "處理結果") {
                    Text(model.maintenanceLog)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { model.refreshStatus() } label: { Label("重新檢查", systemImage: "arrow.clockwise") }
                    .disabled(model.maintenanceBusy)
            }
            ToolbarItem {
                Button { model.openInputSourceSettings() } label: { Label("系統輸入來源設定", systemImage: "slider.horizontal.3") }
            }
        }
    }
}

// MARK: - 翻譯(端側 FM,中↔英方向自動)

struct TranslateView: View {
    @ObservedObject var model: AppModel

    private var inputEmpty: Bool {
        model.translateInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        SettingsPage(title: "翻譯", subtitle: model.settingsMode == .quick
                     ? "速成模式翻譯繁體中文；可選擇本機模型或已設定的雲端連線。"
                     : "自動判斷中英方向，使用拼音模式的模型設定。") {
            if model.settingsMode == .quick {
                SettingsSection(title: "翻譯方式", subtitle: "獨立翻譯設定，不依賴速成輸入的 AI 開關。") {
                    SettingsRow(title: "使用雲端翻譯", detail: "關閉時只使用本機模型") {
                        Toggle("使用雲端翻譯", isOn: $model.quickTranslationCloud).toggleStyle(.switch).labelsHidden()
                            .disabled(!ModelPrefs.supportsCloudModels)
                            .accessibilityLabel("速成使用雲端翻譯")
                    }
                }
                SettingsNotice("雲端翻譯預設關閉；開啟後只向已設定的服務商傳送要翻譯的原文。")
            }
            SettingsSection(title: "原文", subtitle: "方向自動：\(model.translateDirection)") {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $model.translateInput)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 130)
                        .padding(8)
                        .accessibilityLabel("翻譯原文")
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    HStack(spacing: 10) {
                        Button(model.translating ? "翻譯中…" : "翻譯") { model.submitTranslate() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.translating || inputEmpty)
                        if model.translating { ProgressView().controlSize(.small) }
                        Spacer(minLength: 0)
                        if !model.translateInput.isEmpty || !model.translateResult.isEmpty {
                            Button("清除") {
                                model.translateInput = ""
                                model.translateResult = ""
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }

            SettingsSection(title: "譯文") {
                if model.translateResult.isEmpty {
                    SettingsEmptyState(title: "尚未翻譯",
                                       systemImage: "text.bubble",
                                       description: "在上方輸入內容後按「翻譯」，譯文會顯示在這裡。")
                        .padding(24)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.translateResult)
                            .font(.system(size: 15))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 10) {
                            Button { copyResult() } label: { Label("複製譯文", systemImage: "doc.on.doc") }
                                .buttonStyle(.bordered)
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
            }

            SettingsNotice(model.settingsMode == .quick
                           ? "速成翻譯支援繁體中文與外文互譯。雲端翻譯關閉時使用本機模型。"
                           : "自動識別中英方向。輸入內容後，按「翻譯」取得結果。")
        }
        .onSubmit { model.submitTranslate() }
    }

    private func copyResult() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(model.translateResult, forType: .string)
    }
}

// MARK: - 模型(kb36:雲端模型 Provider 接入 + FM 提示詞編輯)

struct ModelView: View {
    @ObservedObject var model: AppModel

    private var cloudAvailable: Bool { ModelPrefs.supportsCloudModels }

    var body: some View {
        SettingsPage(title: "AI 模型", subtitle: "管理共用雲端連線，以及目前模式的提示詞。") {
            cloudSection
            promptSections
        }
    }

    // MARK: 雲端模型

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "雲端模型", subtitle: "兩種模式共用下方雲端連線，各自管理功能開關。") {
                if model.settingsMode == .quick {
                    SettingsRow(title: "速成候選推薦使用雲端 AI", detail: "只控制速成候選推薦，不控制翻譯") {
                        Toggle("速成候選推薦使用雲端 AI", isOn: $model.quickCloud).toggleStyle(.switch).labelsHidden()
                            .disabled(!model.quickAI)
                            .accessibilityLabel("速成候選推薦使用雲端 AI")
                    }
                    Divider()
                    SettingsRow(title: "速成使用雲端翻譯", detail: "獨立開關；只傳送要翻譯的原文") {
                        Toggle("速成使用雲端翻譯", isOn: $model.quickTranslationCloud).toggleStyle(.switch).labelsHidden()
                            .accessibilityLabel("速成使用雲端翻譯")
                    }
                } else {
                    SettingsRow(title: "拼音使用雲端 AI", detail: "候選推薦、整句預測及翻譯使用下方連線") {
                        Toggle("拼音使用雲端 AI", isOn: $model.cloudEnabled).toggleStyle(.switch).labelsHidden()
                            .accessibilityLabel("拼音使用雲端 AI")
                    }
                }
                Divider()
                SettingsRow(title: "服務商", detail: "選擇後自動填入地址、格式及模型名") {
                    Picker("服務商", selection: $model.cloudProvider) {
                        ForEach(AppModel.cloudPresets, id: \.id) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .labelsHidden().frame(minWidth: 190, idealWidth: 260, maxWidth: 340)
                }
                Divider()
                SettingsRow(title: "API 格式") {
                    Picker("API 格式", selection: $model.cloudFormat) {
                        Text("OpenAI 相容").tag("openai")
                        Text("Anthropic").tag("anthropic")
                    }
                    .labelsHidden().frame(minWidth: 190, idealWidth: 260, maxWidth: 340)
                }
                Divider()
                SettingsRow(title: "API 位址") {
                    TextField("https://api.example.com/v1", text: $model.cloudBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden().frame(minWidth: 190, idealWidth: 260, maxWidth: 340)
                }
                Divider()
                SettingsRow(title: "API Key", detail: "以明文存於本機輸入法設定") {
                    SecureField("API Key", text: $model.cloudAPIKey)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden().frame(minWidth: 190, idealWidth: 260, maxWidth: 340)
                }
                Divider()
                SettingsRow(title: "模型名") {
                    TextField("服務商提供的模型 ID", text: $model.cloudModel)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden().frame(minWidth: 190, idealWidth: 260, maxWidth: 340)
                }
                Divider()
                SettingsRow(title: "測試連線", detail: "向指定服務商發送一個簡短請求") {
                    HStack(spacing: 10) {
                        Button(model.cloudTesting ? "測試中…" : "測試") { model.testCloud() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.cloudTesting || model.cloudBaseURL.isEmpty || model.cloudModel.isEmpty)
                        if model.cloudTesting { ProgressView().controlSize(.small) }
                    }
                    .fixedSize()
                }
                if !model.cloudTestResult.isEmpty {
                    Text(model.cloudTestResult)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                }
            }
            .disabled(!cloudAvailable)

            if !cloudAvailable {
                SettingsNotice("雲端 AI 需要 macOS 27 或以上；目前可使用本機 AI 及詞庫輸入。",
                               systemImage: "exclamationmark.triangle")
            }
            SettingsNotice("雲端候選推薦會傳送字碼、候選及光標前的部分文字；雲端翻譯只傳送要翻譯的原文。遠端連線須使用 HTTPS；本機服務可使用 HTTP。")
        }
    }

    // MARK: 提示詞(草稿-應用模式不變:編輯不落盤,按「套用提示詞」才寫入)

    private var promptSections: some View {
        VStack(alignment: .leading, spacing: 24) {
            if model.settingsMode == .quick {
                promptSection(title: "提示詞 · 速成候選推薦", subtitle: "只輸出已有候選的序號；不能新增字詞。", text: $model.promptQuickRerank)
                promptSection(title: "提示詞 · 中文→英文", subtitle: "速成行內翻譯與翻譯頁共用；只輸出譯文。", text: $model.promptQuickTranslateEN)
                promptSection(title: "提示詞 · 外文→繁體中文", subtitle: "速成行內翻譯與翻譯頁共用；預設使用香港繁體中文。", text: $model.promptQuickTranslateZH)
            } else {
            promptSection(title: "提示詞 · 候選重排",
                          subtitle: "只輸出序號數字；請保留格式約束，輸出無法解析時會自動回退詞典。",
                          text: $model.promptRerank)
            promptSection(title: "提示詞 · 整句預測",
                          subtitle: "只輸出中文；用於詞典切不出整句時的兜底。",
                          text: $model.promptSentence)
            promptSection(title: "提示詞 · 翻譯(中文→英)",
                          subtitle: "只輸出譯文；與翻譯頁共用同一份設定。",
                          text: $model.promptTranslateEN)
            promptSection(title: "提示詞 · 翻譯(外文→中)",
                          subtitle: "只輸出譯文；與翻譯頁共用同一份設定。",
                          text: $model.promptTranslateZH)
            }

            SettingsSection(title: "提示詞操作",
                            subtitle: "只套用目前模式草稿；與內置預設一致的段落不落盤，可跟隨程式更新。") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Button("套用提示詞") { model.applyPrompts() }
                            .buttonStyle(.borderedProminent)
                        Button("恢復全部預設") { model.resetPrompts() }
                            .buttonStyle(.bordered)
                        Spacer(minLength: 0)
                        if !model.promptAppliedHint.isEmpty {
                            Text(model.promptAppliedHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    SettingsNotice("請保留每段提示詞的輸出格式要求；未能解析的回應會自動回退至詞庫。")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
    }

    private func promptSection(title: String, subtitle: String, text: Binding<String>) -> some View {
        SettingsSection(title: title, subtitle: subtitle) {
            TextEditor(text: text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .accessibilityLabel(title)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
        }
    }
}

// MARK: - 測試(實驗性互動效果開關)

struct TestView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsPage(title: "實驗功能", subtitle: "拼音專用互動功能；下一次拖拽即會生效。") {
            SettingsSection(title: "拼音水滴拖拽",
                            subtitle: "只影響拼音候選條的選中水滴。") {
                SettingsRow(title: "固定透鏡拖拽", detail: "水滴釘在螢幕抓取點，候選條隨手指平移滑過。") {
                    Toggle("固定透鏡拖拽", isOn: $model.dropletFixedLens).toggleStyle(.switch).labelsHidden()
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("開：按住水滴後它釘在原地(螢幕固定透鏡)，整條候選條(玻璃及文字)隨手指平移、從水滴下面滑過，鬆手上屏水滴正下方的候選。")
                    Text("關(預設)：水滴在候選條內隨手指滑動，候選條不動。")
                    Text("下一次按住拖拽即按新模式。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
        }
    }
}
