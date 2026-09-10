import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AccountsCore

@MainActor final class AppModel: ObservableObject {
    @Published var hideEmails = true {
        didSet { if !demo { UserDefaults.standard.set(hideEmails, forKey: "hideEmails") } }
    }
    @Published var appearance = "system" {
        didSet { if !demo { UserDefaults.standard.set(appearance, forKey: "appearance") } }
    }
    @Published var accounts: [Account] = []
    @Published var selection: String?
    @Published var currentIdentity: String?
    @Published var busy = false
    @Published var status = "从添加一个账号开始。"
    @Published var error: String?
    @Published var loginCode: String?
    @Published var hasBackup = false
    @Published var awaitingConfirmation = false
    @Published var application: URL?
    @Published var home: URL
    let demo: Bool
    private var store: AccountStore?
    private var operation: Task<Void, Never>?
    private var session: IsolatedSession?

    init(demo: Bool = false) {
        self.demo = demo
        let defaultHome = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().appendingPathComponent(".codex")
        home = demo ? URL(fileURLWithPath: "/demo/.codex") : UserDefaults.standard.string(forKey: "codexHome").map { URL(fileURLWithPath: $0) } ?? defaultHome
        application = demo ? nil : UserDefaults.standard.string(forKey: "desktopApplication").map { URL(fileURLWithPath: $0) } ?? Desktop.discover()
        if demo {
            loadDemo()
            if (CommandLine.arguments.contains("--demo-empty") || PreviewConfiguration.variant == "empty") { accounts = []; selection = nil; currentIdentity = nil }
            if (CommandLine.arguments.contains("--demo-pending") || PreviewConfiguration.variant == "pending") { awaitingConfirmation = true; hasBackup = true; currentIdentity = selection; status = "演示：桌面 App 已重开，请核对账号。" }
            if (CommandLine.arguments.contains("--demo-dark") || PreviewConfiguration.variant == "dark") { appearance = "dark" }
            return
        }
        hideEmails = UserDefaults.standard.object(forKey: "hideEmails") as? Bool ?? true
        appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .resolvingSymlinksInPath().appendingPathComponent("CodexAccounts", isDirectory: true)
            store = try AccountStore(directory: root)
            accounts = store!.accounts
            selection = accounts.first?.id
            // On relaunch, the encrypted journal survives even if the last process crashed.
            let backup = try store!.backup()
            hasBackup = backup != nil
            awaitingConfirmation = backup?.isPending ?? false
            refreshFileIdentity()
            status = awaitingConfirmation ? "上次切换尚待核对。请检查桌面 App 的账号，或恢复上次认证。" : (accounts.isEmpty ? "从添加一个账号开始。" : "选择账号，随时切换。")
        } catch { self.error = "本地账号库无法打开。\(safeMessage(error))" }
    }

    var selected: Account? { accounts.first { $0.id == selection } }
    var configured: Bool { application != nil && store != nil }
    var canCancel: Bool { session != nil }
    var currentAccount: Account? { accounts.first { $0.id == currentIdentity } }
    var preferredColorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    func title(_ account: Account) -> String { AccountPresentation.title(account, hideEmails: hideEmails) }
    func switchBlockReason(_ id: String) -> String? {
        if busy { return "请等待当前操作完成" }
        if awaitingConfirmation { return "请先核对或恢复上次切换" }
        if id == currentIdentity { return "已是当前认证，无需再次切换" }
        if !demo && !configured { return "请先在设置中选择桌面 App" }
        if !accounts.contains(where: { $0.id == id }) { return "账号已不存在" }
        return nil
    }
    func checkCurrentIdentity() { if !demo { refreshFileIdentity() } }
    func openDesktop() {
        run("正在打开桌面 App…") {
            try await self.desktop().startDesktop()
            self.status = "桌面 App 已打开。"
        }
    }

    func chooseApplication() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        panel.message = "选择 Codex 桌面 App（也可能显示为 ChatGPT）。"
        if panel.runModal() == .OK, let url = panel.url {
            guard Bundle(url: url)?.bundleIdentifier == Desktop.bundleID else { error = "所选应用不是 Codex 桌面 App。"; return }
            application = url; UserDefaults.standard.set(url.path, forKey: "desktopApplication")
        }
    }
    func chooseHome() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.showsHiddenFiles = true
        panel.message = "选择桌面 App 使用的 Codex 目录。通常是用户目录下的 .codex。"
        if panel.runModal() == .OK, let url = panel.url {
            home = url.resolvingSymlinksInPath(); UserDefaults.standard.set(home.path, forKey: "codexHome"); refreshFileIdentity()
        }
    }
    func importCurrent() {
        run("正在保存当前账号…") {
            let desktop = try self.desktop(); try desktop.preflight()
            guard let data = try desktop.readLive() else { throw AccountsError.message("当前目录没有 auth.json。请先在桌面 App 登录，或检查设置中的认证目录。") }
            try self.importData(data); self.refreshFileIdentity()
            self.status = "当前账号已保存到本机钥匙串。"
        }
    }
    func importFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "导入你自己的 ChatGPT 登录凭据。文件不会复制到项目目录。"
        if panel.runModal() == .OK, let url = panel.url {
            run("正在导入账号…") {
                guard let data = try PrivateFiles.read(url.resolvingSymlinksInPath()) else { throw AccountsError.message("文件不存在。") }
                try self.importData(data); self.status = "账号已保存到本机钥匙串。"
            }
        }
    }
    func addViaLogin(device: Bool = false) {
        run("正在准备浏览器登录…") {
            let desktop = try self.desktop()
            let helper = try self.makeSession(); self.session = helper
            do {
                try await helper.rpc.start(executable: desktop.executable, home: helper.home)
                let result = try await helper.rpc.request("account/login/start", ["type": device ? "chatgptDeviceCode" : "chatgpt"])
                guard let loginID = result["loginId"] as? String,
                      let address = result[device ? "verificationUrl" : "authUrl"] as? String,
                      let url = URL(string: address), url.scheme == "https", url.host == "auth.openai.com" else {
                    throw AccountsError.message("登录未返回受支持的 OpenAI 官方授权地址。")
                }
                self.loginCode = result["userCode"] as? String
                self.status = "请在浏览器完成登录。此操作不会切换桌面 App 的当前账号。"
                NSWorkspace.shared.open(url)
                try await helper.rpc.waitForLogin(loginID)
                guard let data = try PrivateFiles.read(helper.home.appendingPathComponent("auth.json")) else { throw AccountsError.message("登录完成，但没有生成可保存的凭据。") }
                try self.importData(data)
                self.status = "新账号已添加，选择它即可切换。"
                await helper.close(); self.session = nil
            } catch {
                await helper.close(); self.session = nil; throw error
            }
        }
    }
    func cancel() {
        operation?.cancel()
        if let session { Task { await session.rpc.close() } }
    }
    func refresh(_ id: String) {
        run("正在读取额度…") {
            guard let store = self.store else { return }
            let snapshot = try AuthSnapshot(store.snapshot(id))
            let desktop = try self.desktop()
            let helper = try self.makeSession(); self.session = helper
            do {
                try await helper.rpc.start(executable: desktop.executable, home: helper.home)
                // External-token mode does not rotate the stored refresh token in a second process.
                _ = try await helper.rpc.request("account/login/start", ["type": "chatgptAuthTokens", "accessToken": snapshot.accessToken, "chatgptAccountId": snapshot.accountID, "chatgptPlanType": snapshot.plan])
                let result = try await helper.rpc.request("account/rateLimits/read")
                let quotas = QuotaWindow.parse(result)
                guard !quotas.isEmpty else { throw AccountsError.message("服务没有返回可识别的额度窗口，未将未知额度显示为 0。") }
                if let i = store.accounts.firstIndex(where: { $0.id == id }) {
                    store.accounts[i].quotas = quotas; store.accounts[i].updatedAt = Date(); store.accounts[i].issue = nil
                    try store.save(); self.sync()
                }
                self.status = "额度已更新。"
                await helper.close(); self.session = nil
            } catch {
                await helper.close(); self.session = nil
                if let i = store.accounts.firstIndex(where: { $0.id == id }) {
                    store.accounts[i].issue = "刷新失败，显示的是上次结果。凭据过期时请重新登录或导入当前账号。"
                    try? store.save(); self.sync()
                }
                throw error
            }
        }
    }
    func switchTo(_ id: String) {
        guard !demo else { return }
        if let reason = switchBlockReason(id) { error = reason; return }
        run("正在检查切换条件…") {
            guard let store = self.store else { return }
            if self.awaitingConfirmation { throw AccountsError.message("请先核对或恢复上次切换，再进行下一次切换。") }
            let target = try store.snapshot(id)
            let desktop = try self.desktop()
            _ = try await SwitchTransaction.run(target: target, environment: desktop)
            self.awaitingConfirmation = true; self.hasBackup = true
            self.refreshFileIdentity(); self.sync()
            self.status = "认证已更新，桌面 App 已重开。请在 App 中核对账号；当前还未确认桌面登录成功。"
        }
    }
    func restore() {
        run("正在准备恢复…") {
            guard let backup = try self.store?.backup() else { throw AccountsError.message("没有可恢复的备份。") }
            try await SwitchTransaction.restore(backup, environment: self.desktop())
            self.awaitingConfirmation = true
            self.refreshFileIdentity(); self.sync()
            self.status = "原认证已恢复，桌面 App 已重开。请核对账号。"
        }
    }
    func confirmDesktopAccount() {
        guard !demo else { return }
        do {
            try store?.confirmBackup(); awaitingConfirmation = false
            status = "已记录你的核对结果。上一次认证备份仍可恢复。"
        } catch { self.error = safeMessage(error) }
    }
    func rename(_ id: String, nickname: String) {
        guard !demo, let store, let i = store.accounts.firstIndex(where: { $0.id == id }) else { return }
        store.accounts[i].nickname = String(nickname.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        do { try store.save(); sync() } catch { self.error = safeMessage(error) }
    }
    func delete(_ id: String) {
        guard !demo, let store else { return }
        do { try store.delete(id); sync(); selection = accounts.first?.id; status = "已从本工具移除账号，桌面 App 的登录未更改。" }
        catch { self.error = safeMessage(error) }
    }
    private func importData(_ data: Data) throws {
        guard let store else { throw AccountsError.message("本地账号库未就绪。") }
        let account = try store.upsert(data); sync(); selection = account.id
    }
    private func desktop() throws -> Desktop {
        guard let application, let store else { throw AccountsError.message("请先在设置中选择 Codex 桌面 App。") }
        let desktop = Desktop(application: application, home: home, store: store)
        desktop.phase = { [weak self] in self?.status = $0 }
        return desktop
    }
    private func makeSession() throws -> IsolatedSession {
        guard let store else { throw AccountsError.message("本地账号库未就绪。") }
        return try IsolatedSession(root: store.directory.appendingPathComponent("Sessions", isDirectory: true))
    }
    private func sync() { accounts = store?.accounts ?? [] }
    private func refreshFileIdentity() {
        currentIdentity = (try? PrivateFiles.read(home.appendingPathComponent("auth.json"))).flatMap { try? AuthSnapshot($0).identity }
    }
    private func run(_ message: String, body: @escaping () async throws -> Void) {
        guard !busy, !demo else { return }
        busy = true; error = nil; status = message
        operation = Task {
            do { try await body() }
            catch is CancellationError { status = "已取消。" }
            catch { self.error = safeMessage(error); status = "操作未完成。" }
            loginCode = nil; busy = false
            let backup = try? store?.backup()
            hasBackup = backup != nil
            awaitingConfirmation = backup?.isPending ?? false
        }
    }
    private func safeMessage(_ error: Error) -> String {
        if let known = error as? AccountsError { return known.localizedDescription }
        return "本地操作失败，请检查应用设置、文件权限和钥匙串访问。"
    }
    private func loadDemo() {
        // Entirely synthetic UI data. Demo mode never initializes the store, Keychain or RPC.
        func account(_ id: String, _ title: String, _ email: String, _ plan: String, _ short: Double, _ long: Double) -> Account {
            let object: [String: Any] = ["sub": id, "email": email]
            let payload = try! JSONSerialization.data(withJSONObject: object).base64EncodedString()
            let data = try! JSONSerialization.data(withJSONObject: ["tokens": ["account_id": id, "id_token": "demo.\(payload).demo", "access_token": "demo", "refresh_token": "demo"]])
            var account = try! Account(snapshot: AuthSnapshot(data)); account.nickname = title; account.plan = plan
            account.quotas = [.init(id: "short", label: "5 小时", remaining: short, resetsAt: Date().addingTimeInterval(7200)), .init(id: "long", label: "7 天", remaining: long, resetsAt: Date().addingTimeInterval(172800))]
            account.updatedAt = Date(); return account
        }
        accounts = [account("demo-one", "日常工作", "work@example.com", "pro", 84, 62), account("demo-two", "个人探索", "personal@example.com", "plus", 96, 89), account("demo-three", "备用账号", "backup@example.com", "plus", 18, 43)]
        accounts[2].issue = "上次刷新未完成，显示的是缓存额度。"
        accounts[2].updatedAt = Date().addingTimeInterval(-3600)
        selection = accounts[1].id; currentIdentity = accounts[0].id
        status = "演示模式 · 所有账号与额度均为虚构，操作已禁用。"
    }
}
