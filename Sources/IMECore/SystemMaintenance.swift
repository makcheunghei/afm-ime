import AppKit
import Carbon
import Foundation

/// 安裝及更新由 .pkg 處理；這裏只維護目前使用者的系統登記。
public enum SystemMaintenance {
    public enum Action: Sendable {
        case resetConfiguration
        case prepareRemoval
    }

    public struct Result: Sendable {
        public let ok: Bool
        public let log: String
    }

    struct Source {
        let handle: Int
        let id: String
        var enabled = true
        var selected = false
        var selectable = true
        var asciiCapable = false

        var isAFM: Bool {
            IMEInstaller.modeIDs.contains(id) || id == IMEInstaller.bundleID
                || IMEInstaller.legacyBundleIDs.contains(id)
        }
    }

    /// 注入系統邊界，讓回歸測試不用改動真正的輸入來源或使用者設定。
    struct Operations {
        var installedURLs: [URL]
        var sources: [Source]
        var resourceIssue: (URL) -> String?
        var select: (Source) -> OSStatus
        var disable: (Source) -> OSStatus
        var register: (URL) -> (status: OSStatus, skipped: Bool)
        var appRegistration: (URL, Bool) -> Result
        var enabledAFMIDs: () -> Set<String>
        var stopEngine: () -> Void
        var clearRegistrationRequest: () -> Void
        var refreshMenu: () -> Void
    }

    public static func perform(_ action: Action) -> Result {
        perform(action, using: liveOperations())
    }

    static func perform(_ action: Action, using ops: Operations) -> Result {
        guard let primary = ops.installedURLs.first else {
            return Result(ok: false, log: "未找到已安裝的 AFM輸入法，請先使用 .pkg 安裝包安裝。\n")
        }
        guard !ops.sources.isEmpty else {
            return Result(ok: false, log: "無法讀取系統輸入來源，未更改任何登記；請在已解鎖的桌面重試。\n")
        }
        let enabled = ops.sources.filter { $0.isAFM && $0.enabled }
        switch action {
        case .resetConfiguration:
            if let issue = ops.resourceIssue(primary) {
                return Result(ok: false, log: "安裝檔案有問題：\(issue)，請使用 .pkg 安裝包重新安裝。\n")
            }
            let registration = ops.appRegistration(primary, true)
            guard registration.ok else { return registration }
            var log = registration.log
            // 即使只收錄拼音，也不能重新註冊整個 bundle，否則會累積來源副本。
            if !ops.sources.contains(where: \.isAFM) {
                let result = ops.register(primary)
                guard result.status == noErr else {
                    return Result(ok: false, log: log + "系統拒絕輸入法登記（\(result.status)），請在系統設定檢查來源。\n")
                }
                log += result.skipped ? "已遞交過相同登記，略過重複要求。\n" : "已遞交輸入法登記，來源仍由系統設定管理。\n"
            }
            ops.refreshMenu()
            guard ops.enabledAFMIDs() == Set(enabled.map(\.id)) else {
                return Result(ok: false, log: log + "來源狀態有變，請在系統設定核對目前啟用的模式。\n")
            }
            return Result(ok: true, log: log + "已重新整理系統登記及選單圖示，保留目前啟用的輸入來源。\n")

        case .prepareRemoval:
            var log = ""
            if enabled.contains(where: \.selected) {
                let alternatives = ops.sources.filter { !$0.isAFM && $0.enabled && $0.selectable }
                guard let fallback = alternatives.first(where: \.asciiCapable) ?? alternatives.first else {
                    return Result(ok: false, log: "沒有可切換的其他輸入來源，未停用 AFM；請先加入 ABC 等鍵盤。\n")
                }
                let status = ops.select(fallback)
                guard status == noErr else {
                    return Result(ok: false, log: "未能切換至其他輸入來源（\(status)），未停用 AFM。\n")
                }
                log += "已切換至其他輸入來源。\n"
            }
            for source in enabled {
                let status = ops.disable(source)
                guard status == noErr else {
                    return Result(ok: false, log: log + "停用 AFM 來源失敗（\(status)），已暫停取消 App 登記。\n")
                }
            }
            guard ops.enabledAFMIDs().isEmpty else {
                return Result(ok: false, log: log + "系統仍有啟用中的 AFM 來源，已暫停取消 App 登記，請在系統設定檢查。\n")
            }
            ops.stopEngine()
            log += "已停用 AFM 輸入來源。\n"
            for url in ops.installedURLs {
                let result = ops.appRegistration(url, false)
                log += result.log
                guard result.ok else { return Result(ok: false, log: log) }
            }
            ops.clearRegistrationRequest()
            ops.refreshMenu()
            return Result(ok: true, log: log + "已完成移除前準備，App 檔案及個人設定仍保留。檔案移除前，macOS 仍可能重新收錄輸入法。\n")
        }
    }

    private static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    private static func liveOperations() -> Operations {
        let refs = IMEInstaller.allSources()
        let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let currentID = current.map { IMEInstaller.strProp($0, kTISPropertyInputSourceID) }
        func flag(_ source: TISInputSource, _ key: CFString) -> Bool {
            guard let value = TISGetInputSourceProperty(source, key) else { return false }
            return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
        }
        let sources = refs.enumerated().map { index, source in
            let id = IMEInstaller.strProp(source, kTISPropertyInputSourceID)
            return Source(handle: index, id: id,
                          enabled: flag(source, kTISPropertyInputSourceIsEnabled),
                          selected: id == currentID,
                          selectable: flag(source, kTISPropertyInputSourceIsSelectCapable),
                          asciiCapable: flag(source, kTISPropertyInputSourceIsASCIICapable))
        }
        let urls = [IMEInstaller.systemIMEURL, IMEInstaller.installedIMEURL(),
                    IMEInstaller.legacySystemIMEURL, IMEInstaller.legacyInstalledIMEURL]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return Operations(
            installedURLs: urls, sources: sources,
            resourceIssue: { IMEInstaller.installationResourceIssue(at: $0) },
            select: { TISSelectInputSource(refs[$0.handle]) },
            disable: { TISDisableInputSource(refs[$0.handle]) },
            register: { url in
                let result = IMEInstaller.register(bundleURL: url)
                return (result.status, result.skipped)
            },
            appRegistration: { url, register in
                let status = run(lsregister, [register ? "-f" : "-u", url.path])
                return Result(ok: status == 0,
                              log: status == 0
                                ? "已\(register ? "更新" : "取消") \(url.lastPathComponent) 的 App 登記。\n"
                                : "\(register ? "更新" : "取消") App 登記失敗（\(status)）。\n")
            },
            enabledAFMIDs: {
                Set(IMEInstaller.afmRefs().filter { flag($0, kTISPropertyInputSourceIsEnabled) }
                    .map { IMEInstaller.strProp($0, kTISPropertyInputSourceID) })
            },
            stopEngine: { _ = run("/usr/bin/killall", ["AFMInput"]) },
            clearRegistrationRequest: { IMEInstaller.clearRegistrationRequest() },
            refreshMenu: { _ = run("/usr/bin/killall", ["TextInputMenuAgent"]) }
        )
    }

    private static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return -1 }
        guard finished.wait(timeout: .now() + 15) == .success else {
            process.terminate()
            return -1
        }
        return process.terminationStatus
    }
}
