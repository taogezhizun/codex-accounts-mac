import AppKit
import Combine
import Sparkle

/// Sparkle owns download, EdDSA verification, replacement and relaunch of this utility only.
@MainActor final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let author = "taogezhizun"
    static let profileURL = URL(string: "https://github.com/taogezhizun")!
    static let projectURL = URL(string: "https://github.com/taogezhizun/codex-accounts-mac")!
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建" }
    @Published private(set) var availableVersion: String?
    private var reminderOnly = false
    private var rawSessionInProgress = false
    @Published private(set) var canCheck = false
    @Published private(set) var sessionInProgress = false
    @Published var automaticChecks = false {
        didSet {
            if controller?.updater.automaticallyChecksForUpdates != automaticChecks {
                controller?.updater.automaticallyChecksForUpdates = automaticChecks
            }
        }
    }
    var isOperationBusy: () -> Bool = { false }
    var onSessionEnd: () -> Void = {}
    private let enabled: Bool
    private var controller: SPUStandardUpdaterController?
    private var observations: Set<AnyCancellable> = []

    init(enabled: Bool) { self.enabled = enabled; super.init() }
    func start() {
        guard enabled, controller == nil, Bundle.main.bundleIdentifier == "org.codexaccounts.mac" else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
        controller.updater.publisher(for: \.sessionInProgress).sink { [weak self] active in
            self?.receiveSessionState(active)
        }.store(in: &observations)
        controller.startUpdater()
    }
    func check() {
        guard enabled, !isOperationBusy(), canCheck || availableVersion != nil else { return }
        // Sparkle brings an existing reminder into focus instead of opening a second session.
        reminderOnly = false; sessionInProgress = rawSessionInProgress
        controller?.checkForUpdates(nil)
    }
    func receiveSessionState(_ active: Bool) {
        let wasBlocking = sessionInProgress
        rawSessionInProgress = active
        if !active { availableVersion = nil; reminderOnly = false }
        sessionInProgress = active && !reminderOnly
        if wasBlocking && !sessionInProgress { onSessionEnd() }
    }
    func receiveReminder(version: String, handledBySparkle: Bool) {
        availableVersion = version
        reminderOnly = !handledBySparkle
        sessionInProgress = rawSessionInProgress && !reminderOnly
        if reminderOnly { onSessionEnd() }
    }
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { false }
    // Sparkle's standard AppKit user driver invokes these UI delegates on the main thread.
    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated { receiveReminder(version: update.displayVersionString, handledBySparkle: handleShowingUpdate) }
    }
    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { reminderOnly = false; sessionInProgress = rawSessionInProgress }
    }
    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { availableVersion = nil; reminderOnly = false }
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        availableVersion = nil; reminderOnly = false
    }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if isOperationBusy() {
            throw NSError(domain: "CodexAccounts.Updates", code: 1, userInfo: [NSLocalizedDescriptionKey: "请等待当前账号操作完成，再检查更新。"])
        }
    }
}

import SwiftUI

struct CheckForAppUpdates: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var updates: AppUpdates
    var body: some View {
        Button("检查更新…") { updates.check() }.disabled(model.demo || model.busy || (!updates.canCheck && updates.availableVersion == nil))
    }
}
struct UpdateSettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var updates: AppUpdates
    var body: some View {
        Toggle("自动检查新版本", isOn: $updates.automaticChecks).disabled(model.demo || updates.sessionInProgress)
        HStack {
            Text("当前版本 \(AppUpdates.version)").font(.callout)
            Spacer()
            CheckForAppUpdates(updates: updates)
        }
        Text("发现新版后由你确认安装，原位更新并重开本工具。不会重开 Codex 桌面 App。更新包须通过签名校验；请将工具放在“应用程序”中使用。")
            .font(.caption).foregroundStyle(.secondary)
    }
}
struct RefreshStatusView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let text: String = {
                if model.demo { return "演示模式不连接账号" }
                if !model.automaticRefresh { return "自动刷新已暂停" }
                if model.refreshingAutomatically { return "正在刷新账号额度 · 可取消" }
                if model.awaitingConfirmation { return "核对切换结果后继续自动刷新" }
                guard let date = model.nextRefresh else { return "没有待刷新账号；请添加账号或处理登录提示" }
                let seconds = Int(date.timeIntervalSince(context.date))
                return seconds <= 0 ? "空闲后自动刷新" : "下次自动刷新约 \(max(1, (seconds + 59) / 60)) 分钟后"
            }()
            Label(text, systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MenuUpdateNotice: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var updates: AppUpdates
    var body: some View {
        if let version = updates.availableVersion {
            HStack(spacing: 9) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6).accessibilityHidden(true)
                Text("新版本 \(version) 可用").font(.caption)
                Spacer()
                Button("查看更新") { updates.check() }.font(.caption).disabled(model.busy || model.demo)
            }.padding(11).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 8)).padding(.bottom, 10)
        }
    }
}
