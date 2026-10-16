import AppKit
import SwiftUI

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Section("輸入體驗") {
                    ForEach([AppModel.Tab.settings, .dict, .user, .translate, .model]) { tab in
                        Label(tab.title, systemImage: tab.icon).tag(tab)
                            .padding(.vertical, 3)
                    }
                }
                Section("進階") {
                    ForEach([AppModel.Tab.test, .maintenance]) { tab in
                        Label(tab.title, systemImage: tab.icon).tag(tab)
                            .padding(.vertical, 3)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 10) {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                        .resizable().frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AFM輸入法").font(.headline)
                        Text("設定中心").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom) {
                Label("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")",
                      systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationSplitViewColumnWidth(min: 192, ideal: 208, max: 240)
        } detail: {
            Group {
                switch model.tab {
                case .settings: SettingsView(model: model)
                case .dict: DictView(model: model)
                case .user: UserWordsView(model: model)
                case .translate: TranslateView(model: model)
                case .model: ModelView(model: model)
                case .test: TestView(model: model)
                case .maintenance: MaintenanceView(model: model)
                }
            }
            .navigationTitle(model.tab.title)
            .toolbar {
                if [.settings, .dict, .user, .translate, .model].contains(model.tab) {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("設定模式", selection: $model.settingsMode) {
                            ForEach(InputSettingsMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 216)
                        .help("選擇要調整的模式，不會切換系統輸入來源")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .font(.system(size: 13))
        .frame(minWidth: 900, minHeight: 600)
    }

    private var sidebarSelection: Binding<AppModel.Tab?> {
        Binding(get: { model.tab }, set: { if let tab = $0 { model.tab = tab } })
    }
}

@main
struct AFMControlCenter: App {
    var body: some Scene {
        WindowGroup("AFM輸入法") {
            RootView(model: AppModel.shared)
        }
        .defaultSize(width: 1220, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appSettings) {
                Button("設定…") {
                    AppModel.shared.tab = .settings
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",")
            }
            CommandGroup(after: .appSettings) {
                Button("系統輸入來源設定…") { AppModel.shared.openInputSourceSettings() }
                Button("重新檢查系統狀態") { AppModel.shared.refreshStatus() }
                    .disabled(AppModel.shared.maintenanceBusy)
            }
        }
    }
}
