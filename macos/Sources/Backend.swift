import AppKit
import CryptoKit
import Darwin

struct BackendRelease {
    let root: URL
    let id: String
    var target: String { "releases/\(id)" }
}

/// The backend store never decides which hash is newer. Existing selections are
/// retained until an explicit bundled-backend action selects another release.
@MainActor
struct BackendStore {
    static let files = [
        "server.js", "lib/optimizer.js", "public/index.html", "public/app.js", "public/style.css", "public/favicon.svg",
    ]
    let root: URL
    let seed: URL
    private let manager = FileManager.default
    private let replaceLink: (URL, URL) throws -> Void

    init(root: URL, seed: URL, replaceLink: ((URL, URL) throws -> Void)? = nil) {
        self.root = root
        self.seed = seed
        self.replaceLink = replaceLink ?? { temporary, current in
            guard Darwin.rename(temporary.path, current.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        }
    }

    func currentTarget() throws -> String? {
        let current = root.appendingPathComponent("current")
        let target = try? manager.destinationOfSymbolicLink(atPath: current.path)
        guard manager.fileExists(atPath: current.path) || target != nil else { return nil }
        guard let target else { throw ToolError.message(L10n.text(.unmanagedBackend)) }
        guard target.range(of: #"^releases/[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw ToolError.message(L10n.text(.invalidBackendLink))
        }
        return target
    }

    func prepare() throws -> BackendRelease {
        try ensureDirectories()
        if let target = try currentTarget() {
            let active = try verify(root.appendingPathComponent(target))
            guard active.target == target else { throw ToolError.message(L10n.text(.seedMismatch)) }
            return active
        }
        let bundled = try stageBundled()
        try activate(bundled.target, replacing: nil)
        return bundled
    }

    func stageBundled() throws -> BackendRelease {
        try ensureDirectories()
        let bundled = try verify(seed)
        let release = root.appendingPathComponent(bundled.target, isDirectory: true)
        if manager.fileExists(atPath: release.path) || (try? manager.destinationOfSymbolicLink(atPath: release.path)) != nil {
            let existing = try verify(release)
            guard existing.id == bundled.id else { throw ToolError.message(L10n.text(.seedMismatch)) }
            return existing
        }
        let temporary = root.appendingPathComponent("releases/.staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: temporary) }
        try manager.copyItem(at: seed, to: temporary)
        let staged = try verify(temporary)
        guard staged.id == bundled.id else { throw ToolError.message(L10n.text(.seedMismatch)) }
        try manager.moveItem(at: temporary, to: release)
        return try verify(release)
    }

    /// Compare the current target again before replacing it, so a concurrent
    /// external updater is never silently overwritten during rollback.
    func activate(_ target: String?, replacing expected: String?) throws {
        guard try currentTarget() == expected else { throw ToolError.message(L10n.text(.invalidBackendLink)) }
        let current = root.appendingPathComponent("current")
        guard let target else {
            if expected != nil { try manager.removeItem(at: current) }
            return
        }
        guard target.range(of: #"^releases/[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw ToolError.message(L10n.text(.invalidBackendLink))
        }
        let release = try verify(root.appendingPathComponent(target, isDirectory: true))
        guard release.target == target else { throw ToolError.message(L10n.text(.seedMismatch)) }
        let temporary = root.appendingPathComponent(".current-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: temporary) }
        try manager.createSymbolicLink(atPath: temporary.path, withDestinationPath: target)
        try replaceLink(temporary, current)
    }

    /// All process work is supplied by the caller. Tests use temporary roots and
    /// simulated health checks, exercising this same switch/rollback transaction.
    func useBundled<T>(beforeActivation: () async throws -> Void,
                       validate: (BackendRelease) async throws -> T,
                       beforeRollback: () async throws -> Void,
                       restore: (BackendRelease?) async throws -> Void,
                       didActivate: (BackendRelease, String?) -> Void = { _, _ in }) async throws -> T {
        let previous = try currentTarget()
        let candidate = try stageBundled()
        try Task.checkCancellation()
        try await beforeActivation()
        try Task.checkCancellation()
        do {
            try activate(candidate.target, replacing: previous)
            didActivate(candidate, previous)
            return try await validate(candidate)
        } catch {
            let original = error
            do {
                try await beforeRollback()
                try Task.checkCancellation()
                let active = try currentTarget()
                if active == candidate.target { try activate(previous, replacing: candidate.target) }
                else if active != previous { throw ToolError.message(L10n.text(.invalidBackendLink)) }
                let prior = try previous.map { try verify(root.appendingPathComponent($0, isDirectory: true)) }
                try await restore(prior)
            } catch is CancellationError {
                // A newer lifecycle action owns the process now; do not stop it.
                throw CancellationError()
            } catch {
                let reason = "\(L10n.errorDescription(original)); \(L10n.errorDescription(error))"
                throw ToolError.message(L10n.text(.backendSwitchRollbackFailed, reason))
            }
            throw ToolError.message(L10n.text(.backendSwitchRolledBack, L10n.errorDescription(original)))
        }
    }

    func verify(_ directory: URL) throws -> BackendRelease {
        try requireDirectory(directory)
        let manifestURL = directory.appendingPathComponent(".backend-id")
        guard isRegularFile(manifestURL), let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw ToolError.message(L10n.text(.missingBackendID))
        }
        let expected = manifest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expected.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else {
            throw ToolError.message(L10n.text(.invalidBackendID))
        }
        for name in ["lib", "public"] { try requireDirectory(directory.appendingPathComponent(name)) }
        var hash = SHA256()
        for relative in Self.files {
            let url = directory.appendingPathComponent(relative)
            guard isRegularFile(url), let data = try? Data(contentsOf: url) else {
                throw ToolError.message(L10n.text(.invalidBackendFile, relative))
            }
            hash.update(data: Data(relative.utf8))
            hash.update(data: Data([0]))
            hash.update(data: data)
            hash.update(data: Data([0]))
        }
        let actual = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw ToolError.message(L10n.text(.backendHashMismatch)) }
        return BackendRelease(root: directory, id: actual)
    }

    private func ensureDirectories() throws {
        for directory in [root, root.appendingPathComponent("releases", isDirectory: true)] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try requireDirectory(directory)
        }
    }

