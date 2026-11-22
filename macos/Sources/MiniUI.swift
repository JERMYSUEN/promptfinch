import AppKit
import SwiftUI

struct SessionHistoryEntry: Identifiable {
    let id = UUID()
    let original: String
    let result: PromptResult
    let createdAt = Date()
}

private let finchAccent = Color(red: 0.16, green: 0.43, blue: 0.90)

@MainActor
final class MiniUIState: ObservableObject {
    @Published var notesExpanded = false
    @Published var historyExpanded = false
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case model
    case triggers
    case privacy

    var id: String { rawValue }
    var titleKey: L10n.Key {
        switch self {
        case .general: return .tabGeneral
        case .model: return .tabModel
        case .triggers: return .tabTriggers
        case .privacy: return .tabPrivacy
        }
    }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .model: return "cpu"
        case .triggers: return "cursorarrow.click.2"
        case .privacy: return "lock.shield"
        }
    }
}

@MainActor
final class SettingsDraftState: ObservableObject {
    @Published var activeTab: SettingsTab = .model
    @Published var nativeEnabled: Bool = false
    @Published var selectedPreset: ProviderPreset = .deepseek
    @Published var baseURL: String = ProviderPreset.deepseek.defaultBaseURL
    @Published var modelName: String = ProviderPreset.deepseek.defaultModel
    @Published var apiKey: String = ""
    var preferNativeOnNextSync = false

    func sync(from model: WorkspaceModel) {
        nativeEnabled = preferNativeOnNextSync ? true : model.nativeConfig.enabled
        preferNativeOnNextSync = false
        selectedPreset = model.nativeConfig.preset
        baseURL = model.nativeConfig.baseURL
        modelName = model.nativeConfig.model
        apiKey = model.savedAPIKey(for: model.nativeConfig.preset)
    }

    func selectPreset(_ preset: ProviderPreset, model: WorkspaceModel) {
        selectedPreset = preset
        if preset != .custom {
            baseURL = preset.defaultBaseURL
            modelName = preset.defaultModel
        }
        apiKey = model.savedAPIKey(for: preset)
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var uiState: MiniUIState
    let onOpenStudio: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.config?.mode == "live" && model.config?.ready == true ? finchAccent : .orange)
                    .frame(width: 7, height: 7)
                Text("PromptFinch")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.compactStatusLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(action: onOpenStudio) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help(L10n.text(.openFullStudio))
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help(L10n.text(.settings))
                Button(action: onQuit) {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help(L10n.text(.quit))
            }

            HStack(spacing: 6) {
                Picker("", selection: $model.task) {
                    Text(L10n.text(.general)).tag("general")
                    Text(L10n.text(.writing)).tag("writing")
                    Text(L10n.text(.analysis)).tag("analysis")
                    Text(L10n.text(.coding)).tag("coding")
                    Text(L10n.text(.summary)).tag("summary")
                    Text(L10n.text(.marketing)).tag("marketing")
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 88)
                .disabled(model.unavailable)

                Picker("", selection: $model.refinementStyle) {
                    Text(L10n.text(.styleBalanced)).tag("balanced")
                    Text(L10n.text(.styleConcise)).tag("concise")
                    Text(L10n.text(.styleStructured)).tag("structured")
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 74)
                .disabled(model.unavailable)

                Picker("", selection: $model.promptLanguage) {
                    Text("EN").tag("en")
                    Text("繁中").tag("zh-Hant")
                }
                .labelsHidden()
                .controlSize(.small)
                .pickerStyle(.segmented)
                .frame(width: 76)
                .disabled(model.unavailable)

                Spacer(minLength: 4)

                Button { model.clipboard(openStudio: false) } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help(L10n.text(.readClipboard))
                .disabled(model.unavailable)

                Button { model.clear() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L10n.text(.clear))
            }

