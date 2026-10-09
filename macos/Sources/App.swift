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
    @Published var task = UserDefaults.standard.string(forKey: "task") ?? "general"
    @Published var targetModel = UserDefaults.standard.string(forKey: "targetModel") ?? ""
    @Published var result: PromptResult?
    @Published var busy = false
    @Published var message = ""
    @Published var isError = false
    @Published var config: ServiceConfig?
    @Published var settingsVisible = false
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
    let backend = LocalBackend()
    let watcher = SelectionWatcher()
    let resultPanel = ResultPanel()
    @Published var pasteBackEnabled: Bool = SelectionWatcher.pasteBack {
        didSet { UserDefaults.standard.set(pasteBackEnabled, forKey: SelectionWatcher.pasteBackKey) }
    }
    private var sourcePID: pid_t?
    private var sourceCapture: SelectionCapture?
    private var activeEventSequence: UInt64?
    private var operation: Task<Void, Never>?
    private var generationID = UUID()
    private var pasteFeedbackID = UUID()
    private let pasteOperations: PasteOperations
    var showWindow: (() -> Void)?

    init(pasteOperations: PasteOperations? = nil) {
        self.pasteOperations = pasteOperations ?? SystemPasteOperations()
        resultPanel.onPasteBack = { [weak self] in self?.pasteBackFromPanel() }
        resultPanel.onCopy = { [weak self] in self?.copyFromPanel() }
        resultPanel.onClose = { [weak self] in self?.closeResultPanel() }
    }

    var modeLabel: String {
        guard let config else { return L10n.text(.connecting) }
        if config.mode == "mock" { return L10n.text(.mockMode) }
        if !config.ready { return L10n.text(.incompleteConfig) }
        return L10n.text(.liveMode, config.generationModel ?? L10n.text(.configuredModel))
    }

    func refresh() {
        Task {
            do { config = try await backend.ensureRunning() }
            catch { notify(L10n.errorDescription(error), error: true) }
        }
    }

    func notify(_ text: String, error: Bool = false) { message = text; isError = error }

    func receive(_ text: String, generateImmediately: Bool = true) {
        clear()
        original = text
        sourcePID = nil
        sourceCapture = nil
        showWindow?()
        if generateImmediately { generate() }
    }

    // One-click conversion from the floating bar, hotkey or Services: stays
    // in the background so the source app keeps focus. The generated prompt is
    // shown in a floating result window next to the selection, never in a
    // suddenly-raised main window.
    func convert(_ text: String, sourcePID: pid_t?, sourceCapture: SelectionCapture? = nil,
                 anchor: CGPoint? = nil, eventSequence: UInt64? = nil) {
        clear()
        original = text
        self.sourcePID = sourcePID
        self.sourceCapture = sourceCapture
        activeEventSequence = eventSequence
        DebugLog.write("convert seq=\(eventSequence.map(String.init) ?? "-") sourcePID=\(sourcePID.map(String.init) ?? "nil") selectedUTF16=\(text.utf16.count)")
        generate(autoPaste: true, background: true, anchor: anchor ?? mouseAnchor)
    }

    private var mouseAnchor: CGPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        return CGPoint(x: mouse.x, y: (screen?.frame.maxY ?? 0) - mouse.y)
    }

    func setWatcher(left: Bool, right: Bool) {
        UserDefaults.standard.set(left, forKey: SelectionWatcher.leftKey)
        UserDefaults.standard.set(right, forKey: SelectionWatcher.rightKey)
        watcher.invalidatePendingActions()
    }

    func clipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showWindow?(); notify(L10n.text(.emptyClipboard), error: true); return
        }
        receive(text)
    }

    func selection() {
        do {
            let capture = try TextSelection.readCapture()
            convert(capture.text, sourcePID: capture.pid, sourceCapture: capture,
                    anchor: capture.bounds.map { TextSelection.topLeftPoint(from: $0) })
        } catch { showWindow?(); notify(L10n.errorDescription(error), error: true) }
    }

    func generate(autoPaste: Bool = false, background: Bool = false, anchor: CGPoint? = nil) {
        let input = PromptRequest(prompt: original, task: task, targetModel: targetModel)
        let eventID = activeEventSequence.map(String.init) ?? "-"
        do { try input.validate() }
        catch {
            notify(L10n.errorDescription(error), error: true)
            if background { resultPanel.fail(status: L10n.errorDescription(error), eventSequence: activeEventSequence) }
            else if autoPaste { showWindow?() }
            return
        }
        cancel()
        let token = UUID()
        generationID = token
        result = nil; busy = true; notify(L10n.text(.refining))
        DebugLog.write("generate seq=\(eventID) started background=\(background) selectedUTF16=\(input.prompt.utf16.count)")
        if background { resultPanel.present(anchor: anchor ?? mouseAnchor, eventSequence: activeEventSequence) }
        UserDefaults.standard.set(task, forKey: "task")
        UserDefaults.standard.set(targetModel, forKey: "targetModel")
        operation = Task {
            do {
                config = try await backend.ensureRunning()
                try Task.checkCancellation()
                DebugLog.write("generate seq=\(eventID) backend=ready request=sent")
                let output = try await backend.client.optimize(input)
                DebugLog.write("generate seq=\(eventID) done mode=\(output.mode) generatedUTF16=\(output.prompt.utf16.count)")
                guard generationID == token, !Task.isCancelled else { return }
                result = output
                if output.mode == "mock" {
                    notify(L10n.text(.mockNotice))
                    if background {
                        resultPanel.finish(prompt: output.prompt, status: L10n.text(.mockPanelNotice), canPasteBack: false, error: true, eventSequence: activeEventSequence)
                    } else if autoPaste { showWindow?() }
                } else if autoPaste {
                    pasteBack(output.prompt)
                } else {
                    notify(L10n.text(.promptReady))
                    if background { resultPanel.finish(prompt: output.prompt, status: L10n.text(.promptComplete), canPasteBack: canOfferPasteBack, error: false, eventSequence: activeEventSequence) }
                }
            } catch {
                DebugLog.write("generate seq=\(eventID) errorType=\(String(describing: type(of: error)))")
                guard generationID == token, !Task.isCancelled else { return }
                if let networkError = error as? URLError, networkError.code == .cannotConnectToHost {
                    notify(L10n.text(.cannotConnect), error: true)
                } else { notify(L10n.errorDescription(error), error: true) }
                if background { resultPanel.fail(status: L10n.errorDescription(error), eventSequence: activeEventSequence) } else if autoPaste { showWindow?() }
            }
            if generationID == token { busy = false; operation = nil }
        }
    }

    private func pasteBack(_ prompt: String) {
        guard pasteBackEnabled, TextSelection.authorized else {
            let copied = pasteOperations.copy(prompt)
            DebugLog.write("pasteBack skipped: enabled=\(pasteBackEnabled) authorized=\(TextSelection.authorized)")
            let status = copied
                ? L10n.text(TextSelection.authorized ? .autoPasteOffCopied : .pastePermissionCopied)
                : L10n.text(.copyFailedPanel)
            notify(status, error: !copied)
            resultPanel.finish(prompt: prompt,
                               status: copied && canOfferPasteBack ? L10n.text(.manualPasteHelp) : status,
                               canPasteBack: canOfferPasteBack, error: !copied, eventSequence: activeEventSequence)
            return
        }
        requestPasteBack(prompt)
    }

    private var canOfferPasteBack: Bool {
        TextSelection.authorized && sourceCapture?.hasReliableRange == true
    }

    private func requestPasteBack(_ prompt: String) {
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
            resultPanel.finish(prompt: prompt, status: status, canPasteBack: false, error: false, eventSequence: activeEventSequence)
        case .notAttempted:
            let copied = pasteOperations.copy(prompt)
            let status = L10n.text(copied ? .unsafeTargetCopied : .unsafePasteFailed)
            notify(status, error: !copied)
            resultPanel.finish(prompt: prompt, status: status, canPasteBack: false, error: !copied, eventSequence: activeEventSequence)
        case .clipboardUnavailable:
            // An unsafe snapshot or failed recovery must not be followed by an
            // automatic copy that overwrites the clipboard we tried to protect.
            let status = L10n.text(.clipboardUnavailable)
            notify(status, error: true)
            resultPanel.finish(prompt: prompt, status: status, canPasteBack: false, error: true, eventSequence: activeEventSequence)
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
                           canPasteBack: false, error: !copied, eventSequence: activeEventSequence)
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

    func cancel() {
        invalidatePendingPasteFeedback()
        generationID = UUID()
        operation?.cancel(); operation = nil; busy = false
    }

    func invalidatePendingPasteFeedback() { pasteFeedbackID = UUID() }

    func clear() {
        cancel()
        resultPanel.orderOut(nil)
        original = ""
        result = nil
        sourcePID = nil
        sourceCapture = nil
        activeEventSequence = nil
        notify("")
    }

    func useConfig(_ url: URL?) {
        cancel(); config = nil
        Task {
            do { config = try await backend.selectConfiguration(url); notify(L10n.text(.configLoaded)) }
            catch { notify(L10n.errorDescription(error), error: true) }
        }
    }

    func restart() {
        cancel(); config = nil; backend.stop(); refresh()
    }
}

