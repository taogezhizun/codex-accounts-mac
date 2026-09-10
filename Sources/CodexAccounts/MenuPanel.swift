import SwiftUI
import AppKit
import AccountsCore

struct MenuPanel: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""
    @State private var pending: Account?
    @State private var recovering = false
    var accounts: [Account] { AccountPresentation.ordered(model.accounts, current: model.currentIdentity, query: query) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if pending != nil || recovering {
                SwitchConfirmation(target: pending, compact: true, cancel: { pending = nil; recovering = false }) {
                    let target = pending; pending = nil; recovering = false
                    if let target { model.switchTo(target.id) } else { model.restore() }
                }.padding(20)
            } else {
                HStack(spacing: 10) {
                    BrandMark(size: 32)
                    VStack(alignment: .leading, spacing: 3) { Text("Codex Accounts").font(.headline); Text("选择账号，快速切换").font(.system(size: 10)).foregroundStyle(.secondary) }
                    Spacer()
                    Button { model.hideEmails.toggle() } label: { Image(systemName: model.hideEmails ? "eye.slash" : "eye").frame(width: 24, height: 24) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(model.hideEmails ? "显示邮箱" : "隐藏邮箱")
                }.padding(18)
                if let error = model.error { ErrorBanner(message: error) { model.error = nil }.padding([.horizontal, .bottom], 14) }
                if model.awaitingConfirmation {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("请先核对上次切换", systemImage: "clock.badge.checkmark").font(.callout.weight(.medium))
                        Text("检查桌面 App 的账号，确认后才能继续切换。").font(.caption).foregroundStyle(.secondary)
                        HStack { Button("已核对") { model.confirmDesktopAccount() }; Button("恢复…") { recovering = true } }.disabled(model.busy || model.demo)
                    }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).padding([.horizontal, .bottom], 14)
                }
                if !model.accounts.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索账号", text: $query).textFieldStyle(.plain).accessibilityLabel("搜索账号")
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain).accessibilityLabel("清除搜索") }
                    }.padding(10).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 14).padding(.bottom, 8)
                    if accounts.isEmpty {
                        VStack(spacing: 7) { Text("没有匹配的账号").font(.callout); Button("清除搜索") { query = "" }.font(.caption) }.frame(maxWidth: .infinity).padding(24)
                    } else {
                        ScrollView {
                            VStack(spacing: 3) {
                                ForEach(accounts) { account in
                                    QuickAccountRow(account: account) {
                                        model.selection = account.id
                                        if account.id == model.currentIdentity { model.openDesktop() }
                                        else { pending = account }
                                    }
                                    .disabled(model.busy || (account.id != model.currentIdentity && model.switchBlockReason(account.id) != nil))
                                }
                            }.padding(.horizontal, 8)
                        }.frame(height: min(CGFloat(accounts.count) * 74, 340))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("先保存你正在使用的账号").font(.callout.weight(.medium))
                        Text("以后切换时，不必重复登录。").font(.caption).foregroundStyle(.secondary)
                        Button("保存当前账号") { model.importCurrent() }.buttonStyle(.borderedProminent).disabled(model.busy || model.demo)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.busy || model.demo {
                    HStack(spacing: 7) {
                        if model.busy { ProgressView().controlSize(.small) }
                        Text(model.demo ? "演示模式 · 所有账号操作均不会执行" : model.status).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if model.busy && model.canCancel { Button("取消") { model.cancel() } }
                    }.padding(.horizontal, 18).padding(.vertical, 10)
                }
                Divider()
                HStack {
                    Button { openWindow(id: "accounts"); NSApp.activate(ignoringOtherApps: true) } label: { Label("管理账号", systemImage: "sidebar.left") }
                    Spacer()
                    if model.hasBackup { Button { recovering = true } label: { Image(systemName: "clock.arrow.circlepath") }.help("恢复上次认证").disabled(model.busy || model.demo) }
                    SettingsLink { Image(systemName: "gearshape") }.help("设置")
                    Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("退出 Codex Accounts").disabled(model.busy)
                }.buttonStyle(.borderless).padding(15)
            }
        }.frame(width: 368).onAppear { model.checkCurrentIdentity() }
    }
}

private struct QuickAccountRow: View {
    @EnvironmentObject var model: AppModel
    let account: Account
    let action: () -> Void
    @State private var hovered = false
    var current: Bool { account.id == model.currentIdentity }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                AccountAvatar(account: account, hideEmails: model.hideEmails, size: 36)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) { Text(model.title(account)).font(.system(size: 13, weight: .medium)).lineLimit(1); if current { Text("当前认证").font(.system(size: 9, weight: .medium)).foregroundStyle(.tint) }; Spacer(minLength: 0) }
                    HStack(spacing: 7) {
                        Text(account.plan.uppercased()).font(.system(size: 10)).foregroundStyle(.secondary)
                        if let quota = QuotaPresentation.summary(account.quotas) {
                            Text("·").foregroundStyle(.tertiary)
                            Text("Codex \(QuotaPresentation.duration(quota))剩余 \(Int(quota.remaining))%").font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                            if AccountPresentation.needsRefresh(account) {
                                Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(.secondary).help("缓存可能已过期，请在管理窗口刷新")
                            }
                        } else { Text("· Codex 额度未读取").font(.system(size: 10)).foregroundStyle(.secondary) }
                    }
                }
                Image(systemName: current ? "arrow.up.forward" : "arrow.right").font(.caption.weight(.medium)).foregroundStyle(hovered ? .primary : .tertiary)
            }.padding(.horizontal, 11).padding(.vertical, 12)
                .background(hovered ? Color.primary.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .help(current ? "打开桌面 App" : "查看切换确认")
            .accessibilityLabel("\(model.title(account))，\(current ? "当前认证，打开桌面 App" : "切换账号")")
    }
}
