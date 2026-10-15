import Foundation
import Carbon
import Testing
@testable import IMECore

struct SystemMaintenanceTests {
    @Test func resetPreservesEnabledQuickAndDisabledPinyinWithoutRegisteringAgain() {
        let state = State(sources: [
            source(IMEInstaller.quickModeID, handle: 0, enabled: true),
            source(IMEInstaller.modeID, handle: 1, enabled: false),
        ])
        let result = SystemMaintenance.perform(.resetConfiguration, using: operations(state))

        #expect(result.ok)
        #expect(state.events == ["resource", "app-register", "refresh", "enabled-ids"])
        #expect(state.currentEnabledAFMIDs == [IMEInstaller.quickModeID])
    }

    @Test func resetDoesNotRegisterPinyinWhenOnlyPinyinIsPresent() {
        let state = State(sources: [source(IMEInstaller.modeID, handle: 0, enabled: false)])
        let result = SystemMaintenance.perform(.resetConfiguration, using: operations(state))

        #expect(result.ok)
        #expect(state.events == ["resource", "app-register", "refresh", "enabled-ids"])
        #expect(!state.events.contains("register"))
    }

    @Test func resetWithoutAFMSourcesOnlySubmitsRegistrationAndDoesNotEnableAnything() {
        let state = State(sources: [source("com.apple.keylayout.ABC", handle: 0)])
        let result = SystemMaintenance.perform(.resetConfiguration, using: operations(state))

        #expect(result.ok)
        #expect(state.events == ["resource", "app-register", "register", "refresh", "enabled-ids"])
        #expect(state.currentEnabledAFMIDs.isEmpty)
        #expect(state.sources[0].enabled)
    }

    @Test func prepareRemovalSelectsASCIIThenDisablesEveryAFMHandleOnly() {
        let state = State(sources: [
            source(IMEInstaller.modeID, handle: 10, selected: true),
            source(IMEInstaller.modeID, handle: 11),
            source(IMEInstaller.quickModeID, handle: 12),
            source("com.apple.keylayout.ABC", handle: 20, asciiCapable: true),
            source("com.example.other", handle: 21),
        ])
        let result = SystemMaintenance.perform(.prepareRemoval, using: operations(state))

        #expect(result.ok)
        #expect(state.events == [
            "select:20", "disable:10", "disable:11", "disable:12", "enabled-ids",
            "stop", "app-unregister", "clear-registration", "refresh",
        ])
        #expect(state.sources[3].enabled)
        #expect(state.sources[4].enabled)
        #expect(state.sources[0...2].allSatisfy { !$0.enabled })
    }

    @Test func prepareRemovalWithoutAlternativeDoesNotDisableOrUnregister() {
        let state = State(sources: [source(IMEInstaller.modeID, handle: 1, selected: true)])
        let result = SystemMaintenance.perform(.prepareRemoval, using: operations(state))

        #expect(!result.ok)
        #expect(state.events.isEmpty)
    }

    @Test func prepareRemovalSwitchFailureDoesNotDisableOrUnregister() {
        let state = State(sources: [
            source(IMEInstaller.modeID, handle: 1, selected: true),
            source("com.apple.keylayout.ABC", handle: 2, asciiCapable: true),
        ])
        let result = SystemMaintenance.perform(.prepareRemoval, using: operations(state, selectStatus: -1))

        #expect(!result.ok)
        #expect(state.events == ["select:2"])
    }

    @Test func prepareRemovalDisableFailureDoesNotCancelAppRegistration() {
        let state = State(sources: [
            source(IMEInstaller.modeID, handle: 1, selected: true),
            source("com.apple.keylayout.ABC", handle: 2, asciiCapable: true),
        ])
        let result = SystemMaintenance.perform(.prepareRemoval, using: operations(state, disableStatus: -1))

        #expect(!result.ok)
        #expect(state.events == ["select:2", "disable:1"])
        #expect(!state.events.contains("app-unregister"))
        #expect(!state.events.contains("stop"))
    }

    @Test func prepareRemovalStillEnabledAfterDisableDoesNotCancelAppRegistration() {
        let state = State(sources: [source(IMEInstaller.modeID, handle: 1)])
        let result = SystemMaintenance.perform(.prepareRemoval, using: operations(state, leaveEnabledAfterDisable: true))

        #expect(!result.ok)
        #expect(state.events == ["disable:1", "enabled-ids"])
        #expect(!state.events.contains("app-unregister"))
        #expect(!state.events.contains("stop"))
    }

    @Test func emptySourceViewDoesNotRunAnySideEffectsForEitherAction() {
        for action in [SystemMaintenance.Action.resetConfiguration, .prepareRemoval] {
            let state = State(sources: [])
            let result = SystemMaintenance.perform(action, using: operations(state))

            #expect(!result.ok)
            #expect(state.events.isEmpty)
        }
    }

    @Test func resetResourceFailureStopsBeforeAllOtherSideEffects() {
        let state = State(sources: [source(IMEInstaller.quickModeID, handle: 1)])
        let result = SystemMaintenance.perform(
            .resetConfiguration,
            using: operations(state, resourceIssue: "fixture resource issue")
        )

        #expect(!result.ok)
        #expect(state.events == ["resource"])
    }

    private final class State {
        var sources: [SystemMaintenance.Source]
        var events: [String] = []

        init(sources: [SystemMaintenance.Source]) {
            self.sources = sources
        }

        var currentEnabledAFMIDs: Set<String> {
            Set(sources.filter { $0.isAFM && $0.enabled }.map(\.id))
        }
    }

    private let appURLs = [URL(fileURLWithPath: "/fake/AFM拼音.app")]

    private func operations(
        _ state: State,
        resourceIssue: String? = nil,
        selectStatus: OSStatus = noErr,
        disableStatus: OSStatus = noErr,
        leaveEnabledAfterDisable: Bool = false
    ) -> SystemMaintenance.Operations {
        SystemMaintenance.Operations(
            installedURLs: appURLs,
            sources: state.sources,
            resourceIssue: { _ in
                state.events.append("resource")
                return resourceIssue
            },
            select: { candidate in
                state.events.append("select:\(candidate.handle)")
                return selectStatus
            },
            disable: { candidate in
                state.events.append("disable:\(candidate.handle)")
                if disableStatus == noErr && !leaveEnabledAfterDisable,
                   let index = state.sources.firstIndex(where: { $0.handle == candidate.handle }) {
                    state.sources[index].enabled = false
                }
                return disableStatus
            },
            register: { _ in
                state.events.append("register")
                return (noErr, false)
            },
            appRegistration: { _, register in
                state.events.append(register ? "app-register" : "app-unregister")
                return SystemMaintenance.Result(ok: true, log: "")
            },
            enabledAFMIDs: {
                state.events.append("enabled-ids")
                return state.currentEnabledAFMIDs
            },
            stopEngine: { state.events.append("stop") },
            clearRegistrationRequest: { state.events.append("clear-registration") },
            refreshMenu: { state.events.append("refresh") }
        )
    }

    private func source(
        _ id: String,
        handle: Int,
        enabled: Bool = true,
        selected: Bool = false,
        selectable: Bool = true,
        asciiCapable: Bool = false
    ) -> SystemMaintenance.Source {
        SystemMaintenance.Source(
            handle: handle,
            id: id,
            enabled: enabled,
            selected: selected,
            selectable: selectable,
            asciiCapable: asciiCapable
        )
    }
}
