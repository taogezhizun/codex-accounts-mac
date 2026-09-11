import XCTest
import CryptoKit
@testable import CodexAccounts

final class UpdateConfigurationTests: XCTestCase {
    func testReleaseRequiresSignedFeedsAndArchivesBeforeExtraction() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("resources/Info.plist"))
        let info = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
        let encoded = try XCTUnwrap(info["SUPublicEDKey"] as? String)
        let publicBytes = try XCTUnwrap(Data(base64Encoded: encoded))
        XCTAssertEqual(publicBytes.count, 32)
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: publicBytes))
        let url = try XCTUnwrap(URL(string: try XCTUnwrap(info["SUFeedURL"] as? String)))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "raw.githubusercontent.com")
        XCTAssertEqual(url.path, "/taogezhizun/codex-accounts-mac/main/appcast/arm64.xml")
    }
    @MainActor func testDisabledUpdaterCannotStartOrCheck() {
        let updates = AppUpdates(enabled: false)
        updates.start(); updates.check()
        XCTAssertFalse(updates.canCheck)
        XCTAssertFalse(updates.sessionInProgress)
        XCTAssertEqual(AppUpdates.profileURL.absoluteString, "https://github.com/taogezhizun")
        XCTAssertEqual(AppUpdates.projectURL.absoluteString, "https://github.com/taogezhizun/codex-accounts-mac")
    }
}
