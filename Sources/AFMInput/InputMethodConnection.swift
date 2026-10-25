import Foundation
import InputMethodKit

/// Use the same bundle-to-connection resolution as imklaunchagent.
/// macOS 27.0.1 ignores third-party InputMethodConnectionName overrides and
/// resolves `<bundleID>.Connection`; older systems used `_Connection`.
/// The optional runtime selector is read-only: never instantiate a second IMKServer.
enum InputMethodConnection {
    static func name(for bundle: Bundle) -> String {
        let selector = NSSelectorFromString("connectionNameFor:")
        if IMKServer.responds(to: selector),
           let name = IMKServer.perform(selector, with: bundle)?.takeUnretainedValue() as? String,
           !name.isEmpty {
            return name
        }
        return fallback(bundleID: bundle.bundleIdentifier ?? "moe.bemly.inputmethod.AfmIME",
                        declaredName: bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
                        majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    static func fallback(bundleID: String, declaredName: String?, majorVersion: Int) -> String {
        if majorVersion >= 27 { return bundleID + ".Connection" }
        return declaredName.flatMap { $0.isEmpty ? nil : $0 } ?? bundleID + "_Connection"
    }
}
