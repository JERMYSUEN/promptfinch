import AppKit
import CryptoKit

@MainActor
final class LocalBackend {
    let client = PromptClient()
    private var process: Process?
    private var backendInstanceID: String?
    private var starting: Task<ServiceConfig, Error>?
    private let defaults = UserDefaults.standard
    private let backendFiles = [
        "server.js", "lib/optimizer.js", "public/index.html", "public/app.js", "public/style.css", "public/favicon.svg",
    ]

    var configurationPath: String { defaults.string(forKey: "configurationPath") ?? "" }
    var nodePath: String { defaults.string(forKey: "nodePath") ?? "" }

    private var supportBackend: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PromptSelection", isDirectory: true)
            .appendingPathComponent("backend", isDirectory: true)
    }

    func selectConfiguration(_ url: URL?) async throws -> ServiceConfig {
        if let url { defaults.set(url.path, forKey: "configurationPath") }
        else { defaults.removeObject(forKey: "configurationPath") }
        stop()
        return try await ensureRunning()
    }

    func setNode(_ url: URL) {
        defaults.set(url.path, forKey: "nodePath")
    }

    func ensureRunning() async throws -> ServiceConfig {
        if let starting { return try await starting.value }
        let task = Task { @MainActor in try await self.launchOrConnect() }
        starting = task
        defer { starting = nil }
        return try await task.value
    }

    private func launchOrConnect() async throws -> ServiceConfig {
        if process?.isRunning == true {
            let active = try prepareBackend()
            guard let backendInstanceID else {
                throw ToolError.message("無法確認目前後端由此 App 啟動；請重新啟動助手。")
            }
            return try await client.config(expectedBackendID: active.id, expectedInstanceID: backendInstanceID)
        }
        process = nil
        backendInstanceID = nil
        try Task.checkCancellation()
        let active = try prepareBackend()
        let instanceID = try launch(backend: active.root, backendID: active.id)
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 150_000_000)
            guard process?.isRunning == true else {
                process = nil
                backendInstanceID = nil
                throw ToolError.message("本機後端未能啟動。請確認 Node.js 22 以上、設定檔格式正確，且 3210 埠未被其他程式佔用。")
            }
            do { return try await client.config(expectedBackendID: active.id, expectedInstanceID: instanceID) }
            catch let error as ToolError { throw error }
            catch {
                if process?.isRunning != true {
                    process = nil
                    throw ToolError.message("本機後端未能啟動。請確認 Node.js 22 以上、設定檔格式正確，且 3210 埠未被其他程式佔用。")
                }
            }
        }
        throw ToolError.message("本機後端啟動逾時，請重新啟動工具。")
    }

    private func prepareBackend() throws -> (root: URL, id: String) {
        let manager = FileManager.default
        let backendRoot = supportBackend
        try manager.createDirectory(at: backendRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let current = backendRoot.appendingPathComponent("current")
        let linkTarget = try? manager.destinationOfSymbolicLink(atPath: current.path)
        if manager.fileExists(atPath: current.path) || linkTarget != nil {
            guard let target = linkTarget else {
                throw ToolError.message("外部後端 current 路徑不是本工具管理的版本連結；為保護檔案，沒有覆蓋它。")
            }
            guard target.range(of: #"^releases/[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
                throw ToolError.message("外部後端版本連結格式不正確，未啟動未知程式碼。")
            }
            let root = backendRoot.appendingPathComponent(target, isDirectory: true).standardizedFileURL
            return try verifyBackend(root)
        }

        // First launch seeds a private, replaceable support-directory copy from
        // the signed bundle. Future backend-only updates never rewrite the app.
        guard let resources = Bundle.main.resourceURL else { throw ToolError.message("應用程式套件不完整，請重新安裝。") }
        let seed = resources.appendingPathComponent("backend", isDirectory: true)
        let bundled = try verifyBackend(seed)
        let releases = backendRoot.appendingPathComponent("releases", isDirectory: true)
        try manager.createDirectory(at: releases, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let release = releases.appendingPathComponent(bundled.id, isDirectory: true)
        if !manager.fileExists(atPath: release.path) {
            try manager.copyItem(at: seed, to: release)
        }
        let external = try verifyBackend(release)
        guard external.id == bundled.id else { throw ToolError.message("初次安裝後端版本核對失敗。") }
        let temporary = backendRoot.appendingPathComponent(".current-\(UUID().uuidString)")
        try manager.createSymbolicLink(atPath: temporary.path, withDestinationPath: "releases/\(external.id)")
        try manager.moveItem(at: temporary, to: current)
        return external
    }

    private func verifyBackend(_ root: URL) throws -> (root: URL, id: String) {
        let manifestURL = root.appendingPathComponent(".backend-id")
        guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw ToolError.message("後端版本標記遺失，請重新建置或更新後端。")
        }
        let expected = manifest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expected.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw ToolError.message("後端版本標記格式不正確。")
        }
        var hash = SHA256()
        for relative in backendFiles {
            let url = root.appendingPathComponent(relative)
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: url) else {
                throw ToolError.message("後端檔案不完整或包含未知連結：\(relative)。")
            }
            hash.update(data: Data(relative.utf8))
            hash.update(data: Data([0]))
            hash.update(data: data)
            hash.update(data: Data([0]))
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw ToolError.message("外部後端內容與版本識別不符，請重新執行安全更新。") }
        return (root, actual)
    }

    private func launch(backend: URL, backendID: String) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [nodePath, "\(home)/.local/bin/node", "/opt/homebrew/bin/node", "/usr/local/bin/node"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/node" }
        guard let node = candidates.first(where: { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ToolError.message("找不到 Node.js。請安裝 Node.js 22 以上，或在設定中指定執行檔。")
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: node)
        let instanceID = UUID().uuidString
        var arguments: [String] = []
        if !configurationPath.isEmpty {
            guard FileManager.default.isReadableFile(atPath: configurationPath) else {
                throw ToolError.message("找不到所選 .env 設定檔，請在設定中重新選擇。")
            }
            arguments.append("--env-file=\(configurationPath)")
        }
        arguments.append(backend.appendingPathComponent("server.js").path)
        child.arguments = arguments
        child.currentDirectoryURL = backend
        // Only the server reads the key. No secret is bundled or sent to the UI.
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("LLM_") || key == "OPTIMIZER_MODE" || key == "PROMPT_STUDIO_BACKEND_ID" {
            environment.removeValue(forKey: key)
        }
        environment.removeValue(forKey: "PROMPT_STUDIO_BACKEND_INSTANCE")
        environment["HOST"] = "127.0.0.1"
        environment["PORT"] = "3210"
        environment["PROMPT_STUDIO_BACKEND_ID"] = backendID
        environment["PROMPT_STUDIO_BACKEND_INSTANCE"] = instanceID
        if configurationPath.isEmpty { environment["OPTIMIZER_MODE"] = "mock" }
        child.environment = environment
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do { try child.run() }
        catch { throw ToolError.message("本機後端無法啟動，請確認指定的 Node.js 執行檔有效。") }
        process = child
        backendInstanceID = instanceID
        return instanceID
    }

    func stop() {
        starting?.cancel()
        starting = nil
        guard let child = process else { return }
        // Terminate only the child started by this application.
        if child.isRunning { child.terminate(); child.waitUntilExit() }
        process = nil
        backendInstanceID = nil
    }
}
