import XCTest
import AccountsCore
@testable import CodexAccounts

final class StatusBarQuotaTests: XCTestCase {
    func testUsesTightestCodexPeriodWithoutOtherPoolsAndHidesEmail() throws {
        let now = Date()
        var a = try Account(snapshot: AuthSnapshot(syntheticAuth("a")))
        a.updatedAt = now
        a.quotas = [.init(id: "week", label: "7 天", remaining: 74, bucketID: "codex"),
                    .init(id: "short", label: "5 小时", remaining: 95, bucketID: "codex"),
                    .init(id: "other", label: "7 天", remaining: 1, bucketID: "other")]
        let value = StatusBarQuota.make(account: a, pending: false, hideEmails: true, now: now)
        XCTAssertEqual(value.text, "74%")
        XCTAssertTrue(value.help.contains("7 天")); XCTAssertTrue(value.help.contains("剩余"))
        XCTAssertFalse(value.help.contains(a.email))
        XCTAssertTrue(StatusBarQuota.make(account: a, pending: false, hideEmails: false).help.contains(a.email))
    }
    func testUnknownPendingZeroFullAndStaleAreDistinct() throws {
        var a = try Account(snapshot: AuthSnapshot(syntheticAuth("a")))
        let now = Date(); a.updatedAt = now
        XCTAssertEqual(StatusBarQuota.make(account: nil, pending: false, hideEmails: true).text, "—")
        XCTAssertEqual(StatusBarQuota.make(account: a, pending: false, hideEmails: true).text, "—")
        for percentage in [0.0, 100.0] {
            a.quotas = [.init(id: "week", label: "7 天", remaining: percentage, bucketID: "codex")]
            XCTAssertEqual(StatusBarQuota.make(account: a, pending: false, hideEmails: true, now: now).text, "\(Int(percentage))%")
            XCTAssertEqual(StatusBarQuota.make(account: a, pending: true, hideEmails: true, now: now).text, "—")
        }
        XCTAssertEqual(StatusBarQuota.make(account: a, pending: false, hideEmails: true, now: now.addingTimeInterval(901)).text, "~100%")
        a.issue = "Refresh failed"
        XCTAssertTrue(StatusBarQuota.make(account: a, pending: false, hideEmails: true, now: now).help.contains("上次记录"))
        a.issue = nil; a.quotas = [.init(id: "other", label: "7 天", remaining: 50, bucketID: "other")]
        XCTAssertEqual(StatusBarQuota.make(account: a, pending: false, hideEmails: true).text, "—")
    }
}
