import Foundation
import Security
import AccountsCore

final class KeychainVault {
    private let service = "org.codexaccounts.local-vault.v1"
    private let copyMatching: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>) -> OSStatus
    init(copyMatching: @escaping (CFDictionary, UnsafeMutablePointer<CFTypeRef?>) -> OSStatus = { SecItemCopyMatching($0, $1) }) {
        self.copyMatching = copyMatching
    }
    func read(_ key: String, allowInteraction: Bool = true) throws -> Data? {
        var query = base(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowInteraction { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var value: CFTypeRef?
        let status = copyMatching(query as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data else { throw failure(status) }
        return data
    }
    func write(_ data: Data, key: String) throws {
        let status = SecItemUpdate(base(key) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = base(key)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw failure(added) }
        } else if status != errSecSuccess { throw failure(status) }
    }
    func remove(_ key: String) throws {
        let status = SecItemDelete(base(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    private func base(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: key, kSecAttrSynchronizable as String: false]
    }
    private func failure(_ status: OSStatus) -> Error {
        AccountsError.message("钥匙串访问失败（\(status)）。请解锁登录钥匙串并允许 Codex Accounts 访问。")
    }
}

final class AccountStore {
    let directory: URL
    private let vault = KeychainVault()
    private let lock: ExclusiveLock
    var accounts: [Account] = []
    init(directory: URL) throws {
        self.directory = directory
        try PrivateFiles.makeDirectory(directory)
        lock = try ExclusiveLock(at: directory.appendingPathComponent("instance.lock"))
        // Reap only UUID-named private session folders after acquiring the instance lock.
        // This also removes credentials left by a prior crash during browser login.
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
        if let data = try PrivateFiles.read(directory.appendingPathComponent("accounts.json")) {
            accounts = try JSONDecoder().decode([Account].self, from: data)
        }
    }
    func save() throws {
        try PrivateFiles.write(JSONEncoder().encode(accounts), to: directory.appendingPathComponent("accounts.json"))
    }
    @discardableResult func upsert(_ data: Data) throws -> Account {
        let snapshot = try AuthSnapshot(data)
        try vault.write(data, key: snapshot.identity)
        if let i = accounts.firstIndex(where: { $0.id == snapshot.identity }) {
            accounts[i].email = snapshot.email
            accounts[i].plan = snapshot.plan
            accounts[i].issue = nil
        } else { accounts.append(Account(snapshot: snapshot)) }
        try save()
        return accounts.first { $0.id == snapshot.identity }!
    }
    func snapshot(_ id: String) throws -> Data {
        guard let data = try vault.read(id) else { throw AccountsError.message("钥匙串中没有这个账号，请重新添加。") }
        guard try AuthSnapshot(data).identity == id else { throw AccountsError.message("账号与凭据不匹配，已停止操作。") }
        return data
    }
    func delete(_ id: String) throws {
        // Persist the list first: a failed Keychain deletion leaves only an inaccessible orphan,
        // never a visible account pointing to a destroyed credential.
        accounts.removeAll { $0.id == id }; try save(); try vault.remove(id)
    }
    func saveBackup(_ value: SwitchBackup) throws { try vault.write(JSONEncoder().encode(value), key: "switch-recovery") }
    func backup(allowInteraction: Bool = true) throws -> SwitchBackup? {
        guard let data = try vault.read("switch-recovery", allowInteraction: allowInteraction) else { return nil }
        return try JSONDecoder().decode(SwitchBackup.self, from: data)
    }
    func confirmBackup() throws {
        if var value = try backup() { value.isPending = false; try saveBackup(value) }
    }
}
