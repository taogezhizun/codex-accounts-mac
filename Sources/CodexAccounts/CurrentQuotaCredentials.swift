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

/// Choose the freshest live credentials for the active account; otherwise use the saved file store.
struct QuotaCredentials {
    let snapshot: AuthSnapshot
    let fromLive: Bool
    static func load(id: String, live: Data?, saved: () throws -> Data) throws -> Self {
        if let live, let parsed = try? AuthSnapshot(live), parsed.identity == id {
            return Self(snapshot: parsed, fromLive: true)
        }
        let snapshot = try AuthSnapshot(saved())
        guard snapshot.identity == id else { throw AccountsError.message("账号与凭据不匹配，已停止刷新。") }
        return Self(snapshot: snapshot, fromLive: false)
    }
    func validate(id: String, live: Data?, saved: () throws -> Data) throws {
        let latest = try Self.load(id: id, live: live, saved: saved)
        guard latest.fromLive == fromLive, latest.snapshot.data == snapshot.data else {
            throw AccountsError.message("查询期间登录凭据发生变化，已丢弃本次结果；请重新刷新。")
        }
    }
}
