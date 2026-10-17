import Foundation
import CryptoKit

/// No app process, API request, preference or real Application Support path is
/// used here. The supplied callbacks simulate process lifecycle and health.
@MainActor
func runBackendStoreTests(check: (Bool, String) -> Void) async throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appendingPathComponent("PromptFinch-backend-tests-\(UUID().uuidString)", isDirectory: true)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: temporary) }

    func seed(_ name: String) throws -> URL {
        let directory = temporary.appendingPathComponent(name, isDirectory: true)
        var hash = SHA256()
        for relative in BackendStore.files {
            let file = directory.appendingPathComponent(relative)
            try manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = Data("synthetic \(name) \(relative)".utf8)
            try data.write(to: file)
            hash.update(data: Data(relative.utf8)); hash.update(data: Data([0]))
            hash.update(data: data); hash.update(data: Data([0]))
        }
        let id = hash.finalize().map { String(format: "%02x", $0) }.joined()
        try Data("\(id)\n".utf8).write(to: directory.appendingPathComponent(".backend-id"))
        try Data(#"{"type":"module"}"#.utf8).write(to: directory.appendingPathComponent("package.json"))
        return directory
    }

    func rejects(_ action: () throws -> Void) -> Bool {
        do { try action(); return false } catch { return true }
    }

    let firstSeed = try seed("first")
    let nextSeed = try seed("next")
    let storeRoot = temporary.appendingPathComponent("support/backend", isDirectory: true)
    let originalStore = BackendStore(root: storeRoot, seed: firstSeed)
    let original = try originalStore.prepare()
    check(try originalStore.currentTarget() == original.target, "first launch seeds a managed backend")
    let oldBytes = try Data(contentsOf: original.root.appendingPathComponent("server.js"))
    let nextStore = BackendStore(root: storeRoot, seed: nextSeed)
    let nextID = try nextStore.verify(nextSeed).id
    check(nextID != original.id, "test bundle has a distinct backend hash")
    check(try nextStore.prepare().id == original.id, "new app keeps an existing external selection by default")
    check(!manager.fileExists(atPath: storeRoot.appendingPathComponent("releases/\(nextID)").path),
          "ordinary launch does not stage a replacement bundle")

    var lifecycle: [String] = []
    let selectedID = try await nextStore.useBundled(beforeActivation: {
        lifecycle.append("stop")
        check(try nextStore.currentTarget() == original.target, "candidate is staged before old selection is switched")
    }, validate: { candidate in
        lifecycle.append("health")
        check(try nextStore.currentTarget() == candidate.target, "health check observes the selected candidate")
        return candidate.id
    }, beforeRollback: {
        lifecycle.append("rollback-stop")
    }, restore: { _ in lifecycle.append("restore") })
    check(selectedID == nextID && lifecycle == ["stop", "health"], "explicit selection returns its validated backend")
    check(try nextStore.currentTarget() == "releases/\(nextID)", "explicit action atomically selects the bundled release")
    check(try Data(contentsOf: original.root.appendingPathComponent("server.js")) == oldBytes,
          "bundled selection preserves the previous release")

    // A failed startup uses the same transaction as LocalBackend. It restores
    // the previous pointer before asking the caller to restart the old child.
    try nextStore.activate(original.target, replacing: "releases/\(nextID)")
    lifecycle = []
    do {
        let _: String = try await nextStore.useBundled(beforeActivation: { lifecycle.append("stop") }, validate: { _ in
            lifecycle.append("failed-health")
            throw NSError(domain: "SyntheticHealthFailure", code: 1)
        }, beforeRollback: { lifecycle.append("rollback-stop") }, restore: { previous in
            lifecycle.append("restore")
            check(previous?.id == original.id, "rollback supplies the previous verified backend")
            check(try nextStore.currentTarget() == original.target, "rollback restores pointer before old-child restart")
        })
        check(false, "failed startup must be reported")
    } catch {
        check(error.localizedDescription.contains("SyntheticHealthFailure"), "rollback reports the original startup failure")
    }
    check(lifecycle == ["stop", "failed-health", "rollback-stop", "restore"], "failed startup stops candidate then restores old backend")
    check(try nextStore.currentTarget() == original.target, "failed startup leaves the old version active")
    check(manager.fileExists(atPath: storeRoot.appendingPathComponent("releases/\(nextID)").path),
          "rollback retains the candidate without deleting old releases")

    let badSeed = try seed("bad")
    try Data("tampered".utf8).write(to: badSeed.appendingPathComponent("server.js"))
    let badStore = BackendStore(root: storeRoot, seed: badSeed)
    var stopped = false
    do {
        let _: String = try await badStore.useBundled(beforeActivation: { stopped = true }, validate: { $0.id },
                                                     beforeRollback: {}, restore: { _ in })
        check(false, "tampered bundle must be rejected")
    } catch {
        check(!stopped, "invalid bundle is rejected before stopping the running child")
    }
    check(try badStore.currentTarget() == original.target, "invalid bundled hash does not change current")

    let unmanagedRoot = temporary.appendingPathComponent("unmanaged", isDirectory: true)
    try manager.createDirectory(at: unmanagedRoot.appendingPathComponent("current"), withIntermediateDirectories: true)
    let marker = unmanagedRoot.appendingPathComponent("current/keep.txt")
    try Data("keep".utf8).write(to: marker)
    let unmanaged = BackendStore(root: unmanagedRoot, seed: nextSeed)
    check(rejects { _ = try unmanaged.prepare() }, "ordinary current directory is refused")
    do {
        let _: String = try await unmanaged.useBundled(beforeActivation: { check(false, "unmanaged current cannot stop the child") },
                                                      validate: { $0.id }, beforeRollback: {}, restore: { _ in })
        check(false, "explicit action must refuse unmanaged current")
    } catch {
        check(try Data(contentsOf: marker) == Data("keep".utf8), "unmanaged current contents remain untouched")
    }

    let outsideRoot = temporary.appendingPathComponent("outside-link", isDirectory: true)
    try manager.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
    try manager.createSymbolicLink(atPath: outsideRoot.appendingPathComponent("current").path, withDestinationPath: "../first")
    let outside = BackendStore(root: outsideRoot, seed: nextSeed)
    check(rejects { _ = try outside.prepare() }, "unmanaged relative current target is refused")
    check(try manager.destinationOfSymbolicLink(atPath: outsideRoot.appendingPathComponent("current").path) == "../first",
          "unmanaged symbolic link remains unchanged")

    // Inject an atomic-rename failure: the previous target is still valid and
    // its child is restarted, while temporary symlinks are always removed.
    let failing = BackendStore(root: storeRoot, seed: nextSeed, replaceLink: { _, _ in
        throw NSError(domain: "SyntheticRenameFailure", code: 2)
    })
    var restoredAfterRename = false
    do {
        let _: String = try await failing.useBundled(beforeActivation: {}, validate: { _ in
            check(false, "failed activation cannot run candidate health check")
            return "unexpected"
        }, beforeRollback: {}, restore: { previous in restoredAfterRename = previous?.id == original.id })
        check(false, "failed activation must be reported")
    } catch {
        check(restoredAfterRename, "activation failure restarts the previous selection")
    }
    check(try failing.currentTarget() == original.target, "atomic activation failure preserves current")
    check(try manager.contentsOfDirectory(atPath: storeRoot.path).allSatisfy { !$0.hasPrefix(".current-") },
          "failed activation removes temporary symlinks")

    // A rollback whose old process also fails must never be reported as a
    // successful recovery. Its pointer is still restored for a later retry.
    do {
        let _: String = try await nextStore.useBundled(beforeActivation: {}, validate: { _ in
            throw NSError(domain: "SyntheticCandidateFailure", code: 3)
        }, beforeRollback: {}, restore: { _ in throw NSError(domain: "SyntheticRestoreFailure", code: 4) })
        check(false, "failed rollback must be reported")
    } catch {
        check(error.localizedDescription.contains("SyntheticRestoreFailure"), "rollback failure is reported distinctly")
    }
    check(try nextStore.currentTarget() == original.target, "failed old-child restart still preserves the old pointer")

    // Do not overwrite a selection changed by another updater while awaiting
    // candidate health. Both known releases remain available for manual repair.
    let thirdSeed = try seed("third")
    let thirdStore = BackendStore(root: storeRoot, seed: thirdSeed)
    let third = try thirdStore.stageBundled()
    do {
        let _: String = try await nextStore.useBundled(beforeActivation: {}, validate: { candidate in
            try thirdStore.activate(third.target, replacing: candidate.target)
            throw NSError(domain: "SyntheticConcurrentUpdate", code: 5)
        }, beforeRollback: {}, restore: { _ in check(false, "concurrent version must not be replaced by rollback") })
        check(false, "concurrent update conflict must be reported")
    } catch {
        check(try thirdStore.currentTarget() == third.target, "rollback refuses to clobber a concurrent external update")
    }

    let corruptRoot = temporary.appendingPathComponent("corrupt", isDirectory: true)
    let corrupt = BackendStore(root: corruptRoot, seed: firstSeed)
    let corrupted = try corrupt.prepare()
    try Data("unexpected".utf8).write(to: corrupted.root.appendingPathComponent("public/style.css"))
    check(rejects { _ = try corrupt.prepare() }, "a corrupt selected release cannot launch")
    check(rejects { _ = try corrupt.stageBundled() }, "a corrupt same-hash release is never overwritten")
    check(try corrupt.currentTarget() == corrupted.target, "corruption errors do not delete or redirect the selection")
}
