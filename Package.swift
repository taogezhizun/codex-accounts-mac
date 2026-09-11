// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CodexAccounts",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CodexAccounts", targets: ["CodexAccounts"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .target(name: "AccountsCore"),
        .executableTarget(name: "CodexAccounts", dependencies: ["AccountsCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "AccountsCoreTests", dependencies: ["AccountsCore"]),
        .testTarget(name: "CodexAccountsTests", dependencies: ["CodexAccounts"])
    ]
)