private let accent = Color(red: 0.14, green: 0.39, blue: 0.31)

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(.workspaceTitle)).font(.system(size: 25, weight: .semibold))
                    Text(L10n.text(.workspaceIntro))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.settingsVisible = true } label: { Label(L10n.text(.settings), systemImage: "gearshape") }
                    .accessibilityIdentifier("settings")
            }
            HStack(spacing: 8) {
                Circle().fill(model.config?.mode == "live" && model.config?.ready == true ? accent : .orange).frame(width: 7, height: 7)
                Text(model.modeLabel).font(.system(size: 12, weight: .medium))
                Spacer()
                Text(L10n.text(.memoryOnly)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text(.original)).font(.headline)
                    TextEditor(text: $model.original).font(.system(size: 14))
                        .padding(8).background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
                        .frame(minHeight: 190)
                        .disabled(model.busy).accessibilityIdentifier("originalPrompt")
                    HStack {
                        Picker(L10n.text(.purpose), selection: $model.task) {
                            Text(L10n.text(.general)).tag("general"); Text(L10n.text(.writing)).tag("writing"); Text(L10n.text(.analysis)).tag("analysis")
                            Text(L10n.text(.coding)).tag("coding"); Text(L10n.text(.summary)).tag("summary"); Text(L10n.text(.marketing)).tag("marketing")
                        }.frame(maxWidth: 185)
                        Spacer()
                        Text("\(model.original.utf16.count) / 12,000").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.disabled(model.busy)
                    TextField(L10n.text(.targetPlaceholder), text: $model.targetModel).textFieldStyle(.roundedBorder).disabled(model.busy)
                    HStack {
                        Button { model.clipboard() } label: { Label(L10n.text(.readClipboard), systemImage: "doc.on.clipboard") }.disabled(model.busy)
                        Spacer()
                        Button(L10n.text(.clear)) { model.clear() }.accessibilityIdentifier("clear")
                    }
                    Button { model.generate() } label: {
                        HStack { if model.busy { ProgressView().controlSize(.small) }; Text(model.busy ? L10n.text(.generating) : L10n.text(.generate)).fontWeight(.semibold) }
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).tint(accent).disabled(model.busy)
                        .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("generate")
                    Text(L10n.text(.privacy))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(minWidth: 285, maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.text(.copyablePrompt)).font(.headline)
                        Spacer()
                        Button { model.copy() } label: { Label(L10n.text(.copy), systemImage: "doc.on.doc") }
                            .disabled(model.result == nil).accessibilityIdentifier("copyPrompt")
                    }
                    if let result = model.result {
                        Text(result.mode == "mock" ? L10n.text(.mockResult) : L10n.text(.generatedBy, result.generationModel ?? L10n.text(.modelService)))
                            .font(.system(size: 11)).foregroundStyle(result.mode == "mock" ? Color.orange : .secondary)
                    }
                    ScrollView {
                        Text(model.result?.prompt ?? L10n.text(.resultPlaceholder))
                            .font(.system(size: 14)).foregroundStyle(model.result == nil ? .secondary : .primary)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .accessibilityIdentifier("resultPrompt")
                    }.frame(minHeight: 255, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
                    if let result = model.result {
                        DisclosureGroup(L10n.text(.improvements)) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(result.improvements.enumerated()), id: \.offset) { _, item in Text("• \(item)") }
                                    if !result.assumptions.isEmpty {
                                        Text(L10n.text(.assumptions)).fontWeight(.semibold).padding(.top, 6)
                                        ForEach(Array(result.assumptions.enumerated()), id: \.offset) { _, item in Text("• \(item)") }
                                    }
                                }.font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            }.frame(maxHeight: 125)
                        }.font(.system(size: 12))
                    }
                }.frame(minWidth: 330, maxWidth: .infinity)
            }
            HStack(spacing: 10) {
                if !model.message.isEmpty {
                    Image(systemName: model.isError ? "exclamationmark.circle" : "info.circle")
                    Text(model.message).font(.system(size: 12)).textSelection(.enabled).accessibilityIdentifier("statusMessage")
                }
                Spacer()
                if model.busy { Button(L10n.text(.cancel)) { model.cancel(); model.notify(L10n.text(.cancelled)) } }
            }.foregroundStyle(model.isError ? Color.red : .secondary).frame(minHeight: 30)
        }.padding(24).frame(minWidth: 760, minHeight: 620).background(Color(nsColor: .windowBackgroundColor))
            .sheet(isPresented: $model.settingsVisible) { SettingsView(model: model) }
            .environment(\.locale, Locale(identifier: model.language.rawValue))
            .onChange(of: model.original) { _ in
                if model.result != nil { model.invalidatePendingPasteFeedback(); model.notify(L10n.text(.originalChanged)) }
            }
            .onChange(of: model.task) { _ in
                if model.result != nil { model.invalidatePendingPasteFeedback(); model.notify(L10n.text(.purposeChanged)) }
            }
            .onChange(of: model.targetModel) { _ in
                if model.result != nil { model.invalidatePendingPasteFeedback(); model.notify(L10n.text(.targetChanged)) }
            }
    }
}

