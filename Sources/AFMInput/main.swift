import AppKit
import InputMethodKit
import IMECore

// CLI 安装器模式(参考 squirrel --register-input-source 等)
let cliArgs = CommandLine.arguments
if cliArgs.count > 1 {
    let code: Int32
    switch cliArgs[1] {
    case "--register-input-source", "--install": code = Installer.register()
    case "--enable-input-source": code = Installer.enable()
    case "--select-input-source": code = Installer.select()
    case "--select-quick", "--select-quick-input-source": code = Installer.selectQuick()
    case "--check-quick": code = checkQuickData()
    case "--status": code = Installer.status()
    case "--setup": code = Installer.setup() // 单进程连续 register+enable+select,避开 cfprefsd 冲掉瞬态注册
    case "--ensure-enabled": code = Installer.ensureEnabled() // 幂等启用(pkg postinstall 用,已启用不碰活视图)
    case "--uninstall": code = { print(IMEInstaller.uninstall()); return 0 }()
    case "--quit": code = Installer.quitRunning()
    default:
        print("用法: AFMInput [--register-input-source|--enable-input-source|--ensure-enabled|--select-input-source|--select-quick|--check-quick|--status|--setup|--uninstall|--quit]")
        code = 2
    }
    exit(code)
}

/// 資料與按鍵整合驗證；不初始化 IMKServer，不註冊或改變系統輸入來源。
func checkQuickData() -> Int32 {
    if let controllerName = Bundle.main.object(forInfoDictionaryKey: "InputMethodServerControllerClass") as? String,
       NSClassFromString(controllerName) == nil {
        print("IMK controller 類別無法載入：\(controllerName)")
        return 1
    }
    guard let engine = InputController.quickEngine else {
        print("速成資料載入失敗")
        return 1
    }
    let aa = Array("昌晶暑間暗曙昍暙闍閶閽闇晿暏彞龧𣊫𣊭").map(String.init)
    let samples: [String: [String]] = [
        "你": ["們", "我", "老", "等", "死我活", "推我讓"],
        "晶": ["片", "瑩剔透", "瑩", "體", "亮", "狀體", "粒"],
        "香": ["港", "水", "煙", "蕉", "味", "腸", "菸", "包", "菇"],
        "港": ["務局", "口", "都", "澳", "警", "市", "警所", "幣", "務"],
        "好": ["像", "處", "幾", "奇", "手", "轉", "評", "不容易", "看"],
        "暑": ["假", "期", "氣", "熱", "氣逼人"],
    ]
    guard engine.candidates(for: "aa") == aa,
          samples.allSatisfy({ text, expected in Array(engine.associations(after: text).prefix(expected.count)) == expected }),
          engine.candidates(for: "aa", fullCharset: true).starts(with: aa),
          engine.candidates(for: "za", fullCharset: true).contains("　") else {
        print("速成資料與 Windows 參考案例不一致")
        return 1
    }
    let session = QuickSession(engine: engine)
    _ = session.handle(.letter("m"))
    guard session.markedText == "一", session.handle(.space).commits == ["一"], session.code.isEmpty else {
        print("速成 M → 空白 → 一 整合失敗")
        return 1
    }
    session.reset()
    _ = session.handle(.letter("a"))
    _ = session.handle(.letter("a"))
    guard session.handle(.space).commits == ["昌"] else {
        print("速成空白確認首頁候選整合失敗")
        return 1
    }
    session.reset()
    _ = session.handle(.letter("a"))
    _ = session.handle(.letter("a"))
    _ = session.handle(.nextPage)
    session.updateOptions(fullCharset: false, learning: false)
    guard session.handle(.space).commits == ["閶"] else {
        print("速成翻頁／設定快照／空白確認整合失敗")
        return 1
    }
    session.reset()
    _ = session.handle(.letter("o"))
    _ = session.handle(.letter("f"))
    guard session.handle(.digit(2, shifted: false)).commits == ["你"],
          session.handle(.digit(1, shifted: true)).commits == ["們"],
          !session.isAssociation else {
        print("速成聯想提交整合失敗")
        return 1
    }
    let start = Date()
    let lookupCodes = ["aa", "of", "ha", "hu", "a", "za", "bu", "ub", "nx", "ux"]
    var checkedCandidates = 0
    for index in 0..<10_000 {
        checkedCandidates &+= engine.candidates(for: lookupCodes[index % lookupCodes.count], fullCharset: true).count
    }
    let averageMS = Date().timeIntervalSince(start) * 1000 / 10_000
    print("速成驗證通過：M 空白確認一、aa 18 字、六組聯想、翻頁確認、聯想提交、完整字集及 Unicode")
    print(String(format: "全字集查表平均 %.4f ms（10,000 次，候選數校驗 %d）", averageMS, checkedCandidates))
    return 0
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer?
    /// 构建标记:日志里区分新旧进程(重装后防 launchd 复活旧二进制)
    static let buildTag = "20261015-space-confirm1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 幽灵副本自愈(必须先于 IMKServer 初始化——副本若用同一连接名起完整引擎,会劫持客户端
        // 的 IMK 连接,退出后连接断掉,表现为全局打不了字,kb32 时代 23:03 事故实锤):
        // 从非安装位置被点击启动时,同步清自己的 LaunchServices 注册后立即退出,不碰任何引擎设施
        if IMEInstaller.isBundleInstalled(),
           !IMEInstaller.installedURLs().contains(where: {
               $0.standardizedFileURL.path == Bundle.main.bundleURL.standardizedFileURL.path
           }) {
            DebugLog.log("幽灵副本启动(\(Bundle.main.bundleURL.path))→ 自清 LaunchServices 注册并退出(不初始化引擎)")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
            p.arguments = ["-u", Bundle.main.bundleURL.path]
            do { try p.run(); p.waitUntilExit() } catch { }
            exit(0)
        }
        let connName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String) ?? "AFMInput_Connection"
        server = IMKServer(name: connName, bundleIdentifier: Bundle.main.bundleIdentifier)
        ClipboardMonitor.shared.start() // 剪贴板历史(⌃V 面板数据源,轮询 changeCount)
        ShiftModeMonitor.start() // Shift 中英切换监听(需输入监控权限,失败会记日志并在 activateServer 重试)
        DebugLog.log("输入法启动 build=\(Self.buildTag): bundle=\(Bundle.main.bundleIdentifier ?? "?") connection=\(connName) debug=\(DebugLog.isDebug) 日志=\(DebugLog.logPath) 词库引擎=\(InputController.engine != nil)")
        DebugLog.log("设置: 英文=\(UserPrefs.englishMode) 模糊=\(UserPrefs.fuzzyPinyin) 全角=\(UserPrefs.fullWidthPunct) FM=\(UserPrefs.fmEnhance) 词频=\(UserPrefs.userFreq) 字号=\(UserPrefs.candidateFontSize)(设置中心写入)")
        // 直接打开引擎 bundle(未安装态,如从 build/DMG 双击)→ 自动拉起设置中心完成一键安装;
        // 已安装后 launchd 按需拉起时 bundle 在安装位置,不会走这一支
        if !IMEInstaller.isBundleInstalled() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.openSettingsHelper()
            }
        }
        NSLog("[AFM] IMKServer 已启动 build=\(Self.buildTag) connection=%@ bundle=%@", connName, Bundle.main.bundleIdentifier ?? "?")
    }

    private func openSettingsHelper() {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/AFMSettings.app")
        guard FileManager.default.fileExists(atPath: url.path) else {
            DebugLog.error("设置中心 helper 缺失: \(url.path)")
            return
        }
        DebugLog.log("開啟設定中心")
        NSWorkspace.shared.open(url)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DebugLog.log("使用者重開輸入法 App → 開啟設定中心")
        openSettingsHelper()
        return false
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.prohibited)
app.run()
