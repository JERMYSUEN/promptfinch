import AppKit
import ApplicationServices
import CryptoKit
import Darwin

// UI flow regressions with fake operations: no model, host text, key events or
// general pasteboard. Delayed callbacks are delivered after user actions.
@MainActor
private final class FakePasteOperations: PasteOperations {
    var outcome = PasteBackOutcome.pasteRequested
    var copySucceeds = true
    var immediateRestore: ClipboardRestoreOutcome?
    var callbacks: [(ClipboardRestoreOutcome) -> Void] = []
    var copies: [String] = []

    func copy(_ text: String) -> Bool { copies.append(text); return copySucceeds }
    func paste(_ text: String, expectedTarget: SelectionCapture?,
               onRestore: @escaping (ClipboardRestoreOutcome) -> Void) -> PasteBackOutcome {
        callbacks.append(onRestore)
        if let immediateRestore { onRestore(immediateRestore) }
        return outcome
    }
}

@MainActor
func checkWorkspacePasteFeedback(check: (Bool, String) -> Void) async {
    let operations = FakePasteOperations()
    let model = WorkspaceModel(pasteOperations: operations)
    let prompt = "Synthetic English prompt: preserve ACME-42."
    func setResult() {
        model.result = PromptResult(prompt: prompt, improvements: ["Synthetic note"], assumptions: [],
                                    mode: "live", generationModel: "fake-provider", promptLanguage: "en")
    }
    defer { model.closeResultPanel() }
    setResult()
    model.original = "合成原文"
    model.pasteBackFromPanel()
    check(model.message == L10n.text(.pasteRequested), "a posted paste is reported as requested, never confirmed written")
    check(model.resultPanel.isVisible, "requested paste displays its review panel")
    check(operations.copies.isEmpty, "requested paste does not do an unnecessary fallback copy")
    operations.callbacks.last?(.restored)
    check(model.message == L10n.text(.pasteRequestedRestored), "restoration is reported only after the callback")
    check(model.result?.prompt == prompt && model.original == "合成原文", "paste feedback never rewrites the original or result")

    model.pasteBackFromPanel()
    operations.callbacks.last?(.skippedNewerCopy)
    check(model.message == L10n.text(.pasteRequestedNewCopy), "newer clipboard content is reported as kept")
    model.pasteBackFromPanel()
    operations.callbacks.last?(.failed)
    check(model.isError && model.message == L10n.text(.pasteRequestedRestoreFailed), "restoration failure has clear error feedback")

    model.pasteBackFromPanel()
    let closedCallback = operations.callbacks.last!
    model.closeResultPanel()
    let closedStatus = model.message
    closedCallback(.restored)
    check(!model.resultPanel.isVisible && model.message == closedStatus, "late restoration never reopens a closed result panel")

    model.pasteBackFromPanel()
    let oldCallback = operations.callbacks.last!
    model.pasteBackFromPanel()
    oldCallback(.failed)
    check(!model.isError && model.message == L10n.text(.pasteRequested), "an older paste cannot overwrite a newer paste's feedback")
    operations.callbacks.last?(.restored)
    check(model.message == L10n.text(.pasteRequestedRestored), "the newest paste still receives restoration feedback")

    model.pasteBackFromPanel()
    let copiedCallback = operations.callbacks.last!
    model.copyFromPanel()
    let copiedStatus = model.message
    copiedCallback(.restored)
    check(model.message == copiedStatus && operations.copies.last == prompt, "deliberate copy supersedes pending restoration feedback")

    model.pasteBackFromPanel()
    let clearedCallback = operations.callbacks.last!
    model.clear()
    clearedCallback(.restored)
    check(model.message.isEmpty && model.result == nil && !model.resultPanel.isVisible,
          "clearing cancels feedback and hides stale generated content")

    setResult()
    operations.outcome = .notAttempted
    operations.immediateRestore = .restored
    model.pasteBackFromPanel()
    check(model.message == L10n.text(.unsafeTargetCopied) && operations.copies.last == prompt,
          "failed event creation recovers the clipboard and offers a manual copy without claiming a paste")
    operations.copySucceeds = false
    model.pasteBackFromPanel()
    check(model.isError && model.message == L10n.text(.unsafePasteFailed), "fallback copy failure is visible")

    operations.outcome = .clipboardUnavailable
    operations.immediateRestore = .failed
    let copyCount = operations.copies.count
    model.pasteBackFromPanel()
    check(operations.copies.count == copyCount, "unsafe clipboard preparation never triggers automatic fallback copying")
    check(model.isError && model.message == L10n.text(.clipboardUnavailable) && model.resultPanel.isVisible,
          "unsafe clipboard preparation keeps the result visible for deliberate manual copying")
    operations.callbacks.last?(.restored)
    check(model.message == L10n.text(.clipboardUnavailable), "unrequested paste recovery cannot claim a paste or replace clipboard error feedback")

    // Even a terminal helper with a valid selected range cannot authorize
    // replacement: pasting there sends text to stdin instead of editing it.
    let terminal = SelectionCapture(text: "合成原文", bounds: nil, pid: 77,
                                    element: AXUIElementCreateApplication(77),
                                    range: SelectionRange(location: 0, length: 4), isTerminal: true)
    model.setSelectionSourceForTesting(terminal)
    operations.copySucceeds = true
    operations.immediateRestore = nil
    let pasteCount = operations.callbacks.count
    model.pasteBackFromPanel()
    check(operations.callbacks.count == pasteCount && operations.copies.last == prompt,
          "terminal result copies only the prompt without asking fake paste operations to run")
    check(model.message == L10n.text(.terminalCopied) && !model.isError && model.resultPanel.isVisible,
          "terminal result keeps review visible and explains manual CLI input")
    check(!model.resultPanel.contentView!.subviews.compactMap { $0 as? NSButton }
        .contains { $0.title == L10n.text(.pasteBack) && !$0.isHidden },
          "terminal review hides paste-back even when the source has a reliable range")
    operations.copySucceeds = false
    model.pasteBackFromPanel()
    check(model.isError && model.message == L10n.text(.copyFailedPanel)
          && operations.callbacks.count == pasteCount,
          "terminal copy failure is visible and never falls through to stdin paste")

    do { try await checkWorkspaceBackendState(check: check) }
    catch { check(false, "isolated workspace backend fixture failed: \(error.localizedDescription)") }
}

