// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexAccounts",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CodexAccounts", targets: ["CodexAccounts"])],
    targets: [
        .target(name: "AccountsCore"),
        .executableTarget(name: "CodexAccounts", dependencies: ["AccountsCore"]),
        .testTarget(name: "AccountsCoreTests", dependencies: ["AccountsCore"]),
        .testTarget(name: "CodexAccountsTests", dependencies: ["CodexAccounts"])
    ]
)
