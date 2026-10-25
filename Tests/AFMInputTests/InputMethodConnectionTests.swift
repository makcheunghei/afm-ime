import Foundation
import InputMethodKit
import Testing
@testable import afm_input

struct InputMethodConnectionTests {
    @Test func usesSystemResolutionWithoutStartingServer() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AFMConnection-\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let id = "test.afm.connection.\(UUID().uuidString)"
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": id, "CFBundlePackageType": "APPL",
        ], format: .xml, options: 0)
        try data.write(to: root.appendingPathComponent("Contents/Info.plist"))
        let bundle = try #require(Bundle(url: root))
        let selector = NSSelectorFromString("connectionNameFor:")
        if IMKServer.responds(to: selector) {
            let systemName = try #require(IMKServer.perform(selector, with: bundle)?.takeUnretainedValue() as? String)
            #expect(InputMethodConnection.name(for: bundle) == systemName)
            if ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 27 {
                // The actual regression: a listening _Connection port cannot receive
                // events when this OS routes clients to .Connection.
                #expect(systemName == id + ".Connection")
                #expect(systemName != id + "_Connection")
            }
        }
    }

    @Test func fallbackPreservesOlderSystemsAndRejectsObsoleteOverrideOn27() {
        #expect(InputMethodConnection.fallback(bundleID: "test.ime", declaredName: "legacy", majorVersion: 26) == "legacy")
        #expect(InputMethodConnection.fallback(bundleID: "test.ime", declaredName: nil, majorVersion: 26) == "test.ime_Connection")
        #expect(InputMethodConnection.fallback(bundleID: "test.ime", declaredName: "legacy", majorVersion: 27) == "test.ime.Connection")
    }
}
