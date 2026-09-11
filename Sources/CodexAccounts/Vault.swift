import Foundation
import Security
import AccountsCore

final class KeychainVault {
    private let service = "org.codexaccounts.local-vault.v1"
    private let copyMatching: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>) -> OSStatus
    init(copyMatching: @escaping (CFDictionary, UnsafeMutablePointer<CFTypeRef?>) -> OSStatus = { SecItemCopyMatching($0, $1) }) {
        self.copyMatching = copyMatching
    }
    func read(_ key: String) throws -> Data? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = copyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw failure(status) }
        return data
    }
    private func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false]
    }
    private func failure(_ status: OSStatus) -> Error {
        AccountsError.message("钥匙串访问失败（\(status)）。请解锁登录钥匙串并允许 Codex Accounts 访问。")
    }
}

/// One atomic, versioned snapshot owns metadata, credentials and the recovery journal.
/// Data's JSON encoding is base64, NOT encryption. The entire file is private (0600).
private struct LocalAccountData: Codable {
    var version = 1
    var accounts: [Account] = []
    var credentials: [String: Data] = [:]
    var recovery: SwitchBackup?

    func validate() throws {
        guard version == 1, Set(accounts.map(\.id)).count == accounts.count,
              Set(accounts.map(\.id)) == Set(credentials.keys) else {
            throw AccountsError.message("本地账号数据不完整或版本不受支持，已停止操作。")
        }
        for account in accounts {
            guard let data = credentials[account.id], try AuthSnapshot(data).identity == account.id else {
                throw AccountsError.message("账号与凭据不匹配，已停止操作。")
            }
        }
        if let recovery {
            guard recovery.home.hasPrefix("/"), !recovery.home.contains("\0"),
                  recovery.targetIdentity.count == 64,
                  recovery.targetIdentity.allSatisfy({ $0.isHexDigit }),
                  recovery.createdAt.timeIntervalSince1970.isFinite else {
                throw AccountsError.message("恢复记录无效，请先修复旧数据再重试迁移。")
            }
            if let previous = recovery.previous { _ = try AuthSnapshot(previous) }
        }
    }
}

final class AccountStore {
    let directory: URL
    private let vault: KeychainVault // Read only; called exclusively by explicit migration.
    private let lock: ExclusiveLock
    private var data: LocalAccountData?
    private(set) var needsMigration: Bool
    var accounts: [Account] = []
    private var file: URL { directory.appendingPathComponent("local-store-v1.json") }
    private var legacyFile: URL { directory.appendingPathComponent("accounts.json") }
    private static let maxStoreBytes = 64 * 1_048_576