            if model.shouldShowQuickSetupBanner {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(finchAccent)
                    Text(L10n.text(.connectNativeAI))
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                    Button(L10n.text(.settings)) { onOpenSettings() }
                        .controlSize(.mini)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(finchAccent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            TextEditor(text: $model.original)
                .font(.system(size: 13))
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
                .frame(height: 82)
                .disabled(model.unavailable)

            HStack(spacing: 8) {
                Button { model.generate() } label: {
                    HStack(spacing: 6) {
                        if model.busy { ProgressView().controlSize(.small) }
                        Text(model.busy ? L10n.text(.generating) : L10n.text(.generate))
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .tint(finchAccent)
                .disabled(model.unavailable)
                .keyboardShortcut(.return, modifiers: .command)

                if model.busy {
                    Button(L10n.text(.cancel)) {
                        model.cancel()
                        model.notify(L10n.text(.cancelled))
                    }
                    .controlSize(.small)
                }
            }

            if let result = model.result {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(L10n.text(.copyablePrompt))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button { model.copy() } label: {
                            Label(L10n.text(.copy), systemImage: "doc.on.doc")
                                .font(.system(size: 11.5))
                        }
                        .controlSize(.small)
                    }

                    ScrollView {
                        Text(result.prompt)
                            .font(.system(size: 12.5))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 112)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.16)))

                    let notesCount = result.improvements.count + result.assumptions.count
                    if notesCount > 0 {
                        DisclosureGroup(
                            L10n.text(.notesSummary, String(notesCount)),
                            isExpanded: $uiState.notesExpanded
                        ) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(result.improvements.enumerated()), id: \.offset) { _, item in
                                        Text("• \(item)")
                                    }
                                    ForEach(Array(result.assumptions.enumerated()), id: \.offset) { _, item in
                                        Text("ⓘ \(item)").foregroundStyle(.secondary)
                                    }
                                }
                                .font(.system(size: 11))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                            }
                            .frame(maxHeight: 68)
                        }
                        .font(.system(size: 11.5, weight: .medium))
                    }
                }
            }

            if !model.sessionHistory.isEmpty {
                DisclosureGroup(
                    L10n.text(.recentSessionHistory),
                    isExpanded: $uiState.historyExpanded
                ) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(model.sessionHistory) { entry in
                            Button {
                                model.restoreSessionEntry(entry)
                            } label: {
                                Text(entry.original.replacingOccurrences(of: "\n", with: " "))
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 11.5))
            }

            if !model.message.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: model.isError ? "exclamationmark.circle" : "info.circle")
                        .font(.system(size: 11))
                    Text(model.message)
                        .font(.system(size: 11))
                        .lineLimit(2)
                }
                .foregroundStyle(model.isError ? Color.red : .secondary)
            }
        }
        .padding(12)
        .frame(width: 356)
        .environment(\.locale, Locale(identifier: model.language.rawValue))
    }
}

