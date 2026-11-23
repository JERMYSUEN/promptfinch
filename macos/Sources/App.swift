import AppKit
import SwiftUI

@MainActor
protocol PasteOperations {
    func copy(_ text: String) -> Bool
    func paste(_ text: String, expectedTarget: SelectionCapture?,
               onRestore: @escaping (ClipboardRestoreOutcome) -> Void) -> PasteBackOutcome
}

@MainActor
struct SystemPasteOperations: PasteOperations {
    func copy(_ text: String) -> Bool { PasteBack.write(text) }
    func paste(_ text: String, expectedTarget: SelectionCapture?,
               onRestore: @escaping (ClipboardRestoreOutcome) -> Void) -> PasteBackOutcome {
        PasteBack.paste(text, expectedTarget: expectedTarget, onRestore: onRestore)
    }
}

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published var original = ""
    @Published var task: String
    @Published var targetModel: String
    @Published var result: PromptResult?
    @Published private(set) var resultOriginal = ""
    @Published var busy = false
    @Published private(set) var backendSwitching = false
    var unavailable: Bool { busy || backendSwitching }
    @Published var message = ""
    @Published var isError = false
    @Published var config: ServiceConfig?
    @Published var settingsVisible = false
    @Published var comparisonVisible = false
    @Published var accessibilityGranted: Bool = TextSelection.authorized
    @Published var watcherLeft: Bool = SelectionWatcher.leftTrigger {
        didSet { if oldValue != watcherLeft { setWatcher(left: watcherLeft, right: watcherRight) } }
    }
    @Published var watcherRight: Bool = SelectionWatcher.rightTrigger {
        didSet { if oldValue != watcherRight { setWatcher(left: watcherLeft, right: watcherRight) } }
    }
    @Published var language = UILanguage.load() {
        didSet {
            language.save()
            message = L10n.relocalize(message, from: oldValue, to: language)
            resultPanel.updateLanguage(from: oldValue)
            watcher.updateLanguage()
            onLanguageChange?()
        }
    }
    var onLanguageChange: (() -> Void)?
    let backend: LocalBackend
    let nativeEngine: NativeOptimizerEngine
    let watcher = SelectionWatcher()
    let resultPanel = ResultPanel()
    @Published var promptLanguage: String
    @Published var refinementStyle: String
    @Published var nativeConfig: NativeProviderConfig
    @Published var streamingPreview = ""
    @Published private(set) var cachedFetchedModels: [ProviderPreset: [ProviderModelOption]] = [:]
    @Published var appAwarePresetsEnabled: Bool {
        didSet { preferences.set(appAwarePresetsEnabled, forKey: "appAwarePresetsEnabled") }
    }
    @Published var redactSecretsEnabled: Bool {
        didSet { preferences.set(redactSecretsEnabled, forKey: "redactSecretsEnabled") }
    }
    @Published var menuBarOnlyMode: Bool {
        didSet {
            preferences.set(menuBarOnlyMode, forKey: "menuBarOnlyMode")
            onMenuBarModeChange?(menuBarOnlyMode)
        }
    }
    @Published var miniWindowMode: Bool {
        didSet {
            preferences.set(miniWindowMode, forKey: "miniWindowMode")
            onMiniWindowModeChange?(miniWindowMode)
        }
    }
    @Published private(set) var sessionHistory: [SessionHistoryEntry] = []
    @Published var pasteBackEnabled: Bool = SelectionWatcher.pasteBack {
        didSet { UserDefaults.standard.set(pasteBackEnabled, forKey: SelectionWatcher.pasteBackKey) }
    }
    let settingsDraft = SettingsDraftState()
    let miniUIState = MiniUIState()
    var onMenuBarModeChange: ((Bool) -> Void)?
    var onMiniWindowModeChange: ((Bool) -> Void)?
    private var sourcePID: pid_t?
    private var sourceCapture: SelectionCapture?
    private var activeEventSequence: UInt64?
    private var operation: Task<Void, Never>?
    private var generationID = UUID()
    private var configurationID = UUID()
    private var pasteFeedbackID = UUID()
    private let pasteOperations: PasteOperations
    private let preferences: UserDefaults
    private let secretStore: SecretStorage
    var showWindow: (() -> Void)?

    init(pasteOperations: PasteOperations? = nil, backend: LocalBackend? = nil,
         preferences: UserDefaults = .standard, secretStore: SecretStorage = KeychainSecretStore(),
         nativeEngine: NativeOptimizerEngine? = nil) {
        self.pasteOperations = pasteOperations ?? SystemPasteOperations()
        self.backend = backend ?? LocalBackend()
        self.preferences = preferences
        self.secretStore = secretStore
        self.nativeEngine = nativeEngine ?? NativeOptimizerEngine(secrets: secretStore)
        task = preferences.string(forKey: "task") ?? "general"
        targetModel = preferences.string(forKey: "targetModel") ?? ""
        let storedLang = preferences.string(forKey: "promptLanguage") ?? "en"
        promptLanguage = ["en", "zh-Hant"].contains(storedLang) ? storedLang : "en"
        let storedStyle = preferences.string(forKey: "refinementStyle") ?? "balanced"
        refinementStyle = ["balanced", "concise", "structured"].contains(storedStyle) ? storedStyle : "balanced"
        nativeConfig = NativeProviderConfig.load(from: preferences)
        appAwarePresetsEnabled = preferences.object(forKey: "appAwarePresetsEnabled") as? Bool ?? true
        redactSecretsEnabled = preferences.object(forKey: "redactSecretsEnabled") as? Bool ?? false
        menuBarOnlyMode = preferences.object(forKey: "menuBarOnlyMode") as? Bool ?? false
        miniWindowMode = preferences.object(forKey: "miniWindowMode") as? Bool ?? false
        resultPanel.onPasteBack = { [weak self] in self?.pasteBackFromPanel() }
        resultPanel.onCopy = { [weak self] in self?.copyFromPanel() }
        resultPanel.onClose = { [weak self] in self?.closeResultPanel() }
        resultPanel.onRerun = { [weak self] style in self?.rerunFromPanel(style: style) }
    }

    var compactStatusLabel: String {
        guard let config else { return L10n.text(.connecting) }
        if config.mode == "mock" { return "Demo" }
        if !config.ready { return L10n.text(.incompleteConfig) }
        return config.generationModel ?? L10n.text(.configuredModel)
    }

    var quickModelOptions: [ProviderModelOption] {
        var list = nativeConfig.preset.suggestedModels
        var seen = Set(list.map(\.id))
        for item in cachedFetchedModels[nativeConfig.preset] ?? [] where seen.insert(item.id).inserted {
            list.append(item)
        }
        let active = nativeConfig.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !active.isEmpty && seen.insert(active).inserted {
            list.insert(ProviderModelOption(id: active, title: "", note: ""), at: 0)
        }
        return list
    }

    func quickSwitchNativeModel(_ modelID: String) {
        let cleaned = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, nativeConfig.enabled, !nativeConfig.demoMode else { return }
        guard cleaned != nativeConfig.model else { return }
        var updated = nativeConfig
        updated.model = cleaned
        updated.jsonMode = updated.preset.defaultJSONMode
        updated.thinkingMode = updated.preset.resolvedThinkingMode(for: cleaned)
        saveNativeProvider(updated, apiKey: nil)
        settingsDraft.modelName = cleaned
        notify(L10n.text(.modelSwitched, cleaned))
    }

    func restoreSessionEntry(_ entry: SessionHistoryEntry) {
        guard !unavailable else { return }
        original = entry.original
        result = entry.result
        resultOriginal = entry.original
        notify(L10n.text(.promptReady))
    }

    private func recordSessionHistory(original: String, result: PromptResult) {
        let entry = SessionHistoryEntry(original: original, result: result)
        sessionHistory.removeAll { $0.original == original && $0.result.prompt == result.prompt }
        sessionHistory.insert(entry, at: 0)
        if sessionHistory.count > 5 {
            sessionHistory = Array(sessionHistory.prefix(5))
        }
    }

    func savedAPIKey(for preset: ProviderPreset) -> String {
        secretStore.readSecret(account: preset.rawValue) ?? ""
    }

    func saveNativeProvider(_ updated: NativeProviderConfig, apiKey: String?) {
        updated.save(to: preferences)
        nativeConfig = updated
        if let apiKey {
            _ = secretStore.writeSecret(apiKey, account: updated.preset.rawValue)
        }
        if updated.enabled {
            config = nativeEngine.serviceConfig(for: updated)
            Task { try? await backend.stop() }
        } else {
            refresh()
        }
    }

    func enableNativeDemo() {
        var updated = nativeConfig
        updated.enabled = true
        updated.demoMode = true
        saveNativeProvider(updated, apiKey: nil)
        notify(L10n.text(.mockNotice))
    }

    func openNativeModelSetup() {
        settingsDraft.activeTab = .model
        settingsDraft.preferNativeOnNextSync = true
        settingsVisible = true
    }

    var shouldShowQuickSetupBanner: Bool {
        if nativeConfig.enabled && !nativeConfig.demoMode && nativeEngine.hasCredential(for: nativeConfig) {
            return false
        }
        if !nativeConfig.enabled && !backend.configurationPath.isEmpty && config?.ready == true && config?.mode == "live" {
            return false
        }
        return true
    }

    func testNativeProviderConnection() {
        guard !unavailable else { return }
        let current = nativeConfig
        notify(L10n.text(.connecting))
        Task {
            do {
                let outcome = try await nativeEngine.testConnection(config: current)
                notify("\(outcome.model) · OK (\(outcome.latencyMs)ms)")
            } catch {
                notify(L10n.errorDescription(error), error: true)
            }
        }
    }

    func fetchNativeProviderModels(draft: SettingsDraftState) {
        guard !unavailable, !draft.fetchingModels else { return }
        let preset = draft.selectedPreset
        let probeConfig = NativeProviderConfig(
            enabled: true,
            demoMode: false,
            preset: preset,
            baseURL: draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            model: draft.modelName.trimmingCharacters(in: .whitespacesAndNewlines),
            jsonMode: preset.defaultJSONMode,
            thinkingMode: preset.defaultThinkingMode,
            timeoutSeconds: nativeConfig.timeoutSeconds
        )
        let enteredKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.fetchingModels = true
        notify(L10n.text(.fetchingModels))
        Task {
            defer { draft.fetchingModels = false }
            do {
                let models = try await nativeEngine.fetchModels(
                    config: probeConfig,
                    apiKeyOverride: enteredKey.isEmpty ? nil : enteredKey
                )
                guard draft.selectedPreset == preset else { return }
                draft.fetchedModels = models
                cachedFetchedModels[preset] = models
                if draft.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let first = models.first {
                    draft.modelName = first.id
                }
                notify(L10n.text(.fetchedModelsCount, String(models.count)))
            } catch {
                notify(L10n.errorDescription(error), error: true)
            }
        }
    }

    var modeLabel: String {
        guard let config else { return L10n.text(.connecting) }
        if config.mode == "mock" { return L10n.text(.mockMode) }
        if !config.ready { return L10n.text(.incompleteConfig) }
        return L10n.text(.liveMode, config.generationModel ?? L10n.text(.configuredModel))
    }

    func refresh() {
        guard !unavailable else { return }
        if nativeConfig.enabled {
            configurationID = UUID()
            config = nativeEngine.serviceConfig(for: nativeConfig)
            return
        }
        let token = UUID()
        configurationID = token
        config = nil
        let status = L10n.text(.connecting)
        notify(status)
        Task {
            do {
                let loaded = try await backend.ensureRunning()
                guard configurationID == token, !backendSwitching else { return }
                config = loaded
                if message == status, !isError { notify("") }
            } catch {
                guard configurationID == token, !backendSwitching else { return }
                config = backend.verifiedConfiguration
                notify(L10n.errorDescription(error), error: true)
            }
        }
    }

    func notify(_ text: String, error: Bool = false) { message = text; isError = error }

    func receive(_ text: String, generateImmediately: Bool = true, openStudio: Bool = true) {
        guard !backendSwitching else { return }
        clear(wipeHistory: false)
        original = text
        sourcePID = nil
        sourceCapture = nil
        if openStudio { showWindow?() }
        if generateImmediately { generate() }
    }

    // One-click conversion from the floating bar, hotkey or Services: stays
    // in the background so the source app keeps focus. The generated prompt is
    // shown in a floating result window next to the selection, never in a
    // suddenly-raised main window.
    func convert(_ text: String, sourcePID: pid_t?, sourceCapture: SelectionCapture? = nil,
                 anchor: CGPoint? = nil, eventSequence: UInt64? = nil) {
        guard !backendSwitching else { return }
        clear(wipeHistory: false)
        original = text
        self.sourcePID = sourcePID
        self.sourceCapture = sourceCapture
        activeEventSequence = eventSequence
        DebugLog.write("convert seq=\(eventSequence.map(String.init) ?? "-") sourcePID=\(sourcePID.map(String.init) ?? "nil") selectedUTF16=\(text.utf16.count)")
        generate(autoPaste: true, background: true, anchor: anchor ?? mouseAnchor)
    }

    private var mouseAnchor: CGPoint {
        // NSEvent and ResultPanel both use AppKit screen coordinates.
        NSEvent.mouseLocation
    }

    func setWatcher(left: Bool, right: Bool) {
        UserDefaults.standard.set(left, forKey: SelectionWatcher.leftKey)
        UserDefaults.standard.set(right, forKey: SelectionWatcher.rightKey)
        watcher.invalidatePendingActions()
    }

    func clipboard(openStudio: Bool = true) {
        guard !backendSwitching else { return }
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if openStudio { showWindow?() }
            notify(L10n.text(.emptyClipboard), error: true)
            return
        }
        receive(text, generateImmediately: openStudio, openStudio: openStudio)
    }

    func selection() {
        guard !backendSwitching else { return }
        do {
            let capture = try TextSelection.readCapture()
            convert(capture.text, sourcePID: capture.pid, sourceCapture: capture,
                    anchor: capture.bounds.map { TextSelection.topLeftPoint(from: $0) })
        } catch { showWindow?(); notify(L10n.errorDescription(error), error: true) }
    }

    func rerunFromPanel(style: String) {
        guard !backendSwitching, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if ["balanced", "concise", "structured"].contains(style) {
            refinementStyle = style
        }
        generate(autoPaste: false, background: true, preserveAnchor: true)
    }

    func generate(autoPaste: Bool = false, background: Bool = false, anchor: CGPoint? = nil, preserveAnchor: Bool = false) {
        guard !backendSwitching else { return }
        let resolvedTask: String
        if background && appAwarePresetsEnabled, let pid = sourcePID,
           let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
            resolvedTask = AppContextPreset.suggestedTask(forBundleID: bundleID, fallback: task)
        } else {
            resolvedTask = task
        }
        let input = PromptRequest(prompt: original, task: resolvedTask, targetModel: targetModel,
                                  promptLanguage: promptLanguage, notesLanguage: language.rawValue,
                                  style: refinementStyle)
        let eventID = activeEventSequence.map(String.init) ?? "-"
        do { try input.validate() }
        catch {
            notify(L10n.errorDescription(error), error: true)
            if background { resultPanel.fail(status: L10n.errorDescription(error), eventSequence: activeEventSequence) }
            else if autoPaste { showWindow?() }
            return
        }
        cancel(hideResultPanel: !preserveAnchor)
        let token = UUID()
        generationID = token
        let configToken = UUID()
        configurationID = configToken
        let useNative = nativeConfig.enabled
        let activeNativeConfig = nativeConfig
        let redact = redactSecretsEnabled
        let activeStyle = refinementStyle
        let activeModelBadge = useNative
            ? (activeNativeConfig.demoMode ? "Demo" : activeNativeConfig.model)
            : (config?.generationModel ?? "")
        if !useNative { config = nil }
        result = nil; resultOriginal = ""; streamingPreview = ""; busy = true; notify(L10n.text(.refining))
        DebugLog.write("generate seq=\(eventID) started background=\(background) native=\(useNative) selectedUTF16=\(input.prompt.utf16.count)")
        if background {
            resultPanel.present(
                anchor: anchor ?? mouseAnchor,
                modelName: activeModelBadge,
                style: activeStyle,
                preserveAnchor: preserveAnchor,
                eventSequence: activeEventSequence
            )
        } else {
            resultPanel.orderOut(nil)
        }
        preferences.set(task, forKey: "task")
        preferences.set(targetModel, forKey: "targetModel")
        preferences.set(promptLanguage, forKey: "promptLanguage")
        preferences.set(refinementStyle, forKey: "refinementStyle")
        operation = Task {
            do {
                let output: PromptResult
                if useNative {
                    if configurationID == configToken { config = nativeEngine.serviceConfig(for: activeNativeConfig) }
                    output = try await nativeEngine.optimize(input, config: activeNativeConfig, redactSecrets: redact) { [weak workspace = self] preview in
                        Task { @MainActor in
                            guard let workspace, workspace.generationID == token, workspace.busy else { return }
                            workspace.streamingPreview = preview
                            if background {
                                workspace.resultPanel.updateStreamingPreview(preview)
                            }
                        }
                    }
                } else {
                    _ = try await backend.ensureRunning()
                    // Backend health belongs to the configuration, even if the
                    // content generation was cancelled while checking it. Read the
                    // current lifecycle's snapshot rather than an old await result.
                    if configurationID == configToken { config = backend.verifiedConfiguration }
                    try Task.checkCancellation()
                    guard generationID == token else { return }
                    DebugLog.write("generate seq=\(eventID) backend=ready request=sent")
                    output = try await backend.client.optimize(input)
                }
                DebugLog.write("generate seq=\(eventID) done mode=\(output.mode) generatedUTF16=\(output.prompt.utf16.count)")
                guard generationID == token, !Task.isCancelled else { return }
                streamingPreview = ""
                result = output
                resultOriginal = input.prompt
                recordSessionHistory(original: input.prompt, result: output)
                let finishedModel = output.mode == "mock" ? "Demo" : (output.generationModel ?? activeModelBadge)
                if output.mode == "mock" {
                    notify(L10n.text(.mockNotice))
                    if background {
                        resultPanel.finish(prompt: output.prompt, status: L10n.text(.mockPanelNotice), canPasteBack: false, error: true, improvements: output.improvements, assumptions: output.assumptions, modelName: finishedModel, style: activeStyle, canRerun: true, eventSequence: activeEventSequence)
                    } else if autoPaste { showWindow?() }
                } else if autoPaste {
                    pasteBack(output.prompt)
                } else {
                    notify(L10n.text(.promptReady))
                    if background {
                        resultPanel.finish(prompt: output.prompt, status: L10n.text(.promptComplete), canPasteBack: canOfferPasteBack, error: false, improvements: output.improvements, assumptions: output.assumptions, modelName: finishedModel, style: activeStyle, canRerun: true, eventSequence: activeEventSequence)
                    }
                }
            } catch {
                DebugLog.write("generate seq=\(eventID) errorType=\(String(describing: type(of: error)))")
                if !useNative && configurationID == configToken { config = backend.verifiedConfiguration }
                guard generationID == token, !Task.isCancelled else { return }
                streamingPreview = ""
                if let networkError = error as? URLError, networkError.code == .cannotConnectToHost {
                    notify(L10n.text(.cannotConnect), error: true)
                } else { notify(L10n.errorDescription(error), error: true) }
                if background { resultPanel.fail(status: L10n.errorDescription(error), eventSequence: activeEventSequence) } else if autoPaste { showWindow?() }
            }
            if generationID == token { streamingPreview = ""; busy = false; operation = nil }
        }
    }

    private func pasteBack(_ prompt: String) {
        if sourceCapture?.isTerminal == true {
            copyTerminalResult(prompt)
            return
        }
        let improvements = result?.improvements ?? []
        let assumptions = result?.assumptions ?? []
        guard pasteBackEnabled, TextSelection.authorized else {
            let copied = pasteOperations.copy(prompt)
            DebugLog.write("pasteBack skipped: enabled=\(pasteBackEnabled) authorized=\(TextSelection.authorized)")
            let status = copied
                ? L10n.text(TextSelection.authorized ? .autoPasteOffCopied : .pastePermissionCopied)
                : L10n.text(.copyFailedPanel)
            notify(status, error: !copied)
            resultPanel.finish(prompt: prompt,
                               status: copied && canOfferPasteBack ? L10n.text(.manualPasteHelp) : status,
                               canPasteBack: canOfferPasteBack, error: !copied,
                               improvements: improvements, assumptions: assumptions, eventSequence: activeEventSequence)
            return
        }
        requestPasteBack(prompt)
    }

    private var canOfferPasteBack: Bool {
        TextSelection.authorized && sourceCapture?.canPasteBack == true
    }

    private func copyTerminalResult(_ prompt: String) {
        invalidatePendingPasteFeedback()
        let copied = pasteOperations.copy(prompt)
        let status = L10n.text(copied ? .terminalCopied : .copyFailedPanel)
        notify(status, error: !copied)
        resultPanel.finish(prompt: prompt, status: status, canPasteBack: false,
                           error: !copied, improvements: result?.improvements ?? [],
                           assumptions: result?.assumptions ?? [], eventSequence: activeEventSequence)
    }

    private func requestPasteBack(_ prompt: String) {
        // A terminal selection is display text, even when its AX helper reports
        // an editable UTF-16 range. Never send generated text into process stdin.
        if sourceCapture?.isTerminal == true {
            copyTerminalResult(prompt)
            return
        }
        let improvements = result?.improvements ?? []
        let assumptions = result?.assumptions ?? []
        let feedbackID = UUID()
        pasteFeedbackID = feedbackID
        let generation = generationID
        var requested = false
        let outcome = pasteOperations.paste(prompt, expectedTarget: sourceCapture) { [weak self] restored in
            guard let self, requested, self.pasteFeedbackID == feedbackID,
                  self.generationID == generation, self.result?.prompt == prompt else { return }
            let key: L10n.Key
            switch restored {
            case .restored: key = .pasteRequestedRestored
            case .skippedNewerCopy: key = .pasteRequestedNewCopy
            case .failed: key = .pasteRequestedRestoreFailed
            case .superseded: return
            }
            let status = L10n.text(key)
            self.notify(status, error: restored == .failed)
            // Updating feedback must never reopen a panel the user closed.
            self.resultPanel.updateStatus(status, error: restored == .failed)
        }
        switch outcome {
        case .pasteRequested:
            requested = true
            let status = L10n.text(.pasteRequested)
            notify(status)
            resultPanel.finish(prompt: prompt, status: status, canPasteBack: false, error: false,
                               improvements: improvements, assumptions: assumptions, eventSequence: activeEventSequence)
        case .notAttempted:
            let copied = pasteOperations.copy(prompt)
            let status = L10n.text(copied ? .unsafeTargetCopied : .unsafePasteFailed)
            notify(status, error: !copied)
            resultPanel.finish(prompt: prompt, status: status, canPasteBack: false, error: !copied,
                               improvements: improvements, assumptions: assumptions, eventSequence: activeEventSequence)
        case .clipboardUnavailable:
            // An unsafe snapshot or failed recovery must not be followed by an
            // automatic copy that overwrites the clipboard we tried to protect.
            let status = L10n.text(.clipboardUnavailable)
            notify(status, error: true)
            resultPanel.finish(prompt: prompt, status: status, canPasteBack: false, error: true,
                               improvements: improvements, assumptions: assumptions, eventSequence: activeEventSequence)
        }
    }

    // Result window buttons.
    func pasteBackFromPanel() {
        guard let result else { return }
        requestPasteBack(result.prompt)
    }

    func copyFromPanel() {
        invalidatePendingPasteFeedback()
        guard let result else { return }
        let copied = pasteOperations.copy(result.prompt)
        let status = copied ? L10n.text(.copied) : L10n.text(.copyFailed)
        notify(status, error: !copied)
        resultPanel.finish(prompt: result.prompt, status: copied ? L10n.text(.copiedClipboard) : status,
                           canPasteBack: false, error: !copied,
                           improvements: result.improvements, assumptions: result.assumptions,
                           eventSequence: activeEventSequence)
    }

    func closeResultPanel() {
        invalidatePendingPasteFeedback()
        if busy { cancel(); notify(L10n.text(.cancelled)) }
        DebugLog.write("resultPanel seq=\(activeEventSequence.map(String.init) ?? "-") hidden=close-button")
        resultPanel.orderOut(nil)
    }

    func copy() {
        invalidatePendingPasteFeedback()
        guard let result else { return }
        if pasteOperations.copy(result.prompt) { notify(L10n.text(.copiedPromptOnly)) }
        else { notify(L10n.text(.copyFailedWorkspace), error: true) }
    }

    func cancel(hideResultPanel: Bool = true) {
        invalidatePendingPasteFeedback()
        generationID = UUID()
        operation?.cancel(); operation = nil
        streamingPreview = ""
        if busy && hideResultPanel { resultPanel.orderOut(nil) }
        busy = false
    }

    func invalidatePendingPasteFeedback() { pasteFeedbackID = UUID() }

    #if PROMPTFINCH_TESTS
    var generationOperationForTesting: Task<Void, Never>? { operation }

    func setSelectionSourceForTesting(_ capture: SelectionCapture?) {
        sourceCapture = capture
        sourcePID = capture?.pid
    }
    #endif

    func clear(wipeHistory: Bool = true) {
        cancel()
        resultPanel.orderOut(nil)
        original = ""
        result = nil
        resultOriginal = ""
        sourcePID = nil
        sourceCapture = nil
        activeEventSequence = nil
        if wipeHistory { sessionHistory = [] }
        notify("")
    }

    private func changeBackend(_ success: L10n.Key, progress: L10n.Key = .backendChanging, action: @escaping () async throws -> ServiceConfig) {
        guard !backendSwitching else { return }
        cancel()
        backendSwitching = true
        let token = UUID()
        configurationID = token
        config = nil
        watcher.invalidatePendingActions()
        notify(L10n.text(progress))
        Task {
            defer { if configurationID == token { backendSwitching = false } }
            do {
                let loaded = try await action()
                guard configurationID == token else { return }
                config = loaded
                notify(L10n.text(success))
            } catch {
                guard configurationID == token else { return }
                config = backend.verifiedConfiguration
                notify(L10n.errorDescription(error), error: true)
            }
        }
    }

    func useConfig(_ url: URL?) {
        changeBackend(.configLoaded) { try await self.backend.selectConfiguration(url) }
    }

    func useBundledBackend() {
        guard !unavailable else { return }
        changeBackend(.bundledBackendSelected, progress: .backendSwitchInProgress) { try await self.backend.useBundledBackend() }
    }

    func restart() {
        changeBackend(.configLoaded) {
            try await self.backend.stop()
            return try await self.backend.ensureRunning()
        }
    }

    func shutdown() async throws {
        backendSwitching = true
        configurationID = UUID()
        watcher.stop()
        cancel()
        sessionHistory = []
        do { try await backend.stop() }
        catch {
            backendSwitching = false
            watcher.start()
            throw error
        }
    }

}