    private func requireDirectory(_ directory: URL) throws {
        guard let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else {
            throw ToolError.message(L10n.text(.invalidBackendLink))
        }
    }

    private func isRegularFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
}

/// Only accepts the Process object created by this app. Waiting yields the main
/// actor, and cancellation of a caller never cancels an in-flight cleanup.
@MainActor
enum ProcessLifecycle {
    static func stop(_ child: Process, gracePeriod: TimeInterval = 1,
                     killGracePeriod: TimeInterval = 1) async throws {
        let cleanup = Task { @MainActor in
            guard child.isRunning else { return }
            child.terminate()
            if await waitForExit(child, timeout: gracePeriod) { return }
            // Do not signal a port owner, process name, or process group.
            if child.isRunning {
                let outcome = Darwin.kill(child.processIdentifier, SIGKILL)
                if outcome != 0 && errno != ESRCH {
                    throw ToolError.message(L10n.text(.backendStopFailed))
                }
            }
            guard await waitForExit(child, timeout: killGracePeriod) else {
                throw ToolError.message(L10n.text(.backendStopFailed))
            }
        }
        try await cleanup.value
    }

    private static func waitForExit(_ child: Process, timeout: TimeInterval) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, timeout)
        while child.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return !child.isRunning
    }
}

@MainActor
final class LocalBackend {
    let client: PromptClient
    private var process: Process?
    private var backendInstanceID: String?
    private var starting: Task<ServiceConfig, Error>?
    private var startingID: UUID?
    private var switching: Task<ServiceConfig, Error>?
    private var switchingID: UUID?
    private var lifecycleID = UUID()
    private let defaults: UserDefaults
    private let store: BackendStore
    private let port: Int
    private let runProcess: (Process) throws -> Void
    private let loadConfig: (String, String) async throws -> ServiceConfig
    private let terminationGracePeriod: TimeInterval
    private var stopping: Task<Void, Error>?
    private var stoppingID: UUID?
    private var pendingSwitch: (id: UUID, previous: String?, candidate: String)?