struct CompactSettingsView: View {
    @ObservedObject var model: WorkspaceModel
    @ObservedObject var draft: SettingsDraftState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        draft.activeTab = tab
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon).font(.system(size: 12))
                            Text(L10n.text(tab.titleKey)).font(.system(size: 12.5, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(draft.activeTab == tab ? finchAccent.opacity(0.16) : Color.clear)
                        .foregroundStyle(draft.activeTab == tab ? finchAccent : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch draft.activeTab {
                    case .general: generalTab
                    case .model: modelTab
                    case .triggers: triggersTab
                    case .privacy: privacyTab
                    }

                    if !model.message.isEmpty {
                        Text(model.message)
                            .font(.caption)
                            .foregroundStyle(model.isError ? Color.red : .secondary)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("settingsStatus")
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Text(model.modeLabel).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button(L10n.text(.done)) { model.settingsVisible = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(width: 520, height: min(460, (NSScreen.main?.visibleFrame.height ?? 760) - 120))
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { draft.sync(from: model) }
        .environment(\.locale, Locale(identifier: model.language.rawValue))
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(L10n.text(.interfaceLanguage), selection: $model.language) {
                ForEach(UILanguage.allCases) { language in
                    Text(language.name).tag(language)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("interfaceLanguage")

            Text(L10n.text(.languageHelp))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Divider()

            Picker(L10n.text(.outputPromptLanguage), selection: $model.promptLanguage) {
                Text(L10n.text(.promptLangEnglish)).tag("en")
                Text(L10n.text(.promptLangZhHant)).tag("zh-Hant")
            }
            .pickerStyle(.segmented)

            Divider()

            Toggle(L10n.text(.menuBarOnlyMode), isOn: $model.menuBarOnlyMode)
            Text(L10n.text(.menuBarOnlyHelp))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L10n.text(.engineModeHeading), selection: $draft.nativeEnabled) {
                Text(L10n.text(.engineNative)).tag(true)
                Text(L10n.text(.engineLegacy)).tag(false)
            }
            .pickerStyle(.segmented)
            .onReceive(draft.$nativeEnabled.dropFirst().removeDuplicates()) { enabled in
                if !enabled && model.nativeConfig.enabled {
                    var updated = model.nativeConfig
                    updated.enabled = false
                    model.saveNativeProvider(updated, apiKey: nil)
                }
            }

            if draft.nativeEnabled {
                Picker(L10n.text(.providerPresetLabel), selection: $draft.selectedPreset) {
                    ForEach(ProviderPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onReceive(draft.$selectedPreset.dropFirst().removeDuplicates()) { preset in
                    draft.selectPreset(preset, model: model)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(.providerBaseURLLabel)).font(.caption).foregroundStyle(.secondary)
                    TextField("https://api.deepseek.com", text: $draft.baseURL).textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(.providerModelLabel)).font(.caption).foregroundStyle(.secondary)
                    TextField("deepseek-chat", text: $draft.modelName).textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text(.providerAPIKeyLabel)).font(.caption).foregroundStyle(.secondary)
                    SecureField(L10n.text(.providerAPIKeyPlaceholder), text: $draft.apiKey).textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 10) {
                    Button(L10n.text(.saveAndActivate)) {
                        let updated = NativeProviderConfig(
                            enabled: true,
                            demoMode: false,
                            preset: draft.selectedPreset,
                            baseURL: draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                            model: draft.modelName.trimmingCharacters(in: .whitespacesAndNewlines),
                            jsonMode: model.nativeConfig.jsonMode,
                            thinkingMode: model.nativeConfig.thinkingMode,
                            timeoutSeconds: model.nativeConfig.timeoutSeconds
                        )
                        model.saveNativeProvider(updated, apiKey: draft.apiKey)
                        model.notify(L10n.text(.nativeProviderSaved, updated.preset.displayName))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(finchAccent)
                    .disabled(model.unavailable)

                    Button(L10n.text(.testConnection)) {
                        let updated = NativeProviderConfig(
                            enabled: true,
                            demoMode: false,
                            preset: draft.selectedPreset,
                            baseURL: draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                            model: draft.modelName.trimmingCharacters(in: .whitespacesAndNewlines),
                            jsonMode: model.nativeConfig.jsonMode,
                            thinkingMode: model.nativeConfig.thinkingMode,
                            timeoutSeconds: model.nativeConfig.timeoutSeconds
                        )
                        model.saveNativeProvider(updated, apiKey: draft.apiKey)
                        model.testNativeProviderConnection()
                    }
                    .disabled(model.unavailable)

                    Button(L10n.text(.useNativeDemo)) {
                        model.enableNativeDemo()
                    }
                    .disabled(model.unavailable)
                }

                Text(L10n.text(.providerKeychainNote))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.text(.modelSettingsHelp))
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(model.backend.configurationPath.isEmpty ? L10n.text(.usingDemo) : L10n.text(.configFile, URL(fileURLWithPath: model.backend.configurationPath).lastPathComponent))
                        .font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    Button(L10n.text(.chooseEnv)) { chooseConfig() }.disabled(model.unavailable)
                }
                HStack {
                    Button(L10n.text(.editModelConfig)) { createConfig() }
                    Button(L10n.text(.reloadConfig)) { model.restart() }
                    Button(L10n.text(.useDemo)) { model.useConfig(nil) }
                }.disabled(model.unavailable)
                Divider()
                HStack {
                    Text(L10n.text(.runtime)).font(.system(size: 12))
                    Spacer()
                    Button(L10n.text(.chooseNode)) { chooseNode() }.disabled(model.unavailable)
                }
                HStack {
                    Button(L10n.text(.useBundledBackend)) { model.useBundledBackend() }
                        .disabled(model.unavailable).accessibilityIdentifier("useBundledBackend")
                    if model.backendSwitching { ProgressView().controlSize(.small) }
                }
                Text(L10n.text(.bundledBackendHelp))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var triggersTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.text(.globalShortcut)).font(.headline)
            Text(L10n.text(.permissionHelp, L10n.text(model.accessibilityGranted ? .permissionGranted : .permissionMissing)))
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L10n.text(.openAccessibility)) {
                    TextSelection.requestPermission()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button(L10n.text(.recheckPermission)) {
                    model.accessibilityGranted = TextSelection.authorized
                    model.watcher.start()
                }
            }
            Divider()
            Toggle(L10n.text(.showFloatingButton), isOn: $model.watcherLeft)
            Toggle(L10n.text(.showRightClickMenu), isOn: $model.watcherRight)
            Toggle(L10n.text(.autoPaste), isOn: $model.pasteBackEnabled)
            Toggle(L10n.text(.appAwarePresets), isOn: $model.appAwarePresetsEnabled)
            Text(L10n.text(.appAwarePresetsHelp))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L10n.text(.terminalHelp))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var privacyTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(L10n.text(.redactSecretsToggle), isOn: $model.redactSecretsEnabled)
            Text(L10n.text(.redactSecretsHelp))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text(L10n.text(.privacyZeroDiskHeading)).font(.headline)
            Text(L10n.text(.localPrivacy))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L10n.text(.providerKeychainNote))
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
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
