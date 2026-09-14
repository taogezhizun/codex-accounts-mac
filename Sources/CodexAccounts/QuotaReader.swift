import Foundation
import AccountsCore

/// Authentication expiry is distinct from transport failures and unknown quota data.
enum QuotaReadError: Error { case needsLogin }

@MainActor protocol QuotaReading: AnyObject {
    func read(_ snapshot: AuthSnapshot, executable: URL, root: URL) async throws -> [QuotaWindow]
    func cancel()
}

/// Each reader owns one private child. Full refresh credentials are never handed to it.
@MainActor final class QuotaReader: QuotaReading {
    private var session: IsolatedSession?
    func read(_ snapshot: AuthSnapshot, executable: URL, root: URL) async throws -> [QuotaWindow] {
        try Task.checkCancellation()
        if let expiry = snapshot.accessTokenExpiresAt, expiry <= Date() { throw QuotaReadError.needsLogin }
        let helper = try IsolatedSession(root: root); session = helper
        do {
            try await helper.rpc.start(executable: executable, home: helper.home)
            try Task.checkCancellation()
            _ = try await helper.rpc.request("account/login/start", ["type": "chatgptAuthTokens", "accessToken": snapshot.accessToken, "chatgptAccountId": snapshot.accountID, "chatgptPlanType": snapshot.plan])
            let response = try await helper.rpc.request("account/rateLimits/read")
            try Task.checkCancellation()
            let windows = QuotaWindow.parse(response)
            guard !windows.isEmpty else { throw AccountsError.message("服务未返回可识别的额度，保留上次记录。") }
            await helper.close(); session = nil
            return windows
        } catch {
            let needsLogin = helper.rpc.requiresTokenRefresh
            await helper.close(); session = nil
            if Task.isCancelled { throw CancellationError() }
            if needsLogin { throw QuotaReadError.needsLogin }
            throw error
        }
    }
    func cancel() { if let session { Task { await session.rpc.close() } } }
}

/// Fixed-width batches avoid unbounded process/network fan-out. Every outcome is handled separately.
@MainActor enum QuotaBatch {
    static let concurrency = 2
    static func run(_ ids: [String], perform: @escaping @MainActor (String) async -> Void) async {
        let unique = ids.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        for start in stride(from: 0, to: unique.count, by: concurrency) {
            guard !Task.isCancelled else { return }
            let batch = Array(unique[start..<min(start + concurrency, unique.count)])
            await withTaskGroup(of: Void.self) { group in
                for id in batch { group.addTask { await perform(id) } }
                await group.waitForAll()
            }
        }
    }
}
