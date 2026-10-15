import AppKit
import Carbon
import Foundation

/// 輸入法安裝／啟用／選中；啟用清單由 macOS 管理，不直接覆寫。
/// 经验结论(macOS 27 实测):
/// - TISRegisterInputSource:瞬态注册,持久化靠登录扫描;**对已注册的 bundle 重复调用会多出灰色源实例,必须查重**
/// - TISEnableInputSource 的成功回傳不代表已持久化；以系統設定實際結果為準。
/// - TISSelectInputSource:干净状态下可用;脏状态返回 -50
/// - 卸载必须先 TISDisableInputSource 停用全部实例,否则 TIS 回写会把启用条目带回来
public enum IMEInstaller {
    public static let bundleID = "moe.bemly.inputmethod.AfmIME"
    public static let modeID = "moe.bemly.inputmethod.AfmIME.afmpinyin.hans"
    public static let quickModeID = InputMethodMode.quick.sourceID
    public static let modeIDs = InputMethodMode.allCases.map(\.sourceID)
    /// 历史遗留 id(清理用)
    public static let legacyBundleIDs: Set<String> = [
        "com.afm.inputmethod.afmpinyin", "com.afm.inputmethod.afmpinyin.hans",
        "com.afm.AFMInput", "com.afm.AFMInput.hans",
        "moe.bemly.inputmethod.ime", "moe.bemly.inputmethod.ime.hans",
        "moe.bemly.inputmethod", "moe.bemly.inputmethod.hans",
        "moe.bemly.inputmethod.afmpinyin", "moe.bemly.inputmethod.afmpinyin.hans",
        "moe.bemly.inputmethod.AfmIME.afmpinyin", "moe.bemly.inputmethod.AfmIME.afmpinyin.hans",
    ]
    public static let imeAppName = "AFM輸入法.app"
    public static let legacyIMEAppName = "AFM拼音.app"
    public static let toolboxDomain = "com.apple.HIToolbox" as CFString
    private static let registrationRequestKey = "AFMInputSourceRegistrationRequest"

    // MARK: - 查询

    public static func allSources() -> [TISInputSource] {
        guard let unmanaged = TISCreateInputSourceList(nil, true) else { return [] }
        let arr = unmanaged.takeRetainedValue() as CFArray
        return (0..<CFArrayGetCount(arr)).map {
            unsafeBitCast(CFArrayGetValueAtIndex(arr, $0), to: TISInputSource.self)
        }
    }

    public static func enabledSources() -> [TISInputSource] {
        guard let unmanaged = TISCreateInputSourceList(nil, false) else { return [] }
        let arr = unmanaged.takeRetainedValue() as CFArray
        return (0..<CFArrayGetCount(arr)).map {
            unsafeBitCast(CFArrayGetValueAtIndex(arr, $0), to: TISInputSource.self)
        }
    }

    public static func sourceWithID(_ id: String) -> TISInputSource? {
        enabledSources().first { strProp($0, kTISPropertyInputSourceID) == id }
            ?? allSources().first { strProp($0, kTISPropertyInputSourceID) == id }
    }

    /// 本输入法的全部源实例(含历史遗留 id;可能有重复注册产生的多份)
    public static func afmRefs() -> [TISInputSource] {
        allSources().filter {
            let id = strProp($0, kTISPropertyInputSourceID)
            return modeIDs.contains(id) || id == bundleID || legacyBundleIDs.contains(id)
        }
    }

    public static func strProp(_ src: TISInputSource, _ key: CFString) -> String {
        guard let v = TISGetInputSourceProperty(src, key) else { return "" }
        return Unmanaged<CFString>.fromOpaque(v).takeUnretainedValue() as String
    }

    /// TIS 启用视图中本输入法实例数
    public static func enabledRefCount(for mode: InputMethodMode = .pinyin) -> Int {
        enabledSources().filter { strProp($0, kTISPropertyInputSourceID) == mode.sourceID }.count
    }

    public static func enabledRefCount() -> Int { enabledRefCount(for: .pinyin) }

    public static func registeredModeIDs() -> [String] {
        modeIDs.filter { sourceWithID($0) != nil }
    }

    public static func isRegistered() -> Bool {
        registeredModeIDs().count == modeIDs.count
    }

