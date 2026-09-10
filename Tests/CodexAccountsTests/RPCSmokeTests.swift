import XCTest
import AccountsCore
@testable import CodexAccounts

final class RPCSmokeTests: XCTestCase {
    @MainActor func testRealCLIInEmptyIsolatedHome() async throws {
        guard let path = ProcessInfo.processInfo.environment["CODEX_ACCOUNTS_TEST_CLI"] else {
            throw XCTSkip("Set CODEX_ACCOUNTS_TEST_CLI to a trusted local Codex executable for the opt-in smoke test.")
        }
        let root = (try PrivateFiles.canonicalDirectory(FileManager.default.temporaryDirectory)).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try IsolatedSession(root: root)
        do {
            try await session.rpc.start(executable: URL(fileURLWithPath: path), home: session.home)
            let account = try await session.rpc.request("account/read", ["refreshToken": false])
            XCTAssertTrue(account["account"] is NSNull)
            let response = try await session.rpc.request("config/read", ["includeLayers": false])
            let config = response["config"] as? [String: Any]
            XCTAssertEqual(config?["cli_auth_credentials_store"] as? String, "file")
            await session.close()
            XCTAssertFalse(FileManager.default.fileExists(atPath: session.home.path))
        } catch {
            await session.close(); throw error
        }
    }
}

final class LocalStoreTests: XCTestCase {
    func testOnlyAbandonedUUIDSessionsAreReaped() throws {
        let root = try PrivateFiles.canonicalDirectory(FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("Sessions")
        let abandoned = sessions.appendingPathComponent(UUID().uuidString)
        let unrelated = sessions.appendingPathComponent("not-a-session")
        try PrivateFiles.makeDirectory(abandoned)
        try PrivateFiles.write(Data("synthetic-login-placeholder".utf8), to: abandoned.appendingPathComponent("auth.json"))
        try PrivateFiles.makeDirectory(unrelated)
        let store = try AccountStore(directory: root)
        withExtendedLifetime(store) {
            XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
        }
    }
    func testSessionCleanupRefusesSymlink() throws {
        let root = try PrivateFiles.canonicalDirectory(FileManager.default.temporaryDirectory).appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("preserve")
        try PrivateFiles.makeDirectory(outside)
        let sessions = root.appendingPathComponent("Sessions")
        try FileManager.default.createSymbolicLink(at: sessions, withDestinationURL: outside)
        XCTAssertThrowsError(try AccountStore(directory: root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }
    @MainActor func testDemoUsesOnlyExampleAccountsAndRejectsMutation() {
        let model = AppModel(demo: true)
        let original = model.accounts
        XCTAssertEqual(original.count, 3)
        XCTAssertTrue(original.allSatisfy { $0.email.hasSuffix("@example.com") })
        XCTAssertFalse(model.configured)
        model.importCurrent(); model.switchTo(original[1].id); model.delete(original[0].id)
        XCTAssertFalse(model.busy); XCTAssertEqual(model.accounts, original)
    }
}
