import AppKit
import Foundation
import IMECore

// CLI 安装器(Squirrel/KeyTao 同款参数),逻辑在 IMECore.IMEInstaller
enum Installer {
    static func register() -> Int32 {
        let url = Bundle.main.bundleURL
        let registeredBefore = IMEInstaller.registeredModeIDs()
        let st = IMEInstaller.register(bundleURL: url)
        if st.skipped {
            if IMEInstaller.isRegistered() {
                print("兩種輸入模式已完整註冊，跳過重複註冊")
            } else {
                print("已收錄部分模式或已遞交註冊，跳過重複註冊以免累積副本；等待登入掃描補齊模式。")
            }
            return 0
        }
        print("TISRegisterInputSource(\(url.path)) = \(st.status)")
        guard st.status == noErr else { return 1 }
        if IMEInstaller.isRegistered() {
            print("註冊生效：\(IMEInstaller.modeIDs.joined(separator: ", "))")
            return 0
        }
        let registeredAfter = IMEInstaller.registeredModeIDs()
        if !registeredAfter.isEmpty {
            let missing = IMEInstaller.modeIDs.filter { !registeredAfter.contains($0) }
            let prior = registeredBefore.isEmpty ? "" : "（註冊前已部分收錄：\(registeredBefore.joined(separator: ", "))）"
            print("⚠︎ 輸入源部分註冊\(prior)：目前已收錄 \(registeredAfter.joined(separator: ", "))；尚缺 \(missing.joined(separator: ", "))")
            print("註冊請求已遞交；首次新增模式請登出再登入，以完成系統收錄。")
            return 0
        }
        print("註冊請求已遞交，TIS 尚未列出輸入模式；首次安裝請登出再登入。")
        return 0
    }

    static func status() -> Int32 {
        print(IMEInstaller.statusSummary())
        guard !IMEInstaller.allSources().isEmpty else { return 0 }
        for mode in InputMethodMode.allCases {
            let registered = IMEInstaller.sourceWithID(mode.sourceID) != nil
            let enabled = IMEInstaller.enabledRefCount(for: mode)
            print("\(mode.displayName)：已註冊=\(registered)，啟用實例=\(enabled)")
        }
        return 0
    }

    static func enable() -> Int32 {
        let r = IMEInstaller.enable()
        print(r.log, terminator: "")
        return r.ok ? 0 : 1
    }

    static func select() -> Int32 {
        select(mode: .pinyin)
    }

    static func selectQuick() -> Int32 {
        select(mode: .quick)
    }

    private static func select(mode: InputMethodMode) -> Int32 {
        let r = IMEInstaller.select(mode: mode)
        print(r.log, terminator: "")
        return r.ok ? 0 : 1
    }

    static func setup() -> Int32 {
        var code = register()
        if code == 0 { code = enable() }
        if code == 0 { code = select() }
        return code
    }

    static func ensureEnabled() -> Int32 {
        let r = IMEInstaller.ensureEnabled()
        print(r.log, terminator: "")
        return r.ok ? 0 : 1
    }

    static func quitRunning() -> Int32 {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: IMEInstaller.bundleID) {
            app.terminate()
        }
        return 0
    }
}