    public static func installedIMEURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/\(imeAppName)")
    }

    /// 系统级安装位(.pkg 安装器的 payload 目标;/Library 需管理员权限,GUI 换盘不覆盖)
    public static var systemIMEURL: URL {
        URL(fileURLWithPath: "/Library/Input Methods/\(imeAppName)")
    }

    public static var legacyInstalledIMEURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/\(legacyIMEAppName)")
    }

    public static var legacySystemIMEURL: URL {
        URL(fileURLWithPath: "/Library/Input Methods/\(legacyIMEAppName)")
    }

    /// 全部在位安装位(用户级 + 系统级;.pkg 装系统级,GUI/脚本装用户级)
    public static func installedURLs() -> [URL] {
        [installedIMEURL(), systemIMEURL, legacyInstalledIMEURL, legacySystemIMEURL]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func isBundleInstalled() -> Bool {
        FileManager.default.fileExists(atPath: installedIMEURL().path)
            || FileManager.default.fileExists(atPath: systemIMEURL.path)
            || FileManager.default.fileExists(atPath: legacyInstalledIMEURL.path)
            || FileManager.default.fileExists(atPath: legacySystemIMEURL.path)
    }

    /// 本机存在系统级安装(.pkg 安装器管理;GUI 的安装/换盘只管用户级,避免装出双份 bundle)
    public static var isSystemInstalled: Bool {
        FileManager.default.fileExists(atPath: systemIMEURL.path)
            || FileManager.default.fileExists(atPath: legacySystemIMEURL.path)
    }

    /// 当前状态摘要(供 UI 显示)
    public static func statusSummary() -> String {
        let installed = isBundleInstalled()
        if let url = installedURLs().first, let issue = installationResourceIssue(at: url) {
            return "⚠︎ 安裝檔案有問題：\(issue)，請重新安裝修正版。"
        }
        if allSources().isEmpty {
            return "目前無法讀取系統輸入來源；請在已登入及解鎖的桌面重新檢查。"
        }
        let registeredIDs = registeredModeIDs()
        if !registeredIDs.isEmpty && registeredIDs.count < modeIDs.count {
            let registered = InputMethodMode.allCases.filter { registeredIDs.contains($0.sourceID) }.map(\.displayName)
            let missing = InputMethodMode.allCases.filter { !registeredIDs.contains($0.sourceID) }.map(\.displayName)
            return "已收錄 \(registered.joined(separator: "、"))；\(missing.joined(separator: "、")) 尚待系統收錄，請透過系統設定管理所需來源。"
        }
        let registered = registeredIDs.count == modeIDs.count
        let refs = InputMethodMode.allCases.map { enabledRefCount(for: $0) }
        if installed && registered && refs.allSatisfy({ $0 >= 1 }) {
            return "已安裝，系統列出兩種模式；請透過系統設定獨立加入或移除來源。"
        }
        if installed && registered { return "已安装未启用 — 点「安装并启用输入法」" }
        if installed { return "已安装,等待 TIS 收录 — 请注销并重新登录一次" }
        if registered { return "输入源已注册,app 未安装 — 点「安装并启用输入法」" }
        return "未安装 — 点「安装并启用输入法」"
    }

    /// 註冊標記不代表安裝檔案可用；尤其系統級 App 的資源可能屬於 root。
    static func installationResourceIssue(at url: URL) -> String? {
        let requirements: [(String, String, Bool)] = [
            ("Contents/MacOS/AFMInput", "輸入法引擎", true),
            ("Contents/Resources/dict.bin", "拼音詞庫", false),
            ("Contents/Resources/quick.json", "速成詞庫", false),
            ("Contents/PlugIns/AFMSettings.app/Contents/MacOS/AFMSettings", "設定中心", true),
        ]
        let fm = FileManager.default
        for (relative, label, executable) in requirements {
            let path = url.appendingPathComponent(relative).path
            var directory = ObjCBool(false)
            guard fm.fileExists(atPath: path, isDirectory: &directory), !directory.boolValue else {
                DebugLog.log("安裝檔案缺失：\(path)")
                return "缺少\(label)"
            }
            let permissions = (try? fm.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
            guard permissions & 0o444 != 0, fm.isReadableFile(atPath: path),
                  !executable || fm.isExecutableFile(atPath: path) else {
                DebugLog.log("安裝檔案權限錯誤：\(path)")
                return "\(label)無法讀取或執行"
            }
        }
        return nil
    }

    // MARK: - 动作

    @discardableResult
    public static func register(bundleURL: URL) -> (status: OSStatus, skipped: Bool) {
        // 升級新增模式時可能只看見舊拼音；重複註冊整個 bundle 會累積拼音副本。
        // TIS 活視圖亦可能延遲，成功遞交的同一路徑及模式組合只遞交一次。
        let target = installedURLs().first ?? bundleURL
        let request = registrationRequestID(at: target)
        let domain = bundleID as CFString
        let previousRequest = CFPreferencesCopyAppValue(registrationRequestKey as CFString, domain) as? String
        let sourceIDs = Set(allSources().map { strProp($0, kTISPropertyInputSourceID) })
        guard !sourceIDs.isEmpty else {
            DebugLog.log("無法讀取系統輸入來源，暫停註冊以免誤判為首次安裝")
            return (OSStatus(paramErr), false)
        }
        guard registrationIsNeeded(sourceIDs: sourceIDs, requestAlreadySubmitted: previousRequest == request) else {
            DebugLog.log("略過重複註冊；已收錄或已遞交：\(target.path)")
            return (noErr, true)
        }
        let status = TISRegisterInputSource(target as CFURL)
        if status == noErr {
            CFPreferencesSetAppValue(registrationRequestKey as CFString, request as CFString, domain)
            CFPreferencesAppSynchronize(domain)
        }
        DebugLog.log("遞交輸入源註冊：\(target.path)，status=\(status)")
        return (status, false)
    }

    static func registrationIsNeeded(sourceIDs: Set<String>, requestAlreadySubmitted: Bool) -> Bool {
        !requestAlreadySubmitted && sourceIDs.isDisjoint(with: Set(modeIDs + [bundleID]))
    }

    /// 安裝器更換同路徑的 App 後，舊註冊可能失效；只擋同一份檔案的重試。
    static func registrationRequestID(at bundleURL: URL) -> String {
        let executable = bundleURL.appendingPathComponent("Contents/MacOS/AFMInput")
        let attributes = (try? FileManager.default.attributesOfItem(atPath: executable.path)) ?? [:]
        let fileID = (attributes[.systemFileNumber] as? NSNumber)?.stringValue ?? "missing"
        let size = (attributes[.size] as? NSNumber)?.stringValue ?? "missing"
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return ([bundleURL.standardizedFileURL.path, fileID, size, String(modified)] + modeIDs).joined(separator: "|")
    }

    /// 等待条件成立(TIS 状态异步传播,立即查询会误报)
    static func waitUpTo(_ seconds: Double, interval: Double = 0.3, _ cond: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if cond() { return true }
            usleep(useconds_t(interval * 1_000_000))
        }
        return cond()
    }

    /// 安装:拷贝 IME bundle 到 ~/Library/Input Methods 并注册(查重)
    public static func install(embeddedIMEURL: URL) -> String {
        var log = ""
        let fm = FileManager.default
        let dest = installedIMEURL()
        do {
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: embeddedIMEURL, to: dest)
            if fm.fileExists(atPath: legacyInstalledIMEURL.path) {
                try fm.removeItem(at: legacyInstalledIMEURL)
            }
            log += "✓ 已拷贝到 ~/Library/Input Methods\n"
        } catch {
            return log + "✗ 拷贝失败: \(error.localizedDescription)\n"
        }
        let r = register(bundleURL: dest)
        if r.skipped {
            log += "✓ TIS 已注册过(跳过重复注册)\n"
        } else {
            log += "TISRegisterInputSource = \(r.status)\n"
            if waitUpTo(5) { isRegistered() } {
                log += "✓ TIS 已可见\n"
            } else {
                let registered = registeredModeIDs()
                if registered.isEmpty {
                    log += "⚠︎ TIS 暂不可见 — 首次安装请注销并重新登录一次(登录扫描收录后,以后无需再注销)\n"
                } else {
                    let missing = modeIDs.filter { !registered.contains($0) }
                    log += "⚠︎ TIS 部分收錄：已列出 \(registered.joined(separator: ", "))；尚缺 \(missing.joined(separator: ", "))\n"
                }
            }
        }
        return log
    }

    /// 停用本输入法的全部 TIS 实例(卸载/收敛前必须做,否则 TIS 回写复活条目)
    @discardableResult
    public static func disableAll() -> String {
        var log = ""
        for src in afmRefs() {
            let id = strProp(src, kTISPropertyInputSourceID)
            let st = TISDisableInputSource(src)
            if st != noErr { log += "TISDisable(\(id)) = \(st)\n" }
        }
        return log
    }

    /// 僅在使用者明確要求時，透過系統 API 啟用兩種模式。
    @discardableResult
    public static func enable() -> (ok: Bool, log: String) {
        ensureEnabled()
    }

    /// 使用者明確要求啟用兩種模式時，逐一透過 TIS API 啟用；安裝及更新不呼叫。
    public static func ensureEnabled() -> (ok: Bool, log: String) {
        guard !allSources().isEmpty else {
            DebugLog.log("無法讀取系統輸入來源，保留啟用偏好")
            return (false, "目前無法讀取系統輸入來源，未修改啟用設定；請在已登入及解鎖的桌面重試。\n")
        }
        var log = ""
        for mode in InputMethodMode.allCases where enabledRefCount(for: mode) == 0 {
            guard let src = sourceWithID(mode.sourceID) else {
                log += "⚠︎ TIS 尚未列出 \(mode.displayName)(\(mode.sourceID)),請在系統設定加入\n"
                continue
            }
            let status = TISEnableInputSource(src)
            log += "TISEnableInputSource(\(mode.sourceID)) = \(status)\n"
        }
        let viewOK = waitUpTo(3) { InputMethodMode.allCases.allSatisfy { self.enabledRefCount(for: $0) >= 1 } }
        let enabledOK = InputMethodMode.allCases.allSatisfy { enabledRefCount(for: $0) >= 1 }
        if viewOK { log += "✓ 兩種輸入模式均已啟用\n" }
        else { log += "系統尚未確認兩種模式；請在系統設定加入所需來源，啟用清單未被覆寫。\n" }
        return (enabledOK, log)
    }

    @discardableResult
    public static func select() -> (ok: Bool, log: String) {
        select(mode: .pinyin)
    }

    @discardableResult
    public static func select(mode: InputMethodMode) -> (ok: Bool, log: String) {
        guard let src = sourceWithID(mode.sourceID) else {
            return (false, "✗ TIS 中未找到 \(mode.sourceID)\n")
        }
        let st = TISSelectInputSource(src)
        return (st == noErr, "TISSelectInputSource = \(st)\(st == noErr ? "（成功）" : "（系統拒絕切換；首次安裝請登出再登入後重試）")\n")
    }

    /// 一键注销:优先 loginwindow 免确认 AppleEvent,失败走 System Events(弹系统确认框)
    @discardableResult
    public static func requestLogout() -> Bool {
        if let s = NSAppleScript(source: "tell application \"loginwindow\" to «event aevtrlgo»") {
            var err: NSDictionary?
            s.executeAndReturnError(&err)
            if err == nil { return true }
        }
        if let s = NSAppleScript(source: "tell application \"System Events\" to log out") {
            var err: NSDictionary?
            s.executeAndReturnError(&err)
            return err == nil
        }
        return false
    }

    /// 启动已安装的输入法 app(imklaunchagent 感知启动有助于 TIS 收录)
    @discardableResult
    public static func launchIMEApp() -> Bool {
        NSWorkspace.shared.open(installedIMEURL())
    }

    /// 重登后收尾:等待登录扫描收录 → 启用 → 选中 → 启动 app
    public static func postLoginFinish() -> (ok: Bool, log: String) {
        var log = ""
        log += waitUpTo(10, interval: 0.5) { self.isRegistered() }
            ? "✓ 登入掃描已收錄 \(modeIDs.joined(separator: ", "))\n"
            : "✗ 等待 10s 仍未收录 — 确认 bundle 在位后,点「安装并启用输入法」再注销一次\n"
        let e = enable()
        log += e.log
        if e.ok {
            log += select().log
            launchIMEApp()
            log += "✓ 输入法已就绪\n"
        }
        return (e.ok, log)
    }

    /// 卸载:停用全部实例 → 删 bundle → defaults 清条目
    @discardableResult
    public static func uninstall() -> String {
        var log = disableAll()
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
        let fm = FileManager.default
        for path in [installedIMEURL().path, systemIMEURL.path, legacyInstalledIMEURL.path, legacySystemIMEURL.path] {
            if fm.fileExists(atPath: path) {
                do { try fm.removeItem(atPath: path); log += "✓ 已删除 \(path)\n" }
                catch { log += "✗ 删除 \(path) 失败(系统目录需要 sudo)\n" }
            }
        }
        cleanDefaults()
        log += "✓ defaults 启用条目已清理\n"
        return log
    }

    static func cleanDefaults() {
        CFPreferencesSetAppValue(registrationRequestKey as CFString, nil, bundleID as CFString)
        CFPreferencesAppSynchronize(bundleID as CFString)
        let allIDs = legacyBundleIDs.union([bundleID]).union(modeIDs)
        for key in ["AppleEnabledInputSources", "AppleSelectedInputSources", "AppleInputSourceHistory"] as [CFString] {
            guard let raw = CFPreferencesCopyAppValue(key, toolboxDomain),
                  let list = (raw as? NSArray) as? [[String: Any]] else { continue }
            let filtered = list.filter { entry in
                let bid = entry["Bundle ID"] as? String
                let mode = entry["Input Mode"] as? String
                return !(allIDs.contains(bid ?? "") || allIDs.contains(mode ?? ""))
            }
            if filtered.count != list.count {
                CFPreferencesSetAppValue(key, filtered as CFArray, toolboxDomain)
            }
        }
        CFPreferencesAppSynchronize(toolboxDomain)
    }
}
