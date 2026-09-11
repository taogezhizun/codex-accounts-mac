import SwiftUI
import AccountsCore

struct StatusBarQuota: Equatable {
    let text: String
    let help: String

    static func make(account: Account?, pending: Bool, hideEmails: Bool, now: Date = Date()) -> Self {
        if pending { return Self(text: "—", help: "等待核对桌面账号，确认后显示剩余额度") }
        guard let account else { return Self(text: "—", help: "没有匹配的已保存当前账号") }
        let name = AccountPresentation.title(account, hideEmails: hideEmails)
        guard let quota = QuotaPresentation.summary(account.quotas), quota.remaining.isFinite else {
            return Self(text: "—", help: "\(name) · Codex 额度未读取")
        }
        let stale = AccountPresentation.needsRefresh(account, now: now)
        let percent = Int(min(100, max(0, quota.remaining)))
        let timestamp = account.updatedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "时间未知"
        return Self(text: "\(stale ? "~" : "")\(percent)%",
                    help: "\(name) · Codex \(QuotaPresentation.duration(quota))剩余 \(percent)%\n\(stale ? "上次记录" : "更新于")：\(timestamp)")
    }
}

struct StatusBarLabel: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let quota = StatusBarQuota.make(account: model.currentAccount, pending: model.awaitingConfirmation,
                                        hideEmails: model.hideEmails, now: model.quotaDisplayDate)
        HStack(spacing: 5) {
            Image(nsImage: SwitchGlyph.menuBarImage)
            if model.showMenuBarQuota { Text(quota.text).monospacedDigit().font(.system(size: 13, weight: .semibold)) }
        }
        .help(quota.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex Accounts，\(quota.help)")
    }
}
