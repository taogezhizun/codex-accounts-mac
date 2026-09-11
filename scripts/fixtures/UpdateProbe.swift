// Isolated Sparkle integration fixture. Never linked into Codex Accounts.
import AppKit
import Sparkle

@MainActor final class Probe: NSObject, NSApplicationDelegate, SPUUserDriver {
    var updater: SPUUpdater?
    func event(_ value: String) {
        let root = Bundle.main.bundleURL.deletingLastPathComponent()
        try? Data(value.utf8).write(to: root.appendingPathComponent("probe-result.txt"))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "2" {
            event("updated-and-relaunched"); NSApp.terminate(nil); return
        }
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: nil)
        do { try updater!.start(); updater!.checkForUpdates() }
        catch { event("start-failed"); NSApp.terminate(nil) }
    }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { event("not-found"); acknowledgement(); NSApp.terminate(nil) }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        event("rejected-\((error as NSError).code)")
        // The test app has no account data; diagnostics contain only synthetic paths and local URLs.
        fputs("\(error)\n", stderr)
        acknowledgement(); NSApp.terminate(nil)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}
@main struct Runner {
    @MainActor static func main() {
        let app = NSApplication.shared
        let probe = Probe()
        app.delegate = probe
        app.setActivationPolicy(.prohibited)
        app.run()
    }
}