    init(store: BackendStore? = nil, defaults: UserDefaults = .standard, port: Int = 3210,
         client: PromptClient? = nil, runProcess: ((Process) throws -> Void)? = nil,
         loadConfig: ((String, String) async throws -> ServiceConfig)? = nil,
         terminationGracePeriod: TimeInterval = 1) {
        precondition((1...65535).contains(port))
        self.defaults = defaults
        self.port = port
        let client = client ?? PromptClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        self.client = client
        self.runProcess = runProcess ?? { try $0.run() }
        self.loadConfig = loadConfig ?? { backendID, instanceID in
            try await client.config(expectedBackendID: backendID, expectedInstanceID: instanceID)
        }
        self.terminationGracePeriod = terminationGracePeriod
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PromptSelection/backend", isDirectory: true)
        let resources = Bundle.main.resourceURL ?? Bundle.main.bundleURL
        self.store = store ?? BackendStore(root: support, seed: resources.appendingPathComponent("backend", isDirectory: true))
    }

    var configurationPath: String { defaults.string(forKey: "configurationPath") ?? "" }
    var nodePath: String { defaults.string(forKey: "nodePath") ?? "" }

    func selectConfiguration(_ url: URL?) async throws -> ServiceConfig {
        if let url { defaults.set(url.path, forKey: "configurationPath") }
        else { defaults.removeObject(forKey: "configurationPath") }
        try await stop()
        return try await ensureRunning()
    }

    func setNode(_ url: URL) { defaults.set(url.path, forKey: "nodePath") }

    func ensureRunning() async throws -> ServiceConfig {
        if let switching { return try await switching.value }
        return try await ensureBackendRunning()
    }

    func useBundledBackend() async throws -> ServiceConfig {
        if let switching { return try await switching.value }
        let id = UUID()
        let lifecycle = lifecycleID
        let task = Task { @MainActor in
            try await self.store.useBundled(beforeActivation: {
                guard self.lifecycleID == lifecycle else { throw CancellationError() }
                try await self.stopProcess()
            }, validate: { candidate in
                let config = try await self.ensureBackendRunning()
                guard config.backendID == candidate.id else { throw ToolError.message(L10n.text(.backendHashMismatch)) }
                try Task.checkCancellation()
                // Once this health check succeeds, the selection is committed.
                if self.pendingSwitch?.id == id { self.pendingSwitch = nil }
                return config
            }, beforeRollback: {
                guard self.lifecycleID == lifecycle else { throw CancellationError() }
                try await self.stopProcess()
            }, restore: { previous in
                if previous != nil { _ = try await self.ensureBackendRunning() }
            }, didActivate: { candidate, previous in
                self.pendingSwitch = (id, previous, candidate.target)
            })
        }
        switchingID = id
        switching = task
        defer {
            if switchingID == id { switching = nil; switchingID = nil }
            if pendingSwitch?.id == id { pendingSwitch = nil }
        }
        return try await task.value
    }

    private func ensureBackendRunning() async throws -> ServiceConfig {
        if let starting { return try await starting.value }
        let id = UUID()
        let lifecycle = lifecycleID
        let task = Task { @MainActor in
            if let stopping = self.stopping { try await stopping.value }
            try Task.checkCancellation()
            guard self.lifecycleID == lifecycle else { throw CancellationError() }
            return try await self.launchOrConnect(lifecycle: lifecycle)
        }
        startingID = id
        starting = task
        defer {
            if startingID == id { starting = nil; startingID = nil }
        }
        return try await task.value
    }

