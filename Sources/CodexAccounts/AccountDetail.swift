import SwiftUI
import AccountsCore

struct AccountDetail: View {
    @EnvironmentObject var model: AppModel
    let account: Account
    let switchAction: () -> Void
    let renameAction: () -> Void
    let deleteAction: () -> Void
    private var isCurrent: Bool { model.currentIdentity == account.id }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center, spacing: 15) {
                    AccountAvatar(account: account, hideEmails: model.hideEmails, size: 58)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(model.title(account)).font(.system(size: 26, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                        HStack(spacing: 8) {
                            Text(AccountPresentation.email(account, hideEmails: model.hideEmails)).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            PlanBadge(plan: account.plan)
                        }
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button("编辑备注…") { renameAction() }.keyboardShortcut("e").disabled(model.busy || model.demo)
                        Divider()
                        Button("移除账号…", role: .destructive) { deleteAction() }.disabled(model.busy || model.demo)
                    } label: { Image(systemName: "ellipsis").frame(width: 20, height: 20) }
                        .menuStyle(.borderlessButton).fixedSize().help("账号操作").accessibilityLabel("账号操作")
                }
                if isCurrent {
                    Label("当前认证", systemImage: "checkmark.circle.fill").font(.caption.weight(.medium)).foregroundStyle(.tint)
                        .help("该账号与本地认证文件匹配。桌面 App 的实际账号仍需在 App 中核对。")
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("剩余额度").font(.headline)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            Text(AccountPresentation.updatedLabel(account, now: context.date)).font(.caption).foregroundStyle(.secondary)
                        }
                        Button { model.refresh(account.id) } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).help("刷新额度（⌘R）").accessibilityLabel("刷新额度").keyboardShortcut("r").disabled(model.busy || model.demo)
                    }
                    if account.quotas.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "chart.bar.xaxis").font(.title2).foregroundStyle(.tertiary)
                            Text("读取一次，了解可用额度").font(.callout.weight(.medium))
                            Text("不会发送聊天消息或触发额度重置。").font(.caption).foregroundStyle(.secondary)
                            Button("读取额度") { model.refresh(account.id) }.disabled(model.busy || model.demo)
                        }.frame(maxWidth: .infinity).padding(28).background(.background, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                            ForEach(account.quotas) { window in QuotaCard(window: window) }
                        }
                    }
                    if let issue = account.issue {
                        Label(issue, systemImage: "exclamationmark.arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    } else if !account.quotas.isEmpty && AccountPresentation.needsRefresh(account) {
                        Label("这是上次记录的额度，切换前可以刷新确认。", systemImage: "clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 15) {
                    Divider()
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(isCurrent ? "已经是当前认证" : "准备切换到这个账号？").font(.system(size: 14, weight: .medium))
                            Text(isCurrent ? "打开桌面 App，确认实际登录状态。" : "将正常退出并重新打开桌面 App。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        if isCurrent {
                            Button { model.openDesktop() } label: { Label("打开 Codex", systemImage: "arrow.up.forward.app") }
                                .controlSize(.large).disabled(model.busy || model.demo)
                        } else {
                            Button(action: switchAction) { Label("切换至此账号…", systemImage: "arrow.triangle.2.circlepath").padding(.horizontal, 3) }
                                .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.return, modifiers: .command)
                                .disabled(model.switchBlockReason(account.id) != nil)
                                .help(model.switchBlockReason(account.id) ?? "查看切换确认（⌘↩）")
                        }
                    }
                    if !isCurrent, let reason = model.switchBlockReason(account.id) {
                        Label(reason, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    } else if !isCurrent {
                        HStack(spacing: 5) { Image(systemName: "arrow.uturn.backward.circle"); Text("自动保存上一次认证，可随时恢复。") }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding(30).frame(maxWidth: 780, alignment: .leading)
        }
    }
}

struct QuotaCard: View {
    let window: QuotaWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text(window.label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary); Spacer(); Image(systemName: window.label.contains("7 天") ? "calendar" : "clock").foregroundStyle(.tertiary) }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(window.remaining))").font(.system(size: 39, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("%").font(.title3).foregroundStyle(.secondary)
                Spacer()
                if window.remaining < 20 { Text("偏低").font(.caption).foregroundStyle(.orange) }
            }
            QuotaMeter(window: window, height: 6)
            if let reset = window.resetsAt {
                Text("\(reset.formatted(date: .abbreviated, time: .shortened)) 重置").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            } else { Text("重置时间未知").font(.system(size: 10)).foregroundStyle(.tertiary) }
        }.padding(19).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
            .accessibilityElement(children: .combine)
    }
}

struct RecoveryBanner: View {
    @EnvironmentObject var model: AppModel
    let restore: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark").font(.title3).foregroundStyle(.orange).padding(.top, 1)
            VStack(alignment: .leading, spacing: 7) {
                Text("还差一步：核对桌面账号").font(.callout.weight(.semibold))
                Text("本地认证已更新。请检查桌面 App 显示的账号，再确认切换结果。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    Button("已核对，账号正确") { model.confirmDesktopAccount() }.disabled(model.busy || model.demo)
                    Button("恢复上次认证…", action: restore).buttonStyle(.borderless).disabled(model.busy || model.demo || !model.hasBackup)
                }.padding(.top, 2)
            }
            Spacer(minLength: 0)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.2)))
    }
}

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 5) { Text("操作未完成").font(.callout.weight(.medium)); Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("关闭错误提示")
        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct StatusFooter: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 9) {
                if model.busy { ProgressView().controlSize(.small) }
                else { Image(systemName: model.demo ? "play.rectangle" : "checkmark.shield").foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.status).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let code = model.loginCode { Text("验证码：\(code)").font(.system(.body, design: .monospaced).weight(.semibold)).textSelection(.enabled) }
                }
                Spacer(minLength: 0)
                if model.busy && model.canCancel { Button("取消") { model.cancel() } }
            }.padding(.horizontal, 24).padding(.vertical, 14).frame(minHeight: 47)
        }
    }
}
