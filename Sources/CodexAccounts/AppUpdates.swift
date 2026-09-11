import AppKit
import Combine
import Sparkle

/// Sparkle owns download, EdDSA verification, replacement and relaunch of this utility only.
@MainActor final class AppUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let author = "taogezhizun"
    static let profileURL = URL(string: "https://github.com/taogezhizun")!
    static let projectURL = URL(string: "https://github.com/taogezhizun/codex-accounts-mac")!
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发构建" }
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
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
        controller.updater.publisher(for: \.sessionInProgress).sink { [weak self] active in
            let wasActive = self?.sessionInProgress ?? false
            self?.sessionInProgress = active
            if wasActive && !active { self?.onSessionEnd() }
        }.store(in: &observations)
        controller.startUpdater()
    }
    func check() { guard enabled, !isOperationBusy(), canCheck else { return }; controller?.checkForUpdates(nil) }
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
        Button("检查更新…") { updates.check() }.disabled(model.demo || model.busy || !updates.canCheck)
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
                if model.refreshingAutomatically { return "正在刷新当前账号 · 可取消" }
                if model.awaitingConfirmation { return "核对切换结果后继续自动刷新" }
                guard let date = model.nextRefresh else { return "保存当前登录账号后自动刷新" }
                let seconds = Int(date.timeIntervalSince(context.date))
                return seconds <= 0 ? "空闲后自动刷新" : "下次自动刷新约 \(max(1, (seconds + 59) / 60)) 分钟后"
            }()
            Label(text, systemImage: "arrow.clockwise").font(.caption).foregroundStyle(.secondary)
        }
    }
}