struct SettingsView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var permission = TextSelection.authorized
    @State private var watcherLeft = SelectionWatcher.leftTrigger
    @State private var watcherRight = SelectionWatcher.rightTrigger

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L10n.text(.settingsTitle)).font(.title2).fontWeight(.semibold)
                    Picker(L10n.text(.interfaceLanguage), selection: $model.language) {
                        ForEach(UILanguage.allCases) { language in
                            Text(language.name).tag(language)
                        }
                    }.pickerStyle(.menu).accessibilityIdentifier("interfaceLanguage")
                    Text(L10n.text(.languageHelp))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Text(L10n.text(.modelSettingsHelp))
                        .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(model.backend.configurationPath.isEmpty ? L10n.text(.usingDemo) : L10n.text(.configFile, URL(fileURLWithPath: model.backend.configurationPath).lastPathComponent))
                            .font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Button(L10n.text(.chooseEnv)) { chooseConfig() }
                    }
                    HStack {
                        Button(L10n.text(.editModelConfig)) { createConfig() }
                        Button(L10n.text(.reloadConfig)) { model.restart() }
                        Button(L10n.text(.useDemo)) { model.useConfig(nil) }
                    }
                    Divider()
                    Text(L10n.text(.globalShortcut)).font(.headline)
                    Text(L10n.text(.permissionHelp, L10n.text(permission ? .permissionGranted : .permissionMissing)))
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(L10n.text(.openAccessibility)) {
                            TextSelection.requestPermission()
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                        Button(L10n.text(.recheckPermission)) {
                            permission = TextSelection.authorized
                            model.watcher.start()
                        }
                    }
                    Divider()
                    Text(L10n.text(.selectionHeading)).font(.headline)
                    Toggle(L10n.text(.showFloatingButton), isOn: $watcherLeft)
                        .onChange(of: watcherLeft) { _ in model.setWatcher(left: watcherLeft, right: watcherRight) }
                    Toggle(L10n.text(.showRightClickMenu), isOn: $watcherRight)
                        .onChange(of: watcherRight) { _ in model.setWatcher(left: watcherLeft, right: watcherRight) }
                    Text(L10n.text(.explicitActionHelp))
                        .font(.caption).foregroundColor(.secondary)
                    Toggle(L10n.text(.autoPaste), isOn: $model.pasteBackEnabled)
                    Text(L10n.text(.selectionHelp))
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    HStack {
                        Text(L10n.text(.runtime)).font(.system(size: 12))
                        Spacer()
                        Button(L10n.text(.chooseNode)) { chooseNode() }
                    }
                    Text(L10n.text(.localPrivacy))
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(24)
            }
            Divider()
            HStack { Spacer(); Button(L10n.text(.done)) { model.settingsVisible = false }.keyboardShortcut(.defaultAction) }
                .padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(width: 610, height: min(720, (NSScreen.main?.visibleFrame.height ?? 820) - 100))
    }

    private func chooseConfig() {
        let panel = NSOpenPanel()
        panel.title = L10n.text(.chooseConfigTitle); panel.showsHiddenFiles = true
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.useConfig(url) }
    }

    private func chooseNode() {
        let panel = NSOpenPanel(); panel.title = L10n.text(.chooseNodeTitle)
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.backend.setNode(url); model.restart() }
    }

    private func createConfig() {
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("PromptSelection", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent("settings.env")
            if !FileManager.default.fileExists(atPath: destination.path) {
                guard let template = Bundle.main.url(forResource: "deepseek", withExtension: "env.example") else { throw ToolError.message(L10n.text(.missingTemplate)) }
                try FileManager.default.copyItem(at: template, to: destination)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
            if let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
                NSWorkspace.shared.open([destination], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            } else { NSWorkspace.shared.open(destination) }
            model.useConfig(destination)
        } catch { model.notify(L10n.errorDescription(error), error: true) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = WorkspaceModel()
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private let hotKey = SelectionHotKey()
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 940, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "PromptFinch"
        window.minSize = NSSize(width: 800, height: 670)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: WorkspaceView(model: model))
        window.center()
        model.showWindow = { [weak self] in self?.showWorkspace() }
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
        model.watcher.canStartConversion = { [weak model] in model?.busy != true }
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
        showWorkspace()
    }

    private func buildMenu() {
        let menu = NSMenu()
        for (title, selector) in [(L10n.text(.openWorkspace), #selector(openWorkspace)), (L10n.text(.readSelection), #selector(readSelection)), (L10n.text(.generateClipboard), #selector(readClipboard)), (L10n.text(.settingsMenu), #selector(settings)), (L10n.text(.quit), #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self
            menu.addItem(item)
        }
        if statusItem == nil { statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength) }
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "PromptFinch")
        statusItem.menu = menu

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

    private func watchPermission() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, TextSelection.authorized else { return }
                self.permissionTimer?.invalidate(); self.permissionTimer = nil
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
    func applicationWillTerminate(_ notification: Notification) {
        model.watcher.stop()
        model.cancel()
        model.backend.stop()
    }
}

#if !PROMPTFINCH_TESTS
@main
struct PromptSelectionApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif
