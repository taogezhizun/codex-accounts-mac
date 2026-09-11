import Foundation

public struct SwitchBackup: Codable {
    public let previous: Data?
    public let targetIdentity: String
    public let home: String
    public let createdAt: Date
    public var isPending: Bool = true
    public init(previous: Data?, targetIdentity: String, home: String, createdAt: Date = Date()) {
        self.previous = previous; self.targetIdentity = targetIdentity; self.home = home; self.createdAt = createdAt
    }
}

@MainActor public protocol SwitchEnvironment: AnyObject {
    var homePath: String { get }
    func preflight() throws
    func stopDesktop() async throws
    func startDesktop() async throws
    func readLive() throws -> Data?
    func writeLive(_ data: Data?) throws
    func saveBackup(_ backup: SwitchBackup) throws
    func archiveDeparting(_ data: Data) throws
}

public enum SwitchOutcome { case awaitingDesktopConfirmation }

@MainActor public enum SwitchTransaction {
    public static func run(target: Data, environment env: SwitchEnvironment) async throws -> SwitchOutcome {
        let targetAuth = try AuthSnapshot(target)
        try env.preflight()
        try await env.stopDesktop()
        // Re-read after quitting: the departing app may rotate tokens during shutdown.
        let previous = try env.readLive()
        if let previous { try env.archiveDeparting(previous) }
        let backup = SwitchBackup(previous: previous, targetIdentity: targetAuth.identity, home: env.homePath)
        try env.saveBackup(backup) // Durable private backup must precede the first live write.
        guard try env.readLive() == previous else {
            throw AccountsError.message("认证被其他程序修改，本次切换已停止；请重新打开桌面 App。")
        }
        do {
            try env.writeLive(target)
            try await env.startDesktop()
        } catch {
            // Never roll back over an unrelated concurrent login.
            let current = try env.readLive()
            if current == target || current == previous {
                try env.writeLive(previous)
                try? await env.startDesktop()
                throw AccountsError.message("切换未完成，已恢复原认证。请重新打开桌面 App 检查。")
            }
            throw AccountsError.message("切换未完成，且认证已变化。备份已保留，请使用恢复功能。")
        }
        return .awaitingDesktopConfirmation
    }

    public static func restore(_ backup: SwitchBackup, environment env: SwitchEnvironment) async throws {
        guard backup.home == env.homePath else { throw AccountsError.message("备份属于另一个认证目录，不能恢复到这里。") }
        try env.preflight()
        try await env.stopDesktop()
        let current = try env.readLive()
        let identity = current.flatMap { try? AuthSnapshot($0).identity }
        guard current == nil || current == backup.previous || identity == backup.targetIdentity else {
            throw AccountsError.message("当前账号已被其他操作更换。为保留这次登录，已停止恢复。")
        }
        if let current { try env.archiveDeparting(current) }
        guard try env.readLive() == current else { throw AccountsError.message("认证发生并发修改，已停止恢复。") }
        var pendingBackup = backup
        pendingBackup.isPending = true
        try env.saveBackup(pendingBackup)
        try env.writeLive(backup.previous)
        try await env.startDesktop()
    }
}
