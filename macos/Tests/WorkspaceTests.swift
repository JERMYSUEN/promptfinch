import AppKit

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
}
