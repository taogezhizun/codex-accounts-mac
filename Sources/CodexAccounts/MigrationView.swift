import SwiftUI

struct MigrationBanner: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "externaldrive.badge.person.crop").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 5) {
                Text("迁移已保存账号").font(.callout.weight(.semibold))
                Text("迁移后，账号操作使用本地文件。当前额度仍可查看。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("查看迁移说明…") { model.showMigration = true }.disabled(model.busy)
            }
            Spacer(minLength: 0)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct MigrationView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("迁移到本地文件", systemImage: "externaldrive").font(.title2.weight(.semibold))
            Text("将已保存账号与恢复备份一起迁移。完成后，日常账号操作不再请求钥匙串授权。")
            Text("完整登录凭据将以未加密文件保存在应用数据目录，仅当前 macOS 用户可访问；同一用户运行的其他程序也可能读取。系统备份是否包含它们取决于你的备份设置。")
                .font(.callout).foregroundStyle(.secondary)
            Text("读取旧记录可能出现一个或多个钥匙串授权弹窗。拒绝授权或迁移失败会保留旧数据；成功后旧钥匙串记录也会保留，但不再读写。后续变化不会同步给旧版，请勿同时运行或降级使用旧版。")
                .font(.callout).foregroundStyle(.secondary)
            if let error = model.error { Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if model.busy { HStack { ProgressView().controlSize(.small); Text("正在迁移，请处理系统授权提示…").font(.caption) } }
            HStack {
                Button("稍后") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.busy)
                Spacer()
                Button("开始迁移") { model.migrateAccounts() }.buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.demo || model.updates.sessionInProgress)
            }
        }.padding(26).frame(width: 440).fixedSize(horizontal: false, vertical: true)
            .interactiveDismissDisabled(model.busy)
    }
}