    private func launchOrConnect(lifecycle: UUID) async throws -> ServiceConfig {
        try Task.checkCancellation()
        if process?.isRunning == true {
            let active = try store.prepare()
            guard let backendInstanceID else { throw ToolError.message(L10n.text(.unknownBackend)) }
            let config = try await loadConfig(active.id, backendInstanceID)
            try Task.checkCancellation()
            guard lifecycleID == lifecycle else { throw CancellationError() }
            return config
        }
        process = nil
        backendInstanceID = nil
        let active = try store.prepare()
        let instanceID = try launch(backend: active.root, backendID: active.id)
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 150_000_000)
            guard backendInstanceID == instanceID, lifecycleID == lifecycle else { throw CancellationError() }
            guard process?.isRunning == true else {
                process = nil
                backendInstanceID = nil
                throw ToolError.message(L10n.text(.backendStartFailed))
            }
            do {
                let config = try await loadConfig(active.id, instanceID)
                try Task.checkCancellation()
                guard backendInstanceID == instanceID, lifecycleID == lifecycle else { throw CancellationError() }
                return config
            } catch let error as ToolError { throw error }
            catch {
                try Task.checkCancellation()
                guard backendInstanceID == instanceID, lifecycleID == lifecycle else { throw CancellationError() }
                if process?.isRunning != true {
                    process = nil
                    backendInstanceID = nil
                    throw ToolError.message(L10n.text(.backendStartFailed))
                }
            }
        }
        throw ToolError.message(L10n.text(.backendStartTimeout))
    }

    private func launch(backend: URL, backendID: String) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [nodePath, "\(home)/.local/bin/node", "/opt/homebrew/bin/node", "/usr/local/bin/node"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/node" }
        guard let node = candidates.first(where: { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ToolError.message(L10n.text(.missingNode))
        }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: node)
        let instanceID = UUID().uuidString
        var arguments: [String] = []
        if !configurationPath.isEmpty {
            guard FileManager.default.isReadableFile(atPath: configurationPath) else {
                throw ToolError.message(L10n.text(.missingEnv))
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
        environment["PORT"] = String(port)
        // Desktop requests always stay on the loopback host allowlist.
        environment["ALLOWED_HOSTS"] = ""
        environment["PROMPT_STUDIO_BACKEND_ID"] = backendID
        environment["PROMPT_STUDIO_BACKEND_INSTANCE"] = instanceID
        if configurationPath.isEmpty { environment["OPTIMIZER_MODE"] = "mock" }
        child.environment = environment
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        do { try runProcess(child) }
        catch { throw ToolError.message(L10n.text(.invalidNode)) }
        process = child
        backendInstanceID = instanceID
        return instanceID
    }

    func stop() async throws {
        lifecycleID = UUID()
        switching?.cancel()
        switching = nil
        switchingID = nil
        // Restore an unverified selection before the first suspension. A newer
        // lifecycle cannot launch from it while the old health request unwinds.
        // A separate updater's choice is preserved by comparing the exact link.
        var rollbackFailure: Error?
        if let pending = pendingSwitch {
            pendingSwitch = nil
            do {
                if try store.currentTarget() == pending.candidate {
                    try store.activate(pending.previous, replacing: pending.candidate)
                }
            } catch {
                rollbackFailure = ToolError.message(L10n.text(.backendSwitchRollbackFailed, L10n.errorDescription(error)))
            }
        }
        try await stopProcess()
        if let rollbackFailure { throw rollbackFailure }
    }

    private func stopProcess() async throws {
        starting?.cancel()
        starting = nil
        startingID = nil
        if let stopping { return try await stopping.value }
        guard let child = process else { return }
        let id = UUID()
        let task = Task { @MainActor in
            try await ProcessLifecycle.stop(child, gracePeriod: self.terminationGracePeriod)
            // This reference stays owned until exit is observed. A failed stop
            // prevents launch of a second child on the same port.
            if self.process === child {
                self.process = nil
                self.backendInstanceID = nil
            }
        }
        stopping = task
        stoppingID = id
        defer {
            if stoppingID == id { stopping = nil; stoppingID = nil }
        }
        try await task.value
    }
}
