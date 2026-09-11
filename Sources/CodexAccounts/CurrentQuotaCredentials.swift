import Foundation
import AccountsCore

/// Quota reads only reuse the current file login, never saved Keychain credentials.
enum CurrentQuotaCredentials {
    static func load(id: String, readLive: () throws -> Data?) throws -> AuthSnapshot {
        guard let data = try readLive() else {
            throw AccountsError.message("当前没有文件登录凭据，请在 Codex 中登录后再刷新。")
        }
        let snapshot = try AuthSnapshot(data)
        guard snapshot.identity == id else {
            throw AccountsError.message("当前登录账号已变化，本次刷新已停止。")
        }
        return snapshot
    }
}