// Exercise the actual WorkspaceModel and LocalBackend together. Only owned
// sleep children, synthetic health replies and temporary preferences are used;
// no model, HTTP request, installed app or real configuration file is involved.
@MainActor
private func checkWorkspaceBackendState(check: (Bool, String) -> Void) async throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appendingPathComponent("PromptFinch-workspace-tests-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: temporary) }
    let suite = "PromptFinch-workspace-tests-\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    preferences.set("/bin/sh", forKey: "nodePath")

    func seed(_ name: String) throws -> URL {
        let directory = temporary.appendingPathComponent(name, isDirectory: true)
        var hash = SHA256()
        for relative in BackendStore.files {
            let file = directory.appendingPathComponent(relative)
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let bytes = Data("synthetic workspace fixture \(name) \(relative)".utf8)
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
        guard condition() else { throw ToolError.message("Synthetic workspace operation did not finish") }
    }

    let firstSeed = try seed("first")
    let nextSeed = try seed("next")
    let storeRoot = temporary.appendingPathComponent("support/backend", isDirectory: true)
    let previous = try BackendStore(root: storeRoot, seed: firstSeed).prepare()
    let store = BackendStore(root: storeRoot, seed: nextSeed)
    let candidate = try store.verify(nextSeed)
    var children: [Process] = []
    var failLaunch = false
    var failHealth = false
    var failCandidateHealth = false
    var holdNextHealth = false
    var pendingHealth: (continuation: CheckedContinuation<ServiceConfig, Error>, reply: ServiceConfig)?
    defer {
        pendingHealth?.continuation.resume(throwing: CancellationError())
        for child in children where child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
    }
    let backend = LocalBackend(store: store, defaults: preferences, port: 43221, runProcess: { child in
        if failLaunch { throw ToolError.message("Synthetic launch failure") }
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["60"]
        try child.run()
        children.append(child)
    }, loadConfig: { backendID, instanceID in
        if failHealth || (failCandidateHealth && backendID == candidate.id) {
            throw ToolError.message("Synthetic health failure")
        }
        let reply = ServiceConfig(service: "prompt-studio", apiVersion: 2, backendID: backendID,
                                  backendInstanceID: instanceID, mode: "live", ready: true,
                                  generationModel: "synthetic-\(backendID.prefix(8))", promptLanguages: ["en"])
        if holdNextHealth {
            holdNextHealth = false
            return try await withCheckedThrowingContinuation { continuation in
                pendingHealth = (continuation, reply)
            }
        }
        return reply
    }, terminationGracePeriod: 0.12)
    let model = WorkspaceModel(pasteOperations: FakePasteOperations(), backend: backend, preferences: preferences)
    defer { model.clear() }

    model.refresh()
    try await waitUntil { model.config != nil }
    let firstInstance = model.config?.backendInstanceID
    check(model.config?.ready == true && model.config?.backendID == previous.id,
          "workspace initially displays only the health-verified backend")

    model.useConfig(temporary.appendingPathComponent("missing.env"))
    check(model.config == nil && model.backendSwitching,
          "selecting another configuration immediately removes the previous ready badge")
    try await waitUntil { !model.backendSwitching }
    check(model.isError && model.config == nil && backend.verifiedConfiguration == nil,
          "an unreadable configuration cannot retain a stopped backend's ready status")
    check(children.allSatisfy { !$0.isRunning } && !model.modeLabel.contains("synthetic-"),
          "failed configuration selection leaves no child or stale model name")

    model.useConfig(nil)
    try await waitUntil { !model.backendSwitching }
    check(!model.isError && model.config?.ready == true && model.config?.backendInstanceID != firstInstance,
          "choosing a valid configuration restores readiness only after a fresh health check")

    failLaunch = true
    model.restart()
    check(model.config == nil, "restart hides readiness while the old child is being replaced")
    try await waitUntil { !model.backendSwitching }
    check(model.isError && model.config == nil && children.allSatisfy { !$0.isRunning },
          "restart failure cannot show the terminated child as ready")
    failLaunch = false
    model.restart()
    try await waitUntil { !model.backendSwitching }
    check(!model.isError && model.config?.ready == true,
          "a successful retry recovers from restart failure")

    failHealth = true
    model.refresh()
    check(model.config == nil, "refresh removes previously verified readiness while checking current health")
    try await waitUntil { model.isError }
    check(model.config == nil && backend.verifiedConfiguration == nil,
          "a failed refresh cannot display an old successful health check")
    failHealth = false
    model.refresh()
    try await waitUntil { model.config != nil }
    check(model.config?.ready == true && !model.isError,
          "refresh can recover readiness and clear its earlier error after the backend becomes healthy")

    failHealth = true
    model.original = "Synthetic request: preserve ACME-42."
    model.generate()
    check(model.config == nil && model.busy, "generation rechecks readiness before dispatching content")
    try await waitUntil { !model.busy }
    check(model.isError && model.config == nil && model.result == nil,
          "generation startup failure leaves no stale readiness or fabricated output")
    failHealth = false
    model.refresh()
    try await waitUntil { model.config != nil }

    // A generation cancellation does not cancel the shared backend health task.
    // Release health replies explicitly, then await the captured generation task
    // so these checks cannot pass before its success/error handler has run.
    for clearSelection in [false, true] {
        for healthSucceeds in [true, false] {
            holdNextHealth = true
            model.original = "Synthetic cancellable request: preserve ACME-42."
            model.generate()
            let generation = model.generationOperationForTesting!
            try await waitUntil { pendingHealth != nil }
            check(model.busy && model.config == nil,
                  "pending generation health hides the old readiness before cancellation")
            if clearSelection { model.clear() }
            else { model.cancel(); model.notify(L10n.text(.cancelled)) }
            let status = model.message
            let health = pendingHealth!
            pendingHealth = nil
            if healthSucceeds { health.continuation.resume(returning: health.reply) }
            else { health.continuation.resume(throwing: ToolError.message("Synthetic delayed health failure")) }
            await generation.value
            if healthSucceeds {
                check(model.config?.ready == true && model.config?.backendInstanceID == backend.verifiedConfiguration?.backendInstanceID,
                      "\(clearSelection ? "clear" : "cancel") still publishes a successful current backend health check")
            } else {
                check(model.config == nil && backend.verifiedConfiguration == nil,
                      "\(clearSelection ? "clear" : "cancel") cannot restore readiness after a failed current health check")
            }
            check(!model.busy && model.result == nil && model.message == status && !model.resultPanel.isVisible,
                  "late health completion preserves cancellation feedback and never dispatches or reopens generated content")
            if clearSelection { check(model.original.isEmpty, "late health completion preserves a cleared input") }
            if !healthSucceeds {
                model.refresh()
                try await waitUntil { model.config != nil }
                check(model.config?.ready == true && !model.isError,
                      "cancelled generation health failure recovers through a subsequent explicit health check")
            }
        }
    }

    for healthSucceeds in [true, false] {
        holdNextHealth = true
        model.original = "Synthetic superseded request: preserve ACME-42."
        model.generate()
        let generation = model.generationOperationForTesting!
        try await waitUntil { pendingHealth != nil }
        let oldHealth = pendingHealth!
        pendingHealth = nil
        model.restart()
        try await waitUntil { !model.backendSwitching }
        let currentInstance = model.config?.backendInstanceID
        let status = model.message
        check(model.config?.ready == true && currentInstance != oldHealth.reply.backendInstanceID,
              "a newer backend switch verifies a different child while the old health reply is held")
        if healthSucceeds { oldHealth.continuation.resume(returning: oldHealth.reply) }
        else { oldHealth.continuation.resume(throwing: ToolError.message("Synthetic superseded health failure")) }
        await generation.value
        check(model.config?.ready == true && model.config?.backendInstanceID == currentInstance
              && backend.verifiedConfiguration?.backendInstanceID == currentInstance && model.message == status,
              "an old \(healthSucceeds ? "successful" : "failed") health reply cannot overwrite a newer backend switch")
        check(model.result == nil && !model.busy && !model.isError,
              "a superseded generation cannot publish output or errors after the backend switch")
    }

    failCandidateHealth = true
    let beforeRollback = model.config?.backendInstanceID
    model.useBundledBackend()
    check(model.config == nil, "bundled selection hides readiness until its transaction finishes")
    try await waitUntil { !model.backendSwitching }
    check(model.isError && model.config?.backendID == previous.id && model.config?.ready == true,
          "failed bundled startup may display the previous backend only after verified rollback")
    check(model.config?.backendInstanceID != beforeRollback
          && model.config?.backendInstanceID == backend.verifiedConfiguration?.backendInstanceID,
          "rollback readiness comes from the restored child's new health reply, never a cached UI value")
    check(try store.currentTarget() == previous.target,
          "workspace error feedback does not change a successfully restored backend selection")

    failCandidateHealth = false
    model.useBundledBackend()
    try await waitUntil { !model.backendSwitching }
    check(!model.isError && model.config?.backendID == candidate.id,
          "retrying bundled selection displays the newly verified candidate")

    failHealth = true
    model.useBundledBackend()
    try await waitUntil { !model.backendSwitching }
    check(model.isError && model.config == nil && backend.verifiedConfiguration == nil,
          "a failed candidate and failed rollback cannot retain either backend's ready status")
    failHealth = false
    model.restart()
    try await waitUntil { !model.backendSwitching }
    check(!model.isError && model.config?.backendID == candidate.id && model.config?.ready == true,
          "a failed rollback can recover only through another successful startup and health check")
    try await backend.stop()
    check(children.allSatisfy { !$0.isRunning }, "workspace backend fixtures leave no owned child running")
}
