import XCTest
@testable import CodexAccounts

final class RefreshScheduleTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    func testLaunchRefreshesEachAccountThenWaitsFiveMinutes() {
        var schedule = RefreshSchedule()
        schedule.reconcile(["a", "b"], now: start)
        XCTAssertEqual(schedule.due(now: start, enabled: true, blocked: false), "a")
        schedule.completed("a", succeeded: true, now: start)
        XCTAssertEqual(schedule.due(now: start, enabled: true, blocked: false), "b")
        schedule.completed("b", succeeded: true, now: start)
        XCTAssertNil(schedule.due(now: start.addingTimeInterval(299), enabled: true, blocked: false))
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(300), enabled: true, blocked: false), "a")
    }
    func testFailuresBackOffAndDoNotStarveOtherAccounts() {
        var schedule = RefreshSchedule(); schedule.reconcile(["a", "b"], now: start)
        for delay in [600.0, 1200, 2400, 3600, 3600] {
            schedule.completed("a", succeeded: false, now: start)
            XCTAssertEqual(schedule.next["a"], start.addingTimeInterval(delay))
            XCTAssertEqual(schedule.due(now: start, enabled: true, blocked: false), "b")
        }
        schedule.completed("a", succeeded: true, now: start)
        XCTAssertEqual(schedule.next["a"], start.addingTimeInterval(300))
        XCTAssertEqual(schedule.failures["a"], 0)
    }
    func testBusyDisabledAndWakeDoNotCreateCatchUpBursts() {
        var schedule = RefreshSchedule(); schedule.reconcile(["a"], now: start)
        let wake = start.addingTimeInterval(86400)
        XCTAssertNil(schedule.due(now: wake, enabled: false, blocked: false))
        XCTAssertNil(schedule.due(now: wake, enabled: true, blocked: true))
        XCTAssertEqual(schedule.due(now: wake, enabled: true, blocked: false), "a")
        schedule.completed("a", succeeded: true, now: wake)
        XCTAssertNil(schedule.due(now: wake, enabled: true, blocked: false))
    }
    func testReconciliationDoesNotResetExistingCadenceAndNewAccountsArePrompt() {
        var schedule = RefreshSchedule(); schedule.reconcile(["a", "removed"], now: start)
        schedule.completed("a", succeeded: true, now: start)
        schedule.reconcile(["a", "new"], now: start.addingTimeInterval(10))
        XCTAssertNil(schedule.next["removed"])
        XCTAssertEqual(schedule.next["a"], start.addingTimeInterval(300))
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(10), enabled: true, blocked: false), "new")
    }
    func testManualRefreshAndReimportResetCadence() {
        var schedule = RefreshSchedule(); schedule.reconcile(["a"], now: start)
        schedule.completed("a", succeeded: false, now: start)
        schedule.request("a", now: start.addingTimeInterval(5))
        XCTAssertEqual(schedule.due(now: start.addingTimeInterval(5), enabled: true, blocked: false), "a")
        schedule.completed("a", succeeded: true, now: start.addingTimeInterval(6))
        XCTAssertEqual(schedule.next["a"], start.addingTimeInterval(306))
    }
    @MainActor func testDemoNeverStartsBackgroundWorkOrUpdater() {
        let model = AppModel(demo: true)
        model.automaticRefreshTick(now: start)
        model.updates.start(); model.updates.check()
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.nextRefresh)
        XCTAssertFalse(model.updates.sessionInProgress)
        XCTAssertFalse(model.updates.canCheck)
    }
}
