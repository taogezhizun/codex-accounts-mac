import SwiftUI
import AppKit
import AccountsCore

@main struct CodexAccountsApp: App {
    @StateObject private var model = AppModel(demo: CommandLine.arguments.contains("--demo"))
    var body: some Scene {
        WindowGroup("Codex Accounts", id: "accounts") {
            AccountsView().environmentObject(model)
                .frame(minWidth: 780, minHeight: 540)
        }
        .defaultSize(width: 880, height: 610)
        .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra("Codex Accounts", systemImage: "person.2") {
            MenuPanel().environmentObject(model)
        }
        .menuBarExtraStyle(.window)
        Settings { SettingsView().environmentObject(model).frame(width: 520) }
    }
}

struct AccountsView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var pendingSwitch: SwitchSelection?
    @State private var showRestore = false
    @State private var pendingDelete: String?
    @State private var nickname = ""
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $model.selection) {
                    Section("我的账号 · \(model.accounts.count)") {
                        ForEach(model.accounts.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.email.localizedCaseInsensitiveContains(search) }) { account in
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(account.id == model.currentIdentity ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.title).fontWeight(.medium).lineLimit(1)
                                    Text(account.plan.uppercased()).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if account.id == model.currentIdentity { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).help("与当前认证文件匹配；不代表桌面 App 已验证登录。") }
                            }.padding(.vertical, 6).tag(account.id)
                        }
                    }
                }.searchable(text: $search, prompt: "搜索账号")
                HStack {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    Text(model.demo ? "演示数据" : "凭据保存在本机钥匙串").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(14)
            }.navigationSplitViewColumnWidth(min: 215, ideal: 245, max: 280)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                if let account = model.selected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(account.title).font(.system(size: 28, weight: .semibold)).textSelection(.enabled)
                                    if !account.nickname.isEmpty { Text(account.email).foregroundStyle(.secondary).textSelection(.enabled) }
                                    HStack(spacing: 8) {
                                        Text(account.plan.uppercased()).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 4).background(.quaternary, in: Capsule())
                                        if account.id == model.currentIdentity { Label("认证文件匹配", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                Spacer()
                                Image(systemName: "person.crop.circle").font(.system(size: 42, weight: .light)).foregroundStyle(.secondary.opacity(0.6))
                            }
                            VStack(alignment: .leading, spacing: 15) {
                                HStack {
                                    Text("剩余额度").font(.headline)
                                    Spacer()
                                    if let time = account.updatedAt { Text(time, style: .relative).font(.caption).foregroundStyle(.secondary); Text("前更新").font(.caption).foregroundStyle(.secondary) }
                                }
                                if account.quotas.isEmpty {
                                    Text("尚未读取额度").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 85)
                                } else {
                                    ForEach(account.quotas) { window in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack { Text(window.label).foregroundStyle(.secondary); Spacer(); Text("\(Int(window.remaining))%").font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit() }
                                            ProgressView(value: window.remaining, total: 100).tint(window.remaining < 20 ? .orange : .accentColor)
                                            if let reset = window.resetsAt { Text("重置：\(reset.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
                                        }
                                    }
                                }
                                if let issue = account.issue { Label(issue, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                            }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
                            HStack(spacing: 12) {
                                Button { pendingSwitch = SwitchSelection(id: account.id) } label: { Label("切换并重开 App", systemImage: "arrow.triangle.2.circlepath").padding(.horizontal, 8) }
                                    .buttonStyle(.borderedProminent).controlSize(.large).disabled(model.busy || model.demo || model.awaitingConfirmation)
                                Button { model.refresh(account.id) } label: { Label("刷新额度", systemImage: "arrow.clockwise") }.controlSize(.large).disabled(model.busy || model.demo)
                            }
                            Text("切换会正常退出并重新打开桌面 App。完成后，请在桌面 App 中核对账号。")
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Divider()
                            HStack {
                                TextField("添加备注，例如：日常工作", text: $nickname).textFieldStyle(.roundedBorder)
                                Button("保存备注") { model.rename(account.id, nickname: nickname) }.disabled(model.busy || model.demo)
                                Button(role: .destructive) { pendingDelete = account.id } label: { Image(systemName: "trash") }.help("从本工具移除账号").disabled(model.busy || model.demo)
                            }
                        }.padding(30)
                    }.onChange(of: account.id, initial: true) { _, _ in nickname = account.nickname }
                } else {
                    ContentUnavailableView {
                        Label("账号切换，少几次登录", systemImage: "person.2.crop.square.stack")
                    } description: {
                        Text("保存当前账号，或通过浏览器添加另一个账号。\n你的凭据只保存在这台 Mac 上。")
                    } actions: {
                        Button("保存当前账号") { model.importCurrent() }.buttonStyle(.borderedProminent).disabled(model.busy || model.demo)
                        Button("浏览器添加账号") { model.addViaLogin() }.disabled(model.busy || model.demo)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        if model.busy { ProgressView().controlSize(.small) } else { Image(systemName: model.awaitingConfirmation ? "clock" : "info.circle").foregroundStyle(.secondary) }
                        Text(model.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if model.busy && model.canCancel { Button("取消") { model.cancel() } }
                    }
                    if let code = model.loginCode { Text("设备验证码：\(code)").font(.headline.monospaced()).textSelection(.enabled) }
                    if model.awaitingConfirmation { Button("我已在桌面 App 核对账号") { model.confirmDesktopAccount() }.disabled(model.busy) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            }.background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItemGroup {
                if model.demo { Text("DEMO").font(.caption.bold()).foregroundStyle(.orange) }
                Menu {
                    Button("保存当前账号", systemImage: "square.and.arrow.down") { model.importCurrent() }
                    Button("浏览器添加账号", systemImage: "globe") { model.addViaLogin() }
                    Button("设备码添加账号", systemImage: "key.horizontal") { model.addViaLogin(device: true) }
                    Divider()
                    Button("从 JSON 导入…", systemImage: "doc.badge.plus") { model.importFile() }
                } label: { Label("添加账号", systemImage: "plus") }.disabled(model.busy || model.demo)
                if model.hasBackup { Button("恢复上次认证", systemImage: "clock.arrow.circlepath") { showRestore = true }.disabled(model.busy) }
                SettingsLink { Image(systemName: "gearshape") }.disabled(model.busy || model.demo)
            }
        }
        .sheet(item: $pendingSwitch) { id in
            RestartSheet(title: "切换账号并重开 App", actionTitle: "切换并重开", action: { model.switchTo(id.id) })
        }
        .sheet(isPresented: $showRestore) { RestartSheet(title: "恢复上次认证", actionTitle: "恢复并重开", action: { model.restore() }) }
        .alert("从本工具移除账号？", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("移除", role: .destructive) { if let id = pendingDelete { model.delete(id) }; pendingDelete = nil }
        } message: { Text("将移除本工具保存的账号与凭据。桌面 App 当前登录和上一次恢复备份不会被删除。") }
        .alert("操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

// Local presentation identity; the value is an account fingerprint, never a token.
struct SwitchSelection: Identifiable { let id: String }

struct RestartSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let actionTitle: String
    let action: () -> Void
    @State private var ready = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: "arrow.triangle.2.circlepath").font(.title2.bold())
            Text("桌面 App 会退出并重新打开。本工具无法可靠判断所有正在执行的任务，请先暂停任务并保存编辑。")
            Toggle("我已暂停任务，可以正常退出桌面 App", isOn: $ready)
            Text("若桌面 App 拒绝退出，切换将停止，不会强制结束进程。共享此认证目录的 CLI 也可能受到影响。")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button(actionTitle) { dismiss(); action() }.buttonStyle(.borderedProminent).disabled(!ready) }
        }.padding(26).frame(width: 450)
    }
}

