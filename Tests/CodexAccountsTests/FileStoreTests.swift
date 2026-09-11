import XCTest
import Security
import AccountsCore
@testable import CodexAccounts

func syntheticAuth(_ subject: String, token: String = "example-access") throws -> Data {
    let claims = try JSONSerialization.data(withJSONObject: ["sub": subject, "email": "example@example.com"]).base64EncodedString()
    return try JSONSerialization.data(withJSONObject: ["tokens": ["account_id": "example-workspace", "id_token": "demo.\(claims).demo", "access_token": token, "refresh_token": "example-refresh"]])
}

final class StoreFixture {
    let root: URL
    var store: AccountStore?
    var records: [String: Data] = [:]
    var reads: [String] = []
    var denied: String?
    lazy var vault = KeychainVault { [unowned self] query, result in
        let key = (query as NSDictionary)[kSecAttrAccount] as! String
        self.reads.append(key)
        if key == self.denied { return errSecAuthFailed }
        guard let bytes = self.records[key] else { return errSecItemNotFound }
        result.pointee = bytes as CFData
        return errSecSuccess
    }
    init() throws {
        root = try PrivateFiles.canonicalDirectory(FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        try PrivateFiles.makeDirectory(root)
    }
    func legacy(_ subjects: [String], pending: Bool? = nil) throws {
        var accounts: [Account] = []
        for name in subjects {
            let bytes = try syntheticAuth(name)
            var account = try Account(snapshot: AuthSnapshot(bytes))
            account.nickname = "Example \(name)"
            account.updatedAt = Date(timeIntervalSince1970: 1000)
            accounts.append(account); records[account.id] = bytes
        }
        if let pending {
            var backup = SwitchBackup(previous: try syntheticAuth("departing"), targetIdentity: try AuthSnapshot(syntheticAuth("target")).identity, home: root.appendingPathComponent("home").path)
            backup.isPending = pending
            records["switch-recovery"] = try JSONEncoder().encode(backup)
        }
        try PrivateFiles.write(JSONEncoder().encode(accounts), to: root.appendingPathComponent("accounts.json"))
    }
    func open() throws { store = try AccountStore(directory: root, vault: vault) }
    func reopen() throws { store = nil; try open() }
    deinit { store = nil; try? FileManager.default.removeItem(at: root) }
}

final class FileStoreTests: XCTestCase {
    func testNewStoreCRUDAndRecoverySurviveRelaunchWithoutKeychain() throws {
        let f = try StoreFixture(); try f.open()
        let a = try f.store!.upsert(syntheticAuth("a"))
        _ = try f.store!.upsert(syntheticAuth("b"))
        let rotated = try syntheticAuth("a", token: "example-new-access")
        try f.store!.upsert(rotated)
        let backup = SwitchBackup(previous: rotated, targetIdentity: a.id, home: f.root.path)
        try f.store!.saveBackup(backup)
        try f.reopen()
        XCTAssertEqual(try f.store!.snapshot(a.id), rotated)
        XCTAssertEqual(try f.store!.backup()?.previous, rotated)
        XCTAssertEqual(try f.store!.backup()?.isPending, true)
        try f.store!.confirmBackup(); try f.store!.delete(a.id); try f.reopen()
        XCTAssertEqual(f.store!.accounts.count, 1)
        XCTAssertEqual(try f.store!.backup()?.isPending, false)
        XCTAssertEqual(try f.store!.backup()?.previous, rotated)
        XCTAssertTrue(f.reads.isEmpty)
        let file = f.root.appendingPathComponent("local-store-v1.json")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: f.root.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }
    func testMigrationPreservesCompleteMetadataCredentialsAndPendingRecovery() throws {
        let f = try StoreFixture(); try f.legacy(["a", "b"], pending: true); try f.open()
        let accounts = f.store!.accounts
        let oldFile = try PrivateFiles.read(f.root.appendingPathComponent("accounts.json"))
        XCTAssertTrue(f.store!.needsMigration); XCTAssertTrue(f.reads.isEmpty)
        XCTAssertThrowsError(try f.store!.upsert(syntheticAuth("c")))
        XCTAssertThrowsError(try f.store!.delete(accounts[0].id))
        XCTAssertThrowsError(try f.store!.backup())
        XCTAssertTrue(f.reads.isEmpty)
        try f.store!.migrate()
        XCTAssertEqual(f.reads, accounts.map(\.id) + ["switch-recovery"])
        XCTAssertFalse(f.store!.needsMigration)
        XCTAssertEqual(f.store!.accounts, accounts)
        XCTAssertEqual(try f.store!.backup()?.isPending, true)
        XCTAssertEqual(try f.store!.backup()?.home, f.root.appendingPathComponent("home").path)
        XCTAssertEqual(try f.store!.snapshot(accounts[1].id), f.records[accounts[1].id])
        XCTAssertEqual(try PrivateFiles.read(f.root.appendingPathComponent("accounts.json")), oldFile)
        f.reads = []; f.records = [:]; try f.reopen(); try f.store!.migrate()
        try f.store!.confirmBackup(); _ = try f.store!.upsert(syntheticAuth("c")); try f.store!.delete(accounts[0].id)
        XCTAssertTrue(f.reads.isEmpty)
    }
    func testEmptyLegacyListStillMigratesRecoveryAndNewEmptyStoreDoesNotReadIt() throws {
        let f = try StoreFixture(); try f.legacy([], pending: false); try f.open()
        try f.store!.migrate(); XCTAssertEqual(f.reads, ["switch-recovery"])
        XCTAssertNotNil(try f.store!.backup())
        let g = try StoreFixture(); try g.open()
        XCTAssertFalse(g.store!.needsMigration); XCTAssertTrue(g.reads.isEmpty)
    }
    func testDenialMissingAndMalformedRecordNeverCommitPartialMigration() throws {
        for kind in ["denied", "missing", "mismatch", "journal"] {
            let f = try StoreFixture(); try f.legacy(["a", "b"], pending: true); try f.open()
            let second = f.store!.accounts[1].id
            let original = f.records
            switch kind {
            case "denied": f.denied = second
            case "missing": f.records.removeValue(forKey: second)
            case "mismatch": f.records[second] = try syntheticAuth("wrong")
            default: f.records["switch-recovery"] = Data("{}".utf8)
            }
            XCTAssertThrowsError(try f.store!.migrate())
            XCTAssertTrue(f.store!.needsMigration)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.root.appendingPathComponent("local-store-v1.json").path))
            try f.reopen(); XCTAssertTrue(f.store!.needsMigration)
            f.denied = nil; f.records = original
            try f.store!.migrate(); XCTAssertFalse(f.store!.needsMigration)
        }
    }
    func testDeniedRecoveryIsNotMistakenForAbsent() throws {
        let f = try StoreFixture(); try f.legacy(["a"]); try f.open()
        f.denied = "switch-recovery"
        XCTAssertThrowsError(try f.store!.migrate()); XCTAssertTrue(f.store!.needsMigration)
        f.denied = nil; try f.store!.migrate(); XCTAssertNil(try f.store!.backup())
    }
    func testFailedCommitKeepsOriginalDataAndRejectsSymlinks() throws {
        let f = try StoreFixture(); try f.open(); let a = try f.store!.upsert(syntheticAuth("a"))
        let file = f.root.appendingPathComponent("local-store-v1.json")
        let original = try XCTUnwrap(try PrivateFiles.read(file))
        let saved = f.root.appendingPathComponent("saved")
        try FileManager.default.moveItem(at: file, to: saved)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: saved)
        XCTAssertThrowsError(try f.store!.delete(a.id))
        XCTAssertEqual(f.store!.accounts.count, 1)
        XCTAssertEqual(try PrivateFiles.read(saved), original)
        f.store = nil
        XCTAssertThrowsError(try f.open())
    }
    func testMigrationWriteFailureCanRetryWithoutLosingOldRecords() throws {
        let f = try StoreFixture(); try f.legacy(["a", "b"]); try f.open()
        let file = f.root.appendingPathComponent("local-store-v1.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertThrowsError(try f.store!.migrate())
        XCTAssertTrue(f.store!.needsMigration); XCTAssertEqual(f.store!.accounts.count, 2)
        try FileManager.default.removeItem(at: file)
        try f.store!.migrate(); XCTAssertEqual(f.store!.accounts.count, 2)
    }
    func testInterruptedStagingIsIgnoredAndReapedAndInstanceLockIsExclusive() throws {
        let f = try StoreFixture(); try f.legacy(["a"])
        let stage = f.root.appendingPathComponent("migration-\(UUID().uuidString)")
        try PrivateFiles.write(Data("incomplete".utf8), to: stage)
        try f.open()
        XCTAssertTrue(f.store!.needsMigration); XCTAssertTrue(f.reads.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.path))
        XCTAssertThrowsError(try AccountStore(directory: f.root, vault: f.vault))
        try f.store!.migrate(); try f.reopen(); XCTAssertFalse(f.store!.needsMigration)
    }
    func testTamperedActiveDataNeverFallsBackToLegacyKeychain() throws {
        let f = try StoreFixture(); try f.legacy(["a"]); try f.open(); try f.store!.migrate()
        f.store = nil; f.reads = []
        try PrivateFiles.write(Data("{}".utf8), to: f.root.appendingPathComponent("local-store-v1.json"))
        XCTAssertThrowsError(try f.open()); XCTAssertTrue(f.reads.isEmpty)
    }
}

@MainActor private final class StoredSwitchEnvironment: SwitchEnvironment {
    let store: AccountStore
    let home: URL
    var homePath: String { home.path }
    var failLaunch = false
    var rotateOnStop: Data?
    init(store: AccountStore, home: URL) { self.store = store; self.home = home }
    func preflight() throws {}
    func stopDesktop() async throws {
        if let rotateOnStop { try writeLive(rotateOnStop); self.rotateOnStop = nil }
    }
    func startDesktop() async throws { if failLaunch { throw AccountsError.message("Synthetic launch failure") } }
    func readLive() throws -> Data? { try PrivateFiles.read(home.appendingPathComponent("auth.json")) }
    func writeLive(_ data: Data?) throws {
        let file = home.appendingPathComponent("auth.json")
        if let data { try PrivateFiles.write(data, to: file) } else { try PrivateFiles.remove(file) }
    }
    func saveBackup(_ backup: SwitchBackup) throws { try store.saveBackup(backup) }
    func archiveDeparting(_ data: Data) throws { try store.upsert(data) }
}

extension FileStoreTests {
    @MainActor func testFileBackedTransactionArchivesRotationAndRestoresAfterRelaunch() async throws {
        let f = try StoreFixture(); try f.open()
        let a = try syntheticAuth("a"), b = try syntheticAuth("b")
        let rotated = try syntheticAuth("a", token: "example-rotated")
        var env: StoredSwitchEnvironment? = StoredSwitchEnvironment(store: f.store!, home: f.root.appendingPathComponent("home"))
        try env!.writeLive(a); env!.rotateOnStop = rotated
        _ = try f.store!.upsert(b)
        _ = try await SwitchTransaction.run(target: b, environment: env!)
        XCTAssertEqual(try env!.readLive(), b)
        XCTAssertEqual(try f.store!.snapshot(AuthSnapshot(a).identity), rotated)
        XCTAssertEqual(try f.store!.backup()?.previous, rotated)
        env = nil; try f.reopen()
        env = StoredSwitchEnvironment(store: f.store!, home: f.root.appendingPathComponent("home"))
        let backup = try XCTUnwrap(try f.store!.backup())
        XCTAssertTrue(backup.isPending)
        try await SwitchTransaction.restore(backup, environment: env!)
        XCTAssertEqual(try env!.readLive(), rotated)
        try f.store!.confirmBackup(); XCTAssertEqual(try f.store!.backup()?.isPending, false)
        XCTAssertTrue(f.reads.isEmpty)
    }
    @MainActor func testFileBackedFailedLaunchRestoresOriginalWithoutLosingJournal() async throws {
        let f = try StoreFixture(); try f.open()
        let env = StoredSwitchEnvironment(store: f.store!, home: f.root.appendingPathComponent("home"))
        let original = try syntheticAuth("a")
        try env.writeLive(original); env.failLaunch = true
        do { _ = try await SwitchTransaction.run(target: syntheticAuth("b"), environment: env); XCTFail("Expected synthetic launch failure") }
        catch { XCTAssertEqual(try env.readLive(), original) }
        XCTAssertEqual(try f.store!.backup()?.previous, original)
        XCTAssertEqual(try f.store!.backup()?.isPending, true)
        XCTAssertTrue(f.reads.isEmpty)
    }
}