private let accent = Color(red: 0.16, green: 0.43, blue: 0.90)

func makeFinchMenuBarIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
        NSColor.black.setFill()
        NSColor.black.setStroke()
        // Tail
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 6.2, y: 10.6))
        tail.curve(to: NSPoint(x: 1.8, y: 13.8), controlPoint1: NSPoint(x: 4.3, y: 11.1), controlPoint2: NSPoint(x: 2.6, y: 12.2))
        tail.curve(to: NSPoint(x: 6.8, y: 12.2), controlPoint1: NSPoint(x: 3.8, y: 13.9), controlPoint2: NSPoint(x: 5.7, y: 13.2))
        tail.close()
        tail.fill()
        // Body + head silhouette
        NSBezierPath(ovalIn: NSRect(x: 5.0, y: 7.4, width: 7.6, height: 6.2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 7.2, y: 3.6, width: 5.4, height: 5.4)).fill()
        // Crest
        let crest = NSBezierPath()
        crest.move(to: NSPoint(x: 8.6, y: 4.1))
        crest.line(to: NSPoint(x: 8.3, y: 1.9))
        crest.line(to: NSPoint(x: 10.1, y: 3.2))
        crest.line(to: NSPoint(x: 10.7, y: 1.5))
        crest.line(to: NSPoint(x: 11.4, y: 3.8))
        crest.close()
        crest.fill()
        // Beak
        let beak = NSBezierPath()
        beak.move(to: NSPoint(x: 12.2, y: 5.1))
        beak.line(to: NSPoint(x: 15.8, y: 6.3))
        beak.line(to: NSPoint(x: 12.2, y: 7.5))
        beak.close()
        beak.fill()
        // Prompt perch bar
        let perch = NSBezierPath()
        perch.lineWidth = 1.4
        perch.lineCapStyle = .round
        perch.move(to: NSPoint(x: 4.0, y: 15.6))
        perch.line(to: NSPoint(x: 14.5, y: 15.6))
        perch.stroke()
        return true
    }
    image.isTemplate = true
    image.accessibilityDescription = "PromptFinch"
    return image
}

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Circle().fill(model.config?.mode == "live" && model.config?.ready == true ? accent : .orange).frame(width: 7, height: 7)
                Text(model.miniWindowMode ? "PromptFinch" : L10n.text(.workspaceTitle))
                    .font(.system(size: model.miniWindowMode ? 14 : 16, weight: .semibold))
                    .fixedSize(horizontal: model.miniWindowMode, vertical: false)
                    .lineLimit(1)
                    .help(L10n.text(.workspaceIntro))
                QuickModelMenuBadge(model: model, compact: model.miniWindowMode) {
                    model.settingsVisible = true
                }
                Spacer(minLength: 4)
                if model.miniWindowMode {
                    Button { model.miniWindowMode = false } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.text(.fullWindowToggle))
                    .accessibilityIdentifier("toggleMiniWindow")
                    Button { model.settingsVisible = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.text(.settings))
                    .accessibilityIdentifier("settings")
                } else {
                    Button { model.miniWindowMode = true } label: {
                        Label(L10n.text(.miniWindowToggle), systemImage: "rectangle.compress.vertical")
                            .font(.system(size: 12))
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("toggleMiniWindow")
                    Button { model.settingsVisible = true } label: {
                        Label(L10n.text(.settings), systemImage: "gearshape").font(.system(size: 12))
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("settings")
                }
            }

            if model.shouldShowQuickSetupBanner {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(accent)
                    Text(model.miniWindowMode ? L10n.text(.connectNativeAI) : L10n.text(.quickSetupBanner))
                        .font(.system(size: 11.5)).lineLimit(1)
                    Spacer()
                    Button(L10n.text(.connectNativeAI)) { model.openNativeModelSetup() }
                        .buttonStyle(.borderedProminent).tint(accent).controlSize(.small)
                    if !model.miniWindowMode && !(model.nativeConfig.enabled && model.nativeConfig.demoMode) {
                        Button(L10n.text(.useNativeDemo)) { model.enableNativeDemo() }
                            .controlSize(.small)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(accent.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if model.miniWindowMode {
                miniBody
            } else {
                fullBody
            }

            HStack(spacing: 10) {
                if !model.message.isEmpty {
                    Image(systemName: model.isError ? "exclamationmark.circle" : "info.circle").font(.system(size: 11))
                    Text(model.message).font(.system(size: 11.5)).textSelection(.enabled).accessibilityIdentifier("statusMessage")
                } else if !model.miniWindowMode {
                    Text(L10n.text(.memoryOnly) + " · " + L10n.text(.privacy))
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.busy { Button(L10n.text(.cancel)) { model.cancel(); model.notify(L10n.text(.cancelled)) }.controlSize(.small) }
            }.foregroundStyle(model.isError ? Color.red : .secondary).frame(minHeight: 22)
        }
        .padding(model.miniWindowMode ? 12 : 14)
        .frame(minWidth: model.miniWindowMode ? 356 : 660, minHeight: model.miniWindowMode ? 360 : 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.settingsVisible) { CompactSettingsView(model: model, draft: model.settingsDraft) }
        .environment(\.locale, Locale(identifier: model.language.rawValue))
        .onReceive(model.$original.dropFirst().removeDuplicates()) { _ in
            if model.result != nil { model.invalidatePendingPasteFeedback(); model.notify(L10n.text(.originalChanged)) }
        }
        .onReceive(model.$task.dropFirst().removeDuplicates()) { _ in
            if model.result != nil { model.invalidatePendingPasteFeedback(); model.notify(L10n.text(.purposeChanged)) }
        }
        .onReceive(model.$targetModel.dropFirst().removeDuplicates()) { _ in
            if model.result != nil { model.invalidatePendingPasteFeedback(); model.notify(L10n.text(.targetChanged)) }
        }
    }

    private var miniBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Picker("", selection: $model.task) {
                    Text(L10n.text(.general)).tag("general"); Text(L10n.text(.writing)).tag("writing"); Text(L10n.text(.analysis)).tag("analysis")
                    Text(L10n.text(.coding)).tag("coding"); Text(L10n.text(.summary)).tag("summary"); Text(L10n.text(.marketing)).tag("marketing")
                }.labelsHidden().controlSize(.small).frame(maxWidth: 92)
                Picker("", selection: $model.refinementStyle) {
                    Text(L10n.text(.styleBalanced)).tag("balanced")
                    Text(L10n.text(.styleConcise)).tag("concise")
                    Text(L10n.text(.styleStructured)).tag("structured")
                }.labelsHidden().controlSize(.small).frame(maxWidth: 76)
                Picker("", selection: $model.promptLanguage) {
                    Text("EN").tag("en")
                    Text("繁中").tag("zh-Hant")
                }.labelsHidden().controlSize(.small).pickerStyle(.segmented).frame(width: 76)
                Spacer(minLength: 4)
                Button { model.clipboard(openStudio: false) } label: { Image(systemName: "doc.on.clipboard") }
                    .buttonStyle(.borderless).help(L10n.text(.readClipboard))
                Button { model.clear() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help(L10n.text(.clear)).accessibilityIdentifier("clear")
            }.disabled(model.unavailable)

            TextEditor(text: $model.original).font(.system(size: 13))
                .padding(6).background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
                .frame(minHeight: 84, maxHeight: 112)
                .disabled(model.unavailable).accessibilityIdentifier("originalPrompt")

            Button { model.generate() } label: {
                HStack(spacing: 6) {
                    if model.busy { ProgressView().controlSize(.small) }
                    Text(model.busy ? L10n.text(.generating) : L10n.text(.generate)).font(.system(size: 12.5, weight: .semibold))
                }.frame(maxWidth: .infinity).padding(.vertical, 3)
            }.buttonStyle(.borderedProminent).tint(accent).disabled(model.unavailable)
                .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("generate")

            if model.busy && !model.streamingPreview.isEmpty {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(L10n.text(.streamingStatus)).font(.system(size: 11.5, weight: .medium)).foregroundStyle(accent)
                    Spacer()
                }
                ScrollView {
                    Text(model.streamingPreview)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }.frame(minHeight: 100, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.35)))
            } else if let result = model.result {
                HStack {
                    Text(L10n.text(.copyablePrompt)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { model.copy() } label: { Label(L10n.text(.copy), systemImage: "doc.on.doc").font(.system(size: 11.5)) }
                        .controlSize(.small).accessibilityIdentifier("copyPrompt")
                }
                ScrollView {
                    Text(result.prompt)
                        .font(.system(size: 13))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .accessibilityIdentifier("resultPrompt")
                }.frame(minHeight: 100, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.16)))
                let notesCount = result.improvements.count + result.assumptions.count
                if notesCount > 0 {
                    DisclosureGroup(L10n.text(.notesSummary, String(notesCount))) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(result.improvements.enumerated()), id: \.offset) { _, item in Text("• \(item)") }
                                ForEach(Array(result.assumptions.enumerated()), id: \.offset) { _, item in Text("ⓘ \(item)").foregroundStyle(.secondary) }
                            }.font(.system(size: 11.5)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                        }.frame(maxHeight: 72)
                    }.font(.system(size: 11.5, weight: .medium))
                }
            }
        }
    }

    private var fullBody: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.text(.original)).font(.headline)
                TextEditor(text: $model.original).font(.system(size: 14))
                    .padding(8).background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
                    .frame(minHeight: 140)
                    .disabled(model.unavailable).accessibilityIdentifier("originalPrompt")
                HStack(spacing: 6) {
                    Picker("", selection: $model.task) {
                        Text(L10n.text(.general)).tag("general"); Text(L10n.text(.writing)).tag("writing"); Text(L10n.text(.analysis)).tag("analysis")
                        Text(L10n.text(.coding)).tag("coding"); Text(L10n.text(.summary)).tag("summary"); Text(L10n.text(.marketing)).tag("marketing")
                    }.labelsHidden().pickerStyle(.menu).frame(minWidth: 92, maxWidth: 110)
                    Picker("", selection: $model.refinementStyle) {
                        Text(L10n.text(.styleBalanced)).tag("balanced")
                        Text(L10n.text(.styleConcise)).tag("concise")
                        Text(L10n.text(.styleStructured)).tag("structured")
                    }.labelsHidden().pickerStyle(.menu).frame(minWidth: 70, maxWidth: 84)
                    Picker("", selection: $model.promptLanguage) {
                        Text("EN").tag("en")
                        Text("繁中").tag("zh-Hant")
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 78)
                    Spacer(minLength: 4)
                    Text("\(model.original.utf16.count) / 12,000").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }.disabled(model.unavailable)
                TextField(L10n.text(.targetPlaceholder), text: $model.targetModel).textFieldStyle(.roundedBorder).disabled(model.unavailable)
                HStack {
                    Button { model.clipboard() } label: { Label(L10n.text(.readClipboard), systemImage: "doc.on.clipboard") }.disabled(model.unavailable)
                    Spacer()
                    Button(L10n.text(.clear)) { model.clear() }.accessibilityIdentifier("clear")
                }
                Button { model.generate() } label: {
                    HStack { if model.busy { ProgressView().controlSize(.small) }; Text(model.busy ? L10n.text(.generating) : L10n.text(.generate)).fontWeight(.semibold) }
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                }.buttonStyle(.borderedProminent).tint(accent).disabled(model.unavailable)
                    .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("generate")
            }.frame(minWidth: 260, maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.text(.copyablePrompt)).font(.headline)
                    Spacer()
                    Button { model.copy() } label: { Label(L10n.text(.copy), systemImage: "doc.on.doc") }
                        .disabled(model.result == nil).accessibilityIdentifier("copyPrompt")
                }
                if model.busy && !model.streamingPreview.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(L10n.text(.streamingStatus)).font(.system(size: 11)).foregroundStyle(accent)
                    }
                } else if let result = model.result {
                    Text(result.mode == "mock" ? L10n.text(.mockResult) : L10n.text(.generatedBy, result.generationModel ?? L10n.text(.modelService)))
                        .font(.system(size: 11)).foregroundStyle(result.mode == "mock" ? Color.orange : .secondary)
                }
                ScrollView {
                    let displayText = model.result?.prompt ?? (!model.streamingPreview.isEmpty ? model.streamingPreview : L10n.text(.resultPlaceholder))
                    let isPlaceholder = model.result == nil && model.streamingPreview.isEmpty
                    Text(displayText)
                        .font(.system(size: 14)).foregroundStyle(isPlaceholder ? .secondary : .primary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .accessibilityIdentifier("resultPrompt")
                }.frame(minHeight: 160, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(model.busy && !model.streamingPreview.isEmpty ? accent.opacity(0.4) : Color.secondary.opacity(0.15)))
                if let result = model.result {
                    Button(L10n.text(.compareChanges)) { model.comparisonVisible = true }
                        .accessibilityIdentifier("compareChanges")
                        .sheet(isPresented: $model.comparisonVisible) {
                            PromptComparisonView(original: model.resultOriginal, optimized: result.prompt)
                        }
                    DisclosureGroup(L10n.text(.improvements)) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                if result.improvements.isEmpty {
                                    Text(L10n.text(.noImprovement, language: UILanguage(rawValue: result.notesLanguage ?? "") ?? model.language))
                                        .accessibilityIdentifier("noImprovement")
                                } else {
                                    ForEach(Array(result.improvements.enumerated()), id: \.offset) { _, item in Text("• \(item)") }
                                }
                                if !result.assumptions.isEmpty {
                                    Text(L10n.text(.assumptions)).fontWeight(.semibold).padding(.top, 6)
                                    ForEach(Array(result.assumptions.enumerated()), id: \.offset) { _, item in Text("• \(item)") }
                                }
                            }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                        }.frame(maxHeight: 125)
                    }.font(.system(size: 12))
                }
            }.frame(minWidth: 320, maxWidth: .infinity)
        }
    }
}