struct MenuPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Codex Accounts").font(.headline); Spacer(); if model.busy { ProgressView().controlSize(.small) } }
            if model.accounts.isEmpty { Text("添加账号，开始使用。").foregroundStyle(.secondary) }
            ForEach(model.accounts.prefix(5)) { account in
                Button {
                    model.selection = account.id; openWindow(id: "accounts"); NSApp.activate(ignoringOtherApps: true)
                } label: {
                    HStack {
                        Image(systemName: account.id == model.currentIdentity ? "checkmark.circle.fill" : "person.crop.circle").foregroundStyle(.tint)
                        VStack(alignment: .leading, spacing: 3) { Text(account.title).lineLimit(1); Text(account.plan.uppercased()).font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        if let quota = account.quotas.first { Text("\(Int(quota.remaining))%").monospacedDigit().foregroundStyle(.secondary) }
                    }.padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Divider()
            Button("管理账号…") { openWindow(id: "accounts"); NSApp.activate(ignoringOtherApps: true) }.keyboardShortcut(",")
            Button("退出 Codex Accounts") { NSApp.terminate(nil) }.disabled(model.busy).keyboardShortcut("q")
        }.padding(18).frame(width: 295)
    }
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Form {
            Section("桌面 App") {
                LabeledContent("已选择", value: model.application?.lastPathComponent ?? "未找到")
                Button("选择桌面 App…") { model.chooseApplication() }
            }
            Section("认证目录") {
                Text(model.home.path).font(.caption.monospaced()).textSelection(.enabled)
                Button("选择目录…") { model.chooseHome() }
                Text("必须与桌面 App 使用的 CODEX_HOME 一致。第一版支持 file 认证，不支持 keyring、auto 或共享守护进程。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("关于 Codex Accounts · 0.1.0") {
                Text("为 macOS 独立开发的本地账号管理工具。MIT License。")
                Link("灵感来源：cjg1995/codex-account-switcher", destination: URL(string: "https://github.com/cjg1995/codex-account-switcher")!)
                Text("与 OpenAI 及原项目作者无隶属或背书关系。凭据保存在本机钥匙串；添加和额度查询会连接 OpenAI。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).padding(12).disabled(model.busy || model.demo)
    }
}
