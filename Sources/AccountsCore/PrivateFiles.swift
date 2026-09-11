import Foundation
import Darwin

public enum PrivateFiles {
    public static func canonicalDirectory(_ url: URL) throws -> URL {
        guard let path = realpath(url.path, nil) else {
            throw AccountsError.message("无法定位实际目录。")
        }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }

    public static func rejectSymlinks(_ url: URL) throws {
        // Resolve the user's home before calling this. Never follow symlinks inside it.
        var cursor = url.path
        while cursor != "/" {
            var info = stat()
            if lstat(cursor, &info) == 0, (info.st_mode & S_IFMT) == S_IFLNK {
                throw AccountsError.message("认证路径包含符号链接，已停止操作。请使用实际目录。")
            }
            cursor = (cursor as NSString).deletingLastPathComponent
        }
    }

    public static func makeDirectory(_ url: URL) throws {
        try rejectSymlinks(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }

    public static func read(_ url: URL, maximumBytes: Int = 1_048_576) throws -> Data? {
        try rejectSymlinks(url)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd == -1 {
            if errno == ENOENT { return nil }
            throw AccountsError.message("无法读取本地文件，请检查文件权限。")
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_size <= maximumBytes else {
            throw AccountsError.message("文件类型或大小异常，已停止读取。")
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        return try handle.readToEnd() ?? Data()
    }

    public static func write(_ data: Data, to url: URL) throws {
        try makeDirectory(url.deletingLastPathComponent())
        try rejectSymlinks(url)
        let temp = url.deletingLastPathComponent().appendingPathComponent(".accounts-write-\(UUID().uuidString)")
        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw AccountsError.message("无法创建私有临时文件。") }
        defer { close(fd); try? FileManager.default.removeItem(at: temp) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        guard fsync(fd) == 0 else { throw AccountsError.message("文件同步失败，原认证未替换。") }
        guard rename(temp.path, url.path) == 0 else { throw AccountsError.message("原子替换失败，原认证未替换。") }
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY)
        if directory >= 0 { _ = fsync(directory); close(directory) }
    }

    public static func remove(_ url: URL) throws {
        try rejectSymlinks(url)
        if unlink(url.path) != 0 && errno != ENOENT { throw AccountsError.message("无法删除本地文件。") }
    }
}

public final class ExclusiveLock {
    private var fd: Int32 = -1
    public init(at url: URL) throws {
        try PrivateFiles.makeDirectory(url.deletingLastPathComponent())
        try PrivateFiles.rejectSymlinks(url)
        fd = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw AccountsError.message("无法创建操作锁。") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd); fd = -1
            throw AccountsError.message("另一个 Codex Accounts 正在运行。")
        }
    }
    deinit { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
}

public enum StoragePolicy {
    /// Conservative guard; full TOML evaluation remains Codex's responsibility.
    public static func validate(config: String) throws {
        let lines = config.components(separatedBy: .newlines)
        var root = true
        var declarations = 0
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") || line.isEmpty { continue }
            if line.hasPrefix("[") { root = false }
            if line.contains("cli_auth_credentials_store") {
                let pattern = #"^\s*(?:cli_auth_credentials_store|"cli_auth_credentials_store"|'cli_auth_credentials_store')\s*=\s*(?:"file"|'file')\s*(?:#.*)?$"#
                guard root, line.range(of: pattern, options: .regularExpression) != nil else {
                    throw AccountsError.message("第一版只支持文件认证。当前认证存储配置不是明确的 file，或无法安全识别。")
                }
                declarations += 1
            }
        }
        if declarations > 1 { throw AccountsError.message("认证存储配置重复，已停止切换。") }
    }
}
