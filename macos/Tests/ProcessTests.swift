import Foundation
import CryptoKit
import Darwin

@MainActor
private final class ConfigGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func open() { continuation?.resume(); continuation = nil }
}

@MainActor
func runProcessLifecycleTests(check: @escaping (Bool, String) -> Void) async throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appendingPathComponent("PromptFinch-process-tests-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: temporary) }
    let suite = "PromptFinch-process-tests-\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    preferences.set("/bin/sh", forKey: "nodePath")

    func seed(_ name: String) throws -> URL {
        let directory = temporary.appendingPathComponent(name, isDirectory: true)
        var hash = SHA256()
        for relative in BackendStore.files {
            let file = directory.appendingPathComponent(relative)
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = Data("synthetic process fixture \(name) \(relative)".utf8)
            try bytes.write(to: file)
            hash.update(data: Data(relative.utf8)); hash.update(data: Data([0]))
            hash.update(data: bytes); hash.update(data: Data([0]))
        }
        let id = hash.finalize().map { String(format: "%02x", $0) }.joined()
        try Data("\(id)\n".utf8).write(to: directory.appendingPathComponent(".backend-id"))
        return directory
    }
    func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while !condition() && ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        precondition(condition(), "synthetic child did not reach its expected lifecycle state")
    }
    func launchSleep(ignoreTermination: Bool) throws -> Process {
        let child = Process()
        if ignoreTermination {
            child.executableURL = URL(fileURLWithPath: "/bin/sh")
            child.arguments = ["-c", "trap '' TERM; exec /bin/sleep 60"]
        } else {
            child.executableURL = URL(fileURLWithPath: "/bin/sleep")
            child.arguments = ["60"]
        }
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        return child
    }
    let unrelated = try launchSleep(ignoreTermination: false)
    let stubborn = try launchSleep(ignoreTermination: true)
    defer {
        for child in [unrelated, stubborn] where child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
    }
    // Give exec time to install the inherited ignored signal disposition.
    try await Task.sleep(nanoseconds: 80_000_000)
    var actorResponded = false
    let clock = ProcessInfo.processInfo.systemUptime
    let shutdown = Task { try await ProcessLifecycle.stop(stubborn, gracePeriod: 0.15) }
    let pulse = Task { @MainActor in
        try await Task.sleep(nanoseconds: 30_000_000)
        actorResponded = true
    }
    try await pulse.value
    check(actorResponded && stubborn.isRunning, "main actor stays responsive while a child ignores SIGTERM")
    shutdown.cancel()
    try await shutdown.value
    check(!stubborn.isRunning && ProcessInfo.processInfo.systemUptime - clock < 2,
          "cancelled stop caller still reaps a SIGTERM-ignoring child within a bounded interval")
    check(unrelated.isRunning, "forced shutdown never signals another process")
    try await ProcessLifecycle.stop(unrelated, gracePeriod: 0.15)
    check(!unrelated.isRunning, "ordinary SIGTERM child exits without blocking the main actor")

    let firstSeed = try seed("first")
    let nextSeed = try seed("next")
    let storeRoot = temporary.appendingPathComponent("support/backend", isDirectory: true)
    let original = try BackendStore(root: storeRoot, seed: firstSeed).prepare()
    let store = BackendStore(root: storeRoot, seed: nextSeed)
    let nextID = try store.verify(nextSeed).id
    let firstGate = ConfigGate()
    let secondGate = ConfigGate()
    var launches: [Process] = []
    var configCalls = 0
    defer {
        for child in launches where child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
    }
    let backend = LocalBackend(store: store, defaults: preferences, port: 43219, runProcess: { child in
        check(launches.allSatisfy { !$0.isRunning }, "a replacement waits until every previously owned child exits")
        check(child.environment?["HOST"] == "127.0.0.1" && child.environment?["PORT"] == "43219",
              "isolated lifecycle uses the injected loopback port")
        check(child.environment?["OPTIMIZER_MODE"] == "mock", "isolated lifecycle never loads a model configuration")
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", "trap '' TERM; exec /bin/sleep 60"]
        try child.run()
        launches.append(child)
    }, loadConfig: { backendID, instanceID in
        configCalls += 1
        let call = configCalls
        if call == 1 { await firstGate.wait() }
        if call == 2 { await secondGate.wait() }
        return ServiceConfig(service: "prompt-studio", apiVersion: 2, backendID: backendID,
                             backendInstanceID: instanceID, mode: "mock", ready: true,
                             generationModel: nil, promptLanguages: ["en"])
    }, terminationGracePeriod: 0.12)
    check(backend.nodePath == "/bin/sh" && backend.configurationPath.isEmpty,
          "lifecycle preferences come exclusively from an isolated suite")
    let oldStart = Task { try await backend.ensureRunning() }
    try await waitUntil { configCalls == 1 }
    try await backend.stop()
    check(launches.count == 1 && !launches[0].isRunning, "stop cancels startup and confirms owned-child exit")
    let freshStart = Task { try await backend.ensureRunning() }
    try await waitUntil { configCalls == 2 }
    firstGate.open()
    do {
        _ = try await oldStart.value
        check(false, "a cancelled old startup must never report a ready configuration")
    } catch {
        check(error is CancellationError, "stale startup observes lifecycle cancellation after a delayed config reply")
    }
    let coalesced = Task { try await backend.ensureRunning() }
    try await Task.sleep(nanoseconds: 40_000_000)
    check(configCalls == 2 && launches.count == 2,
          "an old startup defer never clears a newer shared startup task")
    secondGate.open()
    let freshConfig = try await freshStart.value
    let sharedConfig = try await coalesced.value
    check(freshConfig.backendInstanceID == sharedConfig.backendInstanceID && freshConfig.backendID == original.id,
          "concurrent ensure calls share exactly one owned backend instance")
    let selected = try await backend.useBundledBackend()
    check(selected.backendID == nextID && launches.count == 3 && !launches[1].isRunning,
          "real lifecycle switches to a validated bundled backend only after old-child exit")
    let stopOne = Task { try await backend.stop() }
    let stopTwo = Task { try await backend.stop() }
    let restart = Task { try await backend.ensureRunning() }
    try await stopOne.value
    try await stopTwo.value
    let restarted = try await restart.value
    check(restarted.backendID == nextID && launches.count == 4 && !launches[2].isRunning,
          "overlapping stop calls and restart serialize cleanup before the next launch")
    try await backend.stop()
    check(launches.allSatisfy { !$0.isRunning }, "isolated lifecycle leaves no live child processes")

    // A shutdown can interrupt health after the filesystem pointer changes.
    // It must restore that pointer before a later lifecycle can adopt it.
    let thirdSeed = try seed("third")
    for externalUpdate in [false, true] {
        let cancellationRoot = temporary.appendingPathComponent("cancel-\(externalUpdate)/backend", isDirectory: true)
        let previousStore = BackendStore(root: cancellationRoot, seed: firstSeed)
        let previous = try previousStore.prepare()
        let cancellationStore = BackendStore(root: cancellationRoot, seed: nextSeed)
        let candidateGate = ConfigGate()
        var candidateHealthPending = false
        let cancellationBackend = LocalBackend(store: cancellationStore, defaults: preferences, port: 43220, runProcess: { child in
            check(launches.allSatisfy { !$0.isRunning }, "cancelled switch cleanup finishes before another lifecycle launches")
            child.executableURL = URL(fileURLWithPath: "/bin/sh")
            child.arguments = ["-c", "trap '' TERM; exec /bin/sleep 60"]
            try child.run()
            launches.append(child)
        }, loadConfig: { backendID, instanceID in
            if backendID == nextID {
                candidateHealthPending = true
                await candidateGate.wait()
            }
            return ServiceConfig(service: "prompt-studio", apiVersion: 2, backendID: backendID,
                                 backendInstanceID: instanceID, mode: "mock", ready: true,
                                 generationModel: nil, promptLanguages: ["en"])
        }, terminationGracePeriod: 0.12)
        _ = try await cancellationBackend.ensureRunning()
        let pendingSelection = Task { try await cancellationBackend.useBundledBackend() }
        try await waitUntil { candidateHealthPending }
        check(try cancellationStore.currentTarget() == "releases/\(nextID)", "candidate is selected while its health check is still pending")
        var expectedTarget = previous.target
        var expectedID = previous.id
        if externalUpdate {
            let externalStore = BackendStore(root: cancellationRoot, seed: thirdSeed)
            let third = try externalStore.stageBundled()
            try externalStore.activate(third.target, replacing: "releases/\(nextID)")
            expectedTarget = third.target
            expectedID = third.id
        }
        try await cancellationBackend.stop()
        check(try cancellationStore.currentTarget() == expectedTarget,
              externalUpdate ? "cancelling a pending switch preserves a concurrent updater's pointer" : "cancelling pending health restores the previous pointer before stop returns")
        let nextLifecycle = try await cancellationBackend.ensureRunning()
        check(nextLifecycle.backendID == expectedID, "the next lifecycle never adopts an unverified cancelled candidate")
        candidateGate.open()
        do {
            _ = try await pendingSelection.value
            check(false, "a cancelled pending selection must not complete successfully")
        } catch {
            check(error is CancellationError, "a cancelled health transaction reports cancellation without restarting an old child")
        }
        check(try cancellationStore.currentTarget() == expectedTarget && launches.last?.isRunning == true,
              "late cancelled health cleanup cannot change the newer lifecycle's pointer or stop its child")
        try await cancellationBackend.stop()
    }
    check(launches.allSatisfy { !$0.isRunning }, "cancellation boundary fixtures leave no live children")
}
