import XCTest
import Security
import AccountsCore
@testable import CodexAccounts

final class CurrentQuotaTests: XCTestCase {
    private func credentials(_ subject: String, token: String = "example-access") throws -> Data {
        let claims = try JSONSerialization.data(withJSONObject: ["sub": subject, "email": "example@example.com"]).base64EncodedString()
        return try JSONSerialization.data(withJSONObject: ["tokens": ["account_id": "example-workspace", "id_token": "demo.\(claims).demo", "access_token": token, "refresh_token": "example-refresh"]])
    }
    func testUsesLatestLiveTokenForTheExactSavedIdentity() throws {
        let old = try credentials("a", token: "old-access")
        let current = try credentials("a", token: "new-access")
        let result = try CurrentQuotaCredentials.load(id: AuthSnapshot(old).identity) { current }
        XCTAssertEqual(result.accessToken, "new-access")
    }
    func testRejectsAnotherUserInTheSameWorkspaceAndLogout() throws {
        let id = try AuthSnapshot(credentials("a")).identity
        let other = try credentials("b")
        XCTAssertThrowsError(try CurrentQuotaCredentials.load(id: id) { other })
        XCTAssertThrowsError(try CurrentQuotaCredentials.load(id: id) { nil })
        XCTAssertThrowsError(try CurrentQuotaCredentials.load(id: id) { Data("{}".utf8) })
    }
    func testRechecksLiveIdentityBetweenRefreshStages() throws {
        let first = try credentials("a"), second = try credentials("b")
        let id = try AuthSnapshot(first).identity
        var live: Data? = first
        XCTAssertNoThrow(try CurrentQuotaCredentials.load(id: id) { live })
        live = second
        XCTAssertThrowsError(try CurrentQuotaCredentials.load(id: id) { live })
    }
    func testOnlyCurrentSavedAccountIsScheduledAndSwitchResetsCadence() {
        let now = Date(timeIntervalSince1970: 1000)
        var schedule = RefreshSchedule()
        schedule.reconcileCurrent("b", savedIDs: ["a", "b"], now: now)
        XCTAssertEqual(schedule.due(now: now, enabled: true, blocked: false), "b")
        XCTAssertNil(schedule.next["a"])
        schedule.completed("b", succeeded: true, now: now)
        schedule.reconcileCurrent("b", savedIDs: ["a", "b", "new"], now: now.addingTimeInterval(10))
        XCTAssertNil(schedule.next["new"])
        XCTAssertEqual(schedule.next["b"], now.addingTimeInterval(300))
        schedule.reconcileCurrent("a", savedIDs: ["a", "b"], now: now.addingTimeInterval(20))
        XCTAssertEqual(schedule.due(now: now.addingTimeInterval(20), enabled: true, blocked: false), "a")
        XCTAssertNil(schedule.next["b"])
    }
    func testNoBackgroundRefreshAfterLogoutOrForUnsavedLogin() {
        let now = Date()
        var schedule = RefreshSchedule()
        for current in ["a", nil, "unknown"] as [String?] {
            schedule.reconcileCurrent(current, savedIDs: ["a", "b"], now: now)
            XCTAssertEqual(schedule.next.count, current == "a" ? 1 : 0)
        }
    }
    func testExplicitRecoveryReadCanAuthorizeAndMissingItemIsAbsent() throws {
        let vault = KeychainVault { query, _ in
            XCTAssertNil((query as NSDictionary)[kSecUseAuthenticationUI])
            return errSecItemNotFound
        }
        XCTAssertNil(try vault.read("example-recovery"))
    }
}