    init(directory: URL, vault: KeychainVault = KeychainVault()) throws {
        self.vault = vault
        self.directory = directory
        needsMigration = false
        try PrivateFiles.makeDirectory(directory)
        lock = try ExclusiveLock(at: directory.appendingPathComponent("instance.lock"))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let sessions = directory.appendingPathComponent("Sessions", isDirectory: true)
        try PrivateFiles.rejectSymlinks(sessions)
        if FileManager.default.fileExists(atPath: sessions.path) {
            for child in try FileManager.default.contentsOfDirectory(at: sessions, includingPropertiesForKeys: nil) {
                if UUID(uuidString: child.lastPathComponent) != nil {
                    try PrivateFiles.rejectSymlinks(child)
                    try FileManager.default.removeItem(at: child)
                }
            }
        }
        if let bytes = try PrivateFiles.read(file, maximumBytes: Self.maxStoreBytes) {
            let value = try JSONDecoder().decode(LocalAccountData.self, from: bytes)
            try value.validate()
            data = value; accounts = value.accounts
        } else if let bytes = try PrivateFiles.read(legacyFile) {
            accounts = try JSONDecoder().decode([Account].self, from: bytes)
            needsMigration = true // Even an empty old list may have a recovery record.
        } else {
            try commit(LocalAccountData())
        }
        // Only reap our own interrupted migration staging files after acquiring the lock.
        for child in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let name = child.lastPathComponent
            if name.hasPrefix("migration-"), UUID(uuidString: String(name.dropFirst(10))) != nil {
                try PrivateFiles.remove(child)
            }
        }
    }
    private func requireFiles() throws -> LocalAccountData {
        guard let data, !needsMigration else {
            throw AccountsError.message("请先在“本地存储”中迁移已保存账号。可稍后迁移，当前额度仍可查看。")
        }
        return data
    }
    private func commit(_ value: LocalAccountData) throws {
        try value.validate()
        let bytes = try JSONEncoder().encode(value)
        guard bytes.count <= Self.maxStoreBytes else { throw AccountsError.message("账号库超过大小限制，未保存更改。") }
        try PrivateFiles.write(bytes, to: file)
        data = value; accounts = value.accounts; needsMigration = false
    }
    func save() throws {
        if needsMigration {
            // Quota cache and labels may still be saved while migration is deferred.
            try PrivateFiles.write(JSONEncoder().encode(accounts), to: legacyFile)
        } else {
            var value = try requireFiles(); value.accounts = accounts
            do { try commit(value) } catch { accounts = data?.accounts ?? []; throw error }
        }
    }
    @discardableResult func upsert(_ bytes: Data) throws -> Account {
        var value = try requireFiles()
        let snapshot = try AuthSnapshot(bytes)
        value.credentials[snapshot.identity] = bytes
        if let i = value.accounts.firstIndex(where: { $0.id == snapshot.identity }) {
            value.accounts[i].email = snapshot.email; value.accounts[i].plan = snapshot.plan; value.accounts[i].issue = nil
        } else { value.accounts.append(Account(snapshot: snapshot)) }
        try commit(value)
        return value.accounts.first { $0.id == snapshot.identity }!
    }
    func snapshot(_ id: String) throws -> Data {
        let value = try requireFiles()
        guard let bytes = value.credentials[id], try AuthSnapshot(bytes).identity == id else {
            throw AccountsError.message("没有匹配的账号凭据，请重新添加。")
        }
        return bytes
    }
    func delete(_ id: String) throws {
        var value = try requireFiles()
        value.accounts.removeAll { $0.id == id }; value.credentials.removeValue(forKey: id)
        try commit(value)
    }
    func saveBackup(_ backup: SwitchBackup) throws {
        var value = try requireFiles(); value.recovery = backup; try commit(value)
    }
    func backup() throws -> SwitchBackup? { try requireFiles().recovery }
    func confirmBackup() throws {
        var value = try requireFiles(); value.recovery?.isPending = false; try commit(value)
    }
    /// Caller serializes this operation with every account mutation and updater session.
    /// Nothing changes until ALL old records are readable and the staged snapshot validates.
    func migrate() throws {
        guard needsMigration else { return }
        var value = LocalAccountData(); value.accounts = accounts
        for (index, account) in accounts.enumerated() {
            guard let bytes = try vault.read(account.id) else {
                throw AccountsError.message("第 \(index + 1) 个账号的旧凭据缺失。迁移未完成，旧数据保留；请用旧版修复该账号后重试。")
            }
            guard try AuthSnapshot(bytes).identity == account.id else {
                throw AccountsError.message("第 \(index + 1) 个账号与旧凭据不匹配，迁移已停止。")
            }
            value.credentials[account.id] = bytes
        }
        if let bytes = try vault.read("switch-recovery") {
            value.recovery = try JSONDecoder().decode(SwitchBackup.self, from: bytes)
        }
        try value.validate()
        let stage = directory.appendingPathComponent("migration-\(UUID().uuidString)")
        defer { try? PrivateFiles.remove(stage) }
        let bytes = try JSONEncoder().encode(value)
        guard bytes.count <= Self.maxStoreBytes else { throw AccountsError.message("账号库超过大小限制，迁移未完成。") }
        try PrivateFiles.write(bytes, to: stage)
        guard let verified = try PrivateFiles.read(stage, maximumBytes: Self.maxStoreBytes), verified == bytes else {
            throw AccountsError.message("迁移文件核验失败，旧数据保留。")
        }
        let decoded = try JSONDecoder().decode(LocalAccountData.self, from: verified)
        try decoded.validate()
        try commit(decoded)
        // Intentionally preserve old Keychain items and metadata; never access them again.
    }
}
