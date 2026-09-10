import XCTest
@testable import AccountsCore
import Darwin

func sample(_ user: String = "one", account: String = "workspace", rotated: Bool = false) throws -> Data {
    let payload = try JSONSerialization.data(withJSONObject: ["sub": user, "email": "\(user)@example.com"])
        .base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return try JSONSerialization.data(withJSONObject: ["auth_mode": "chatgpt", "tokens": ["account_id": account,
        "id_token": "fixture.\(payload).fixture", "access_token": rotated ? "rotated-fixture" : "fixture", "refresh_token": "fixture"]])
}

final class AuthTests: XCTestCase {
    func testIdentityStableAcrossRotationButDistinctAcrossUsersAndWorkspaces() throws {
        let first = try AuthSnapshot(sample())
        XCTAssertEqual(first.identity, try AuthSnapshot(sample(rotated: true)).identity)
        XCTAssertNotEqual(first.identity, try AuthSnapshot(sample("two")).identity)
        XCTAssertNotEqual(first.identity, try AuthSnapshot(sample(account: "other")).identity)
    }
    func testRejectsAPIKeyMalformedAndIncompleteCredentials() throws {
        for data in [Data("{}".utf8), Data("not json".utf8), Data("{\"OPENAI_API_KEY\":\"fixture\"}".utf8), Data(repeating: 0, count: 1_048_577)] {
            XCTAssertThrowsError(try AuthSnapshot(data))
        }
        var root = try JSONSerialization.jsonObject(with: sample()) as! [String: Any]
        root["OPENAI_API_KEY"] = "fixture"
        XCTAssertThrowsError(try AuthSnapshot(JSONSerialization.data(withJSONObject: root)))
    }
    func testNullQuotaIsUnknownAndPrimaryMapWins() {
        XCTAssertTrue(QuotaWindow.parse(["rateLimits": ["primary": NSNull()]]).isEmpty)
        let rows = QuotaWindow.parse([
            "rateLimits": ["primary": ["usedPercent": 100.0]],
            "rateLimitsByLimitId": ["codex": ["primary": ["usedPercent": 21.0, "windowDurationMins": 300],
                                                    "secondary": ["usedPercent": 140.0, "windowDurationMins": 10080]]]
        ])
        XCTAssertEqual(rows.map(\.remaining), [79, 0]); XCTAssertEqual(rows.map(\.label), ["5 小时", "7 天"])
    }
    func testNoAssumedDurationForUnknownWindow() {
        let rows = QuotaWindow.parse(["rateLimits": ["primary": ["usedPercent": 12.0]]])
        XCTAssertEqual(rows.first?.label, "主要窗口")
    }
    func testAllLimitBucketsArePreserved() {
        let rows = QuotaWindow.parse(["rateLimitsByLimitId": ["a": ["primary": ["usedPercent": 1.0]], "b": ["primary": ["usedPercent": 9.0]]]])
        XCTAssertEqual(rows.count, 2); XCTAssertEqual(Set(rows.map(\.id)).count, 2)
    }
}

final class FileTests: XCTestCase {
    var root: URL!
    override func setUpWithError() throws {
        root = (try PrivateFiles.canonicalDirectory(FileManager.default.temporaryDirectory)).appendingPathComponent(UUID().uuidString)
        try PrivateFiles.makeDirectory(root)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testAtomicWriteKeepsPermissionsPrivateAndLeavesNoTemp() throws {
        let file = root.appendingPathComponent("auth.json")
        try PrivateFiles.write(Data("old".utf8), to: file)
        try PrivateFiles.write(Data("new".utf8), to: file)
        XCTAssertEqual(try PrivateFiles.read(file), Data("new".utf8))
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["auth.json"])
    }
    func testRejectsSymlinkWithoutChangingDestination() throws {
        let target = root.appendingPathComponent("target")
        try PrivateFiles.write(Data("unchanged".utf8), to: target)
        let link = root.appendingPathComponent("auth.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try PrivateFiles.read(link))
        XCTAssertThrowsError(try PrivateFiles.write(Data("bad".utf8), to: link))
        XCTAssertEqual(try PrivateFiles.read(target), Data("unchanged".utf8))
    }
    func testRejectsParentSymlink() throws {
        let real = root.appendingPathComponent("real"); try PrivateFiles.makeDirectory(real)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertThrowsError(try PrivateFiles.write(Data(), to: link.appendingPathComponent("auth.json")))
    }
    func testRejectsDirectoryAndOversizeInput() throws {
        XCTAssertThrowsError(try PrivateFiles.read(root))
        let large = root.appendingPathComponent("large")
        try PrivateFiles.write(Data(repeating: 0, count: 1_048_577), to: large)
        XCTAssertThrowsError(try PrivateFiles.read(large))
    }
    func testSecondInstanceCannotTakeLock() throws {
        let path = root.appendingPathComponent("lock")
        let first = try ExclusiveLock(at: path)
        try withExtendedLifetime(first) { XCTAssertThrowsError(try ExclusiveLock(at: path)) }
    }
    func testStorageGuardRejectsAmbiguousOrNonFileModes() throws {
        try StoragePolicy.validate(config: "# comment\nmodel = \"example\"\n")
        try StoragePolicy.validate(config: "'cli_auth_credentials_store' = 'file' # comment\n[features]\nother=true")
        for config in ["cli_auth_credentials_store = 'keyring'", "cli_auth_credentials_store = 'auto'", "cli_auth_credentials_store = 'ephemeral'", "[profile]\ncli_auth_credentials_store='file'", "cli_auth_credentials_store='file'\ncli_auth_credentials_store='file'"] {
            XCTAssertThrowsError(try StoragePolicy.validate(config: config))
        }
    }
}

@MainActor final class FakeEnvironment: SwitchEnvironment {
    var homePath = "/fixture/codex"
    var live: Data?
    var backup: SwitchBackup?
    var events: [String] = []
    var stopFails = false
    var backupFails = false
    var startFails = false
    var mutateOnStart: Data?
    var mutateAfterBackup: Data?
    var rotateOnStop: Data?
    init(live: Data?) { self.live = live }
    func preflight() throws { events.append("preflight") }
    func stopDesktop() async throws {
        events.append("stop")
        if stopFails { throw AccountsError.message("busy") }
        if let rotateOnStop { live = rotateOnStop }
    }
    func startDesktop() async throws {
        events.append("start")
        if let mutateOnStart { live = mutateOnStart }
        if startFails { throw AccountsError.message("start failed") }
    }
    func readLive() throws -> Data? { live }
    func writeLive(_ data: Data?) throws { events.append("write"); live = data }
    func saveBackup(_ backup: SwitchBackup) throws {
        events.append("backup")
        if backupFails { throw AccountsError.message("keychain locked") }
        self.backup = backup
        if let mutateAfterBackup { live = mutateAfterBackup }
    }
    func archiveDeparting(_ data: Data) throws { events.append("archive") }
}

final class SwitchTests: XCTestCase {
    @MainActor func testSuccessfulSwitchBacksUpShutdownRotationBeforeWriting() async throws {
        let fresh = try sample(rotated: true), target = try sample("two")
        let env = FakeEnvironment(live: try sample()); env.rotateOnStop = fresh
        _ = try await SwitchTransaction.run(target: target, environment: env)
        XCTAssertEqual(env.events, ["preflight", "stop", "archive", "backup", "write", "start"])
        XCTAssertEqual(env.backup?.previous, fresh); XCTAssertEqual(env.live, target)
        XCTAssertEqual(env.backup?.isPending, true)
    }
    @MainActor func testStopFailureNeverBacksUpOrWrites() async throws {
        let old = try sample(); let env = FakeEnvironment(live: old); env.stopFails = true
        do { _ = try await SwitchTransaction.run(target: sample("two"), environment: env); XCTFail() } catch {}
        XCTAssertEqual(env.live, old); XCTAssertFalse(env.events.contains("write")); XCTAssertNil(env.backup)
    }
    @MainActor func testBackupFailureNeverWritesLive() async throws {
        let old = try sample(); let env = FakeEnvironment(live: old); env.backupFails = true
        do { _ = try await SwitchTransaction.run(target: sample("two"), environment: env); XCTFail() } catch {}
        XCTAssertEqual(env.live, old); XCTAssertFalse(env.events.contains("write"))
    }
    @MainActor func testFailedLaunchRestoresPrevious() async throws {
        let old = try sample(); let env = FakeEnvironment(live: old); env.startFails = true
        do { _ = try await SwitchTransaction.run(target: sample("two"), environment: env); XCTFail() } catch {}
        XCTAssertEqual(env.live, old); XCTAssertNotNil(env.backup)
    }
    @MainActor func testFailedLaunchDoesNotOverwriteConcurrentLogin() async throws {
        let third = try sample("third"); let env = FakeEnvironment(live: try sample())
        env.startFails = true; env.mutateOnStart = third
        do { _ = try await SwitchTransaction.run(target: sample("two"), environment: env); XCTFail() } catch {}
        XCTAssertEqual(env.live, third)
    }
    @MainActor func testConcurrentWriteAfterBackupStopsSwitch() async throws {
        let third = try sample("third"); let env = FakeEnvironment(live: try sample()); env.mutateAfterBackup = third
        do { _ = try await SwitchTransaction.run(target: sample("two"), environment: env); XCTFail() } catch {}
        XCTAssertEqual(env.live, third); XCTAssertFalse(env.events.contains("write"))
    }
    @MainActor func testRestoreAcceptsRotatedTargetAndPreservesIt() async throws {
        let old = try sample(); let target = try sample("two")
        let env = FakeEnvironment(live: try sample("two", rotated: true))
        let backup = SwitchBackup(previous: old, targetIdentity: try AuthSnapshot(target).identity, home: env.homePath)
        try await SwitchTransaction.restore(backup, environment: env)
        XCTAssertEqual(env.live, old); XCTAssertTrue(env.events.contains("archive"))
    }
    @MainActor func testRestoreRejectsOtherDirectoryOrUnrelatedAccount() async throws {
        let env = FakeEnvironment(live: try sample("third"))
        let backup = SwitchBackup(previous: try sample(), targetIdentity: try AuthSnapshot(sample("two")).identity, home: "/elsewhere")
        do { try await SwitchTransaction.restore(backup, environment: env); XCTFail() } catch {}
        XCTAssertTrue(env.events.isEmpty)
        let sameHome = SwitchBackup(previous: try sample(), targetIdentity: backup.targetIdentity, home: env.homePath)
        do { try await SwitchTransaction.restore(sameHome, environment: env); XCTFail() } catch {}
        XCTAssertFalse(env.events.contains("write"))
    }
    @MainActor func testMissingOriginalRestoresToNoFile() async throws {
        let env = FakeEnvironment(live: nil); env.startFails = true
        do { _ = try await SwitchTransaction.run(target: sample("two"), environment: env); XCTFail() } catch {}
        XCTAssertNil(env.live)
    }
    @MainActor func testInvalidTargetDoesNotStopDesktop() async throws {
        let env = FakeEnvironment(live: try sample())
        do { _ = try await SwitchTransaction.run(target: Data(), environment: env); XCTFail() } catch {}
        XCTAssertTrue(env.events.isEmpty)
    }
}
