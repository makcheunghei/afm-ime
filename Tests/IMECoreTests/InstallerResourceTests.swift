import Foundation
import Testing
@testable import IMECore

struct InstallerResourceTests {
    @Test func partialRegistrationDoesNotRegisterPinyinAgain() {
        #expect(!IMEInstaller.registrationIsNeeded(sourceIDs: [IMEInstaller.modeID], requestAlreadySubmitted: false))
        #expect(!IMEInstaller.registrationIsNeeded(sourceIDs: [IMEInstaller.bundleID], requestAlreadySubmitted: false))
    }

    @Test func pendingRequestDoesNotRepeatWhileTISViewIsEmpty() {
        #expect(!IMEInstaller.registrationIsNeeded(sourceIDs: [], requestAlreadySubmitted: true))
        #expect(IMEInstaller.registrationIsNeeded(sourceIDs: ["com.apple.keylayout.ABC"], requestAlreadySubmitted: false))
    }

    private let files = [
        "Contents/MacOS/AFMInput",
        "Contents/Resources/dict.bin",
        "Contents/Resources/quick.json",
        "Contents/PlugIns/AFMSettings.app/Contents/MacOS/AFMSettings",
    ]

    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AFMInstallTest-\(UUID().uuidString).app")
        for relative in files {
            let file = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: relative.contains("/MacOS/") ? 0o755 : 0o644], ofItemAtPath: file.path)
        }
        return root
    }

    @Test func readableBundlePassesResourceCheck() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(IMEInstaller.installationResourceIssue(at: root) == nil)
    }

    @Test func unreadableQuickDictionaryIsReportedBeforeReadyStatus() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.appendingPathComponent(files[2]).path)
        #expect(IMEInstaller.installationResourceIssue(at: root) == "速成詞庫無法讀取或執行")
    }

    @Test func missingSettingsHelperIsReported() throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent(files[3]))
        #expect(IMEInstaller.installationResourceIssue(at: root) == "缺少設定中心")
    }
}
