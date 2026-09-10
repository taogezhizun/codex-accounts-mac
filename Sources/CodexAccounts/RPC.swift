import Foundation
import AccountsCore
import Darwin

/// A private app-server child, never the desktop app's live connection.
@MainActor final class RPC {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var notifications: [[String: Any]] = []
    private var stopped = false

    func start(executable: URL, home: URL) async throws {
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://", "-c", "cli_auth_credentials_store=\"file\"", "-c", "analytics.enabled=false"]
        // Deliberately do not inherit API keys, alternate issuer URLs or provider credentials.
        let inherited = ProcessInfo.processInfo.environment
        let allow = ["PATH", "HOME", "TMPDIR", "LANG", "LC_ALL", "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY", "https_proxy", "http_proxy", "all_proxy", "no_proxy"]
        var env = Dictionary(uniqueKeysWithValues: allow.compactMap { k in inherited[k].map { (k, $0) } })
        env["CODEX_HOME"] = home.path
        process.environment = env
        process.currentDirectoryURL = home
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in self?.failAll("Codex 辅助进程已退出。请重新尝试。") }
        }
        try process.run()
        _ = try await request("initialize", ["clientInfo": ["name": "codex_accounts_mac", "version": "0.1.0"], "capabilities": ["experimentalApi": true]])
        try send(["method": "initialized"])
    }

    func request(_ method: String, _ params: [String: Any] = [:], timeout: UInt64 = 30) async throws -> [String: Any] {
        guard !stopped, process.isRunning else { throw AccountsError.message("Codex 辅助进程未就绪。") }
        nextID += 1; let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(["method": method, "id": id, "params": params]) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: AccountsError.message("无法发送 Codex 请求。")) }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: timeout * 1_000_000_000)
                self?.pending.removeValue(forKey: id)?.resume(throwing: AccountsError.message("Codex 请求超时：\(method)。请检查网络后重试。"))
            }
        }
    }

    func waitForLogin(_ id: String) async throws {
        for _ in 0..<600 {
            try Task.checkCancellation()
            if stopped { throw AccountsError.message("登录已停止。") }
            if let i = notifications.firstIndex(where: { row in
                row["method"] as? String == "account/login/completed" && (row["params"] as? [String: Any])?["loginId"] as? String == id
            }) {
                let row = notifications.remove(at: i)["params"] as? [String: Any]
                guard row?["success"] as? Bool == true else { throw AccountsError.message("浏览器登录未完成，请重新添加账号。") }
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw AccountsError.message("登录等待超过 5 分钟，请重新添加账号。")
    }

    func close() async {
        stopped = true
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        for _ in 0..<30 {
            if !process.isRunning { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        // Only our own isolated child, never the desktop process.
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        for _ in 0..<20 {
            if !process.isRunning { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        output.fileHandleForReading.readabilityHandler = nil
        failAll("操作已结束。")
    }
    private func send(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    private func receive(_ data: Data) {
        if data.isEmpty { return }
        buffer.append(data)
        guard buffer.count < 4_194_304 else { failAll("Codex 响应超过大小限制。"); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            if let id = object["id"] as? Int, object["method"] != nil {
                try? send(["id": id, "error": ["code": -32601, "message": "Unsupported server request"]])
            } else if let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                if object["error"] != nil {
                    // Server error strings may contain diagnostic paths or credentials; don't forward them.
                    continuation.resume(throwing: AccountsError.message("Codex 请求失败。凭据可能已过期，或当前版本不支持此操作。请重新登录或导入。"))
                } else { continuation.resume(returning: object["result"] as? [String: Any] ?? [:]) }
            } else if object["method"] as? String == "account/login/completed" { notifications.append(object) }
        }
    }
    private func failAll(_ message: String) {
        let all = pending; pending.removeAll()
        all.values.forEach { $0.resume(throwing: AccountsError.message(message)) }
    }
}

@MainActor final class IsolatedSession {
    let home: URL
    let rpc = RPC()
    init(root: URL) throws {
        home = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try PrivateFiles.makeDirectory(home)
    }
    func close() async {
        await rpc.close()
        try? FileManager.default.removeItem(at: home)
    }
}