// Compare the source captured for this result, never a later edit in the workspace.
// Whole-line highlights describe text changes, not semantic correctness.
struct PromptComparisonView: View {
    let original: String
    let optimized: String
    @Environment(\.dismiss) private var dismiss

    private func highlights() -> (Set<Int>, Set<Int>) {
        let before = original.components(separatedBy: "\n")
        let after = optimized.components(separatedBy: "\n")
        // Bound diff work for prompts containing thousands of tiny lines.
        guard before.count <= 200, after.count <= 200 else {
            return (Set(before.indices), Set(after.indices))
        }
        let changes = after.difference(from: before)
        var removed = Set<Int>(), added = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): added.insert(offset)
            }
        }
        return (removed, added)
    }

    private func column(_ text: String, title: L10n.Key, changed: Set<Int>, insertion: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(title)).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if text.components(separatedBy: "\n").count > 200 {
                        Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                    ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                        Text((changed.contains(index) ? (insertion ? "+ " : "− ") : "  ") + line)
                            .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
                            .background(changed.contains(index) ? (insertion ? Color.green.opacity(0.12) : Color.red.opacity(0.10)) : .clear)
                    }
                    }
                }.padding(10)
            }.background(Color(nsColor: .textBackgroundColor))
        }.frame(maxWidth: .infinity)
    }

    var body: some View {
        let (removed, added) = highlights()
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text(.compareChanges)).font(.title2).fontWeight(.semibold)
            Text(L10n.text(.comparisonHelp)).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 16) {
                column(original, title: .sourceForResult, changed: removed, insertion: false)
                column(optimized, title: .copyablePrompt, changed: added, insertion: true)
            }
            HStack { Spacer(); Button(L10n.text(.done)) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(22).frame(width: 760, height: 520)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = WorkspaceModel()
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu?
    private var popover: NSPopover?
    private let hotKey = SelectionHotKey()
    private var permissionTimer: Timer?
    private var terminationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let initialMini = model.miniWindowMode
        let initialRect = initialMini ? NSRect(x: 0, y: 0, width: 376, height: 470) : NSRect(x: 0, y: 0, width: 720, height: 520)
        window = NSWindow(contentRect: initialRect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PromptFinch"
        window.minSize = initialMini ? NSSize(width: 356, height: 360) : NSSize(width: 660, height: 460)
        window.level = initialMini ? .floating : .normal
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WorkspaceView(model: model))
        window.center()
        model.showWindow = { [weak self] in self?.showWorkspace() }
        model.onMenuBarModeChange = { enabled in
            NSApp.setActivationPolicy(enabled ? .accessory : .regular)
        }
        model.onMiniWindowModeChange = { [weak self] mini in
            self?.applyWindowMode(mini: mini, animated: true)
        }
        buildPopover()
        buildMenu()
        model.onLanguageChange = { [weak self] in self?.buildMenu() }
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        hotKey.action = { [weak self] in self?.model.selection() }
        if !hotKey.register() { model.notify(L10n.text(.shortcutOccupied), error: true) }
        model.watcher.onSelection = { [weak model] capture, anchor, eventSequence in
            model?.convert(capture.text, sourcePID: capture.pid, sourceCapture: capture, anchor: anchor,
                           eventSequence: eventSequence)
        }
        model.watcher.canStartConversion = { [weak model] in model?.unavailable != true }
        model.watcher.activate()
        if !TextSelection.authorized {
            model.notify(L10n.text(.permissionNeeded), error: true)
            // Adds this app to the Accessibility list (toggled off) and opens the pane.
            TextSelection.requestPermission()
            watchPermission()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--config"), CommandLine.arguments.count > index + 1 {
            model.useConfig(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        } else { model.refresh() }
        if !model.menuBarOnlyMode {
            showWorkspace()
        }
    }

    private func buildPopover() {
        let controller = NSHostingController(rootView: MenuBarPopoverView(
            model: model,
            uiState: model.miniUIState,
            onOpenStudio: { [weak self] in
                self?.popover?.performClose(nil)
                self?.showWorkspace()
            },
            onOpenSettings: { [weak self] in
                self?.popover?.performClose(nil)
                self?.showWorkspace()
                self?.model.settingsVisible = true
            },
            onQuit: { NSApp.terminate(nil) }
        ))
        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentViewController = controller
        popover = pop
    }

    private func buildMenu() {
        let menu = NSMenu()
        for (title, selector) in [(L10n.text(.openWorkspace), #selector(openWorkspace)), (L10n.text(.readSelection), #selector(readSelection)), (L10n.text(.generateClipboard), #selector(readClipboard)), (L10n.text(.settingsMenu), #selector(settings)), (L10n.text(.quit), #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self
            menu.addItem(item)
        }
        statusMenu = menu
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        if let button = statusItem.button {
            button.image = makeFinchMenuBarIcon()
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem.menu = nil

        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let servicesItem = NSMenuItem(title: L10n.text(.services), action: nil, keyEquivalent: "")
        servicesItem.submenu = NSMenu(title: L10n.text(.services)); appMenu.addItem(servicesItem); NSApp.servicesMenu = servicesItem.submenu
        let quitItem = NSMenuItem(title: L10n.text(.quitApp), action: #selector(quit), keyEquivalent: "q"); quitItem.target = self; appMenu.addItem(quitItem)
        let editItem = NSMenuItem(); editItem.title = L10n.text(.edit); main.addItem(editItem)
        let edit = NSMenu(title: L10n.text(.edit)); editItem.submenu = edit
        for (title, action, key) in [(L10n.text(.undo), "undo:", "z"), (L10n.text(.cut), "cut:", "x"), (L10n.text(.copy), "copy:", "c"), (L10n.text(.paste), "paste:", "v"), (L10n.text(.selectAll), "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        NSApp.mainMenu = main
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            popover?.performClose(nil)
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc(generateEnglishPrompt:userData:error:)
    func generateEnglishPrompt(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = L10n.text(.selectFirst) as NSString; return
        }
        // Return immediately; asynchronous model calls must not block Services.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let capture = TextSelection.capture(expectedPID: frontPID, phase: "services").flatMap { $0.text == text ? $0 : nil }
        model.convert(text, sourcePID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                      sourceCapture: capture, anchor: nil)
    }

    func showWorkspace() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }

    private func applyWindowMode(mini: Bool, animated: Bool) {
        let targetSize = mini ? NSSize(width: 376, height: 470) : NSSize(width: 720, height: 520)
        window.minSize = mini ? NSSize(width: 356, height: 360) : NSSize(width: 660, height: 460)
        window.level = mini ? .floating : .normal
        let currentFrame = window.frame
        let contentFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))
        let newOrigin = NSPoint(x: currentFrame.minX, y: currentFrame.maxY - contentFrame.height)
        window.setFrame(NSRect(origin: newOrigin, size: contentFrame.size), display: true, animate: animated)
    }

    private func watchPermission() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, TextSelection.authorized else { return }
                self.permissionTimer?.invalidate(); self.permissionTimer = nil
                self.model.accessibilityGranted = true
                self.model.watcher.start()
                self.model.notify(L10n.text(.permissionActive))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }
    @objc private func openWorkspace() { showWorkspace() }
    @objc private func readSelection() { model.selection() }
    @objc private func readClipboard() { model.clipboard() }
    @objc private func settings() { showWorkspace(); model.settingsVisible = true }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWorkspace(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task {
            do {
                try await model.shutdown()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                model.notify(L10n.errorDescription(error), error: true)
                showWorkspace()
                terminationTask = nil
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        model.watcher.stop()
        model.cancel()
    }
}

#if !PROMPTFINCH_TESTS
@main
struct PromptSelectionApp {
    static func main() {
        let app = NSApplication.shared
        let menuBarOnly = UserDefaults.standard.bool(forKey: "menuBarOnlyMode")
        app.setActivationPolicy(menuBarOnly ? .accessory : .regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif
