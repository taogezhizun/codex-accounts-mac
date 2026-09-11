import XCTest
import Security
import AccountsCore
@testable import CodexAccounts

/// Real, non-demo AppModel lifecycle with isolated files/defaults and a spy in place of SecItemCopyMatching.
/// No real credentials, Keychain items, network requests or desktop processes are used.
@MainActor final class RecoveryLifecycleTests: XCTestCase {
    @MainActor private final class Fixture {
        let root: URL
        let defaults: UserDefaults
        let suite = "org.codexaccounts.tests.\(UUID().uuidString)"
        let credentials: Data
        let current: Account
        let other: Account
        var reads: [String] = []
        var journal: Data?
        var readStatus: OSStatus = errSecSuccess
        var returnTarget = false
        var model: AppModel!

        init(pending: Bool? = nil, services: Bool = false) throws {
            root = try PrivateFiles.canonicalDirectory(FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
            defaults = UserDefaults(suiteName: suite)!
            func auth(_ subject: String) throws -> Data {
                let claims = try JSONSerialization.data(withJSONObject: ["sub": subject, "email": "example@example.com"]).base64EncodedString()
                return try JSONSerialization.data(withJSONObject: ["tokens": ["account_id": "example-workspace", "id_token": "demo.\(claims).demo", "access_token": "example-access", "refresh_token": "example-refresh"]])
            }
            credentials = try auth("other")
            current = try Account(snapshot: AuthSnapshot(auth("current")))
            other = try Account(snapshot: AuthSnapshot(credentials))
            let home = root.appendingPathComponent("home")
            let directory = root.appendingPathComponent("store")
            try PrivateFiles.makeDirectory(home)
            try PrivateFiles.makeDirectory(directory)
            try PrivateFiles.write(auth("current"), to: home.appendingPathComponent("auth.json"))
            try PrivateFiles.write(JSONEncoder().encode([current, other]), to: directory.appendingPathComponent("accounts.json"))
            if let pending {
                var backup = SwitchBackup(previous: nil, targetIdentity: other.id, home: home.path)
                backup.isPending = pending
                journal = try JSONEncoder().encode(backup)
            }
            defaults.set(home.path, forKey: "codexHome")
            // An absent, unique app fails preflight before any helper or desktop action.
            defaults.set(root.appendingPathComponent("Missing.app").path, forKey: "desktopApplication")
            defaults.set(false, forKey: "automaticRefresh")
            let vault = KeychainVault { [unowned self] query, result in
                let key = (query as NSDictionary)[kSecAttrAccount] as! String
                self.reads.append(key)
                if self.readStatus != errSecSuccess { return self.readStatus }
                let data = key == "switch-recovery" ? self.journal : self.returnTarget ? self.credentials : nil
                guard let data else { return errSecItemNotFound }
                result.pointee = data as CFData
                return errSecSuccess
            }
            model = AppModel(directory: directory, defaults: defaults, startServices: services, vault: vault)
        }
        func clean() {
            model = nil
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        func finish() async {
            for _ in 0..<200 {
                await Task.yield()
                if !model.busy { return }
            }
            XCTFail("Isolated operation did not finish")
        }
    }

    func testNormalStartupAndScheduledServicesNeverProbeExistingJournal() async throws {
        let f = try Fixture(pending: true, services: true); defer { f.clean() }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(f.reads.isEmpty)
        XCTAssertEqual(f.model.accounts.count, 2)
        XCTAssertEqual(f.model.currentIdentity, f.current.id)
        XCTAssertTrue(f.model.recoveryNeedsUnlock)
        XCTAssertFalse(f.model.awaitingConfirmation)
        XCTAssertNil(f.model.error)
        f.model.checkCurrentIdentity()
        f.model.selection = f.other.id
        f.model.rename(f.other.id, nickname: "Example")
        XCTAssertTrue(f.reads.isEmpty)
    }

    func testManualAndAutomaticQuotaRefreshRunWithoutReadingJournal() async throws {
        let f = try Fixture(pending: true); defer { f.clean() }
        f.readStatus = errSecAuthFailed
        f.model.refresh(f.current.id)
        XCTAssertTrue(f.model.busy, "Unchecked recovery must not block current quota refresh")
        await f.finish()
        XCTAssertTrue(f.reads.isEmpty)
        XCTAssertNotNil(f.model.error, "Fixture must reach the missing-app preflight")
        f.model.automaticRefresh = true
        f.model.automaticRefreshTick(now: Date().addingTimeInterval(7200))
        XCTAssertTrue(f.model.refreshingAutomatically)
        await f.finish()
        f.model.automaticRefresh = false
        XCTAssertTrue(f.reads.isEmpty)
    }

    func testOrdinaryOperationFailureDoesNotRecheckRecovery() async throws {
        let f = try Fixture(pending: true); defer { f.clean() }
        try PrivateFiles.remove(f.model.home.appendingPathComponent("auth.json"))
        f.model.importCurrent()
        await f.finish()
        XCTAssertNotNil(f.model.error)
        XCTAssertTrue(f.reads.isEmpty)
    }

    func testRelaunchedPendingJournalStopsSwitchBeforeTargetRead() async throws {
        let f = try Fixture(pending: true); defer { f.clean() }
        f.model.switchTo(f.other.id)
        await f.finish()
        XCTAssertEqual(f.reads, ["switch-recovery"])
        XCTAssertTrue(f.model.awaitingConfirmation)
        XCTAssertTrue(f.model.hasBackup)
        XCTAssertFalse(f.model.recoveryNeedsUnlock)
        XCTAssertNotNil(f.model.switchBlockReason(f.other.id))
    }

    func testDeniedRecoveryReadStopsSwitchAndDoesNotRetryInBackground() async throws {
        let f = try Fixture(); defer { f.clean() }
        f.readStatus = errSecAuthFailed
        f.model.switchTo(f.other.id)
        await f.finish()
        f.model.automaticRefreshTick()
        XCTAssertEqual(f.reads, ["switch-recovery"])
        XCTAssertTrue(f.model.recoveryNeedsUnlock)
        XCTAssertTrue(f.model.awaitingConfirmation)
        XCTAssertNotNil(f.model.error)
        f.readStatus = errSecSuccess
        f.model.unlockRecoveryRecord()
        XCTAssertEqual(f.reads, ["switch-recovery", "switch-recovery"])
        XCTAssertFalse(f.model.awaitingConfirmation)
        XCTAssertFalse(f.model.recoveryNeedsUnlock)
    }

    func testMalformedJournalIsNotTreatedAsAbsent() async throws {
        let f = try Fixture(); defer { f.clean() }
        f.journal = Data("not-json".utf8)
        f.model.switchTo(f.other.id)
        await f.finish()
        XCTAssertEqual(f.reads, ["switch-recovery"])
        XCTAssertTrue(f.model.awaitingConfirmation)
        XCTAssertTrue(f.model.recoveryNeedsUnlock)
    }

    func testTransactionFailureLeavesRecoveryUnknownWithoutAnotherRead() async throws {
        let f = try Fixture(pending: false); defer { f.clean() }
        f.returnTarget = true
        f.model.switchTo(f.other.id)
        await f.finish()
        // Missing-app preflight rejects the transaction before it can stop any real desktop.
        XCTAssertEqual(f.reads, ["switch-recovery", f.other.id])
        XCTAssertTrue(f.model.awaitingConfirmation)
        XCTAssertTrue(f.model.recoveryNeedsUnlock)
        XCTAssertNotNil(f.model.error)
    }

    func testRestoreChecksForBackupOnlyAfterExplicitAction() async throws {
        let f = try Fixture(); defer { f.clean() }
        XCTAssertTrue(f.reads.isEmpty)
        f.model.restore()
        await f.finish()
        XCTAssertEqual(f.reads, ["switch-recovery"])
        XCTAssertFalse(f.model.hasBackup)
        XCTAssertFalse(f.model.awaitingConfirmation)
        XCTAssertNotNil(f.model.error)
    }
}
