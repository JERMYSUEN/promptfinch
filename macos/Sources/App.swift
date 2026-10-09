import AppKit
import SwiftUI

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
    var showWindow: (() -> Void)?

    init() {
        resultPanel.onPasteBack = { [weak self] in self?.pasteBackFromPanel() }
        resultPanel.onCopy = { [weak self] in self?.copyFromPanel() }
        resultPanel.onClose = { [weak self] in self?.closeResultPanel() }
    }

    var modeLabel: String {
        guard let config else { return "正在連接本機服務…" }
        if config.mode == "mock" { return "示範模式 · 原文未經優化" }
        if !config.ready { return "模型設定未完成" }
        return "模型模式 · \(config.generationModel ?? "已設定模型")"
    }

    func refresh() {
        Task {
            do { config = try await backend.ensureRunning() }
            catch { notify(error.localizedDescription, error: true) }
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
    }

    func clipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showWindow?(); notify("剪貼簿沒有文字，請先複製需求。", error: true); return
        }
        receive(text)
    }

    func selection() {
        do {
            let capture = try TextSelection.readCapture()
            convert(capture.text, sourcePID: capture.pid, sourceCapture: capture,
                    anchor: capture.bounds.map { TextSelection.topLeftPoint(from: $0) })
        } catch { showWindow?(); notify(error.localizedDescription, error: true) }
    }

    func generate(autoPaste: Bool = false, background: Bool = false, anchor: CGPoint? = nil) {
        let input = PromptRequest(prompt: original, task: task, targetModel: targetModel)
        let eventID = activeEventSequence.map(String.init) ?? "-"
        do { try input.validate() }
        catch {
            notify(error.localizedDescription, error: true)
            if background { resultPanel.fail(status: error.localizedDescription, eventSequence: activeEventSequence) }
            else if autoPaste { showWindow?() }
            return
        }
        cancel()
        let token = UUID()
        generationID = token
        result = nil; busy = true; notify("正在整理英文 Prompt…")
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
                    notify("示範模式：只顯示固定範本，原文未經語意優化，也未貼回來源輸入框。請設定模型後再使用。")
                    if background {
                        resultPanel.finish(prompt: output.prompt, status: "示範模式：這不是生成結果；請在設定中完成模型設定。", canPasteBack: false, error: true, eventSequence: activeEventSequence)
                    } else if autoPaste { showWindow?() }
                } else if autoPaste {
                    pasteBack(output.prompt)
                } else {
                    notify("英文 Prompt 已完成，可以複製使用。")
                    if background { resultPanel.finish(prompt: output.prompt, status: "英文 Prompt 已完成。", canPasteBack: sourceCapture != nil, error: false, eventSequence: activeEventSequence) }
                }
            } catch {
                DebugLog.write("generate seq=\(eventID) errorType=\(String(describing: type(of: error)))")
                guard generationID == token, !Task.isCancelled else { return }
                if let networkError = error as? URLError, networkError.code == .cannotConnectToHost {
                    notify("無法連接本機後端，請在設定中重新啟動。", error: true)
                } else { notify(error.localizedDescription, error: true) }
                if background { resultPanel.fail(status: error.localizedDescription, eventSequence: activeEventSequence) } else if autoPaste { showWindow?() }
            }
            if generationID == token { busy = false; operation = nil }
        }
    }

    private func pasteBack(_ prompt: String) {
        guard pasteBackEnabled, TextSelection.authorized else {
            let copied = PasteBack.write(prompt)
            DebugLog.write("pasteBack skipped: enabled=\(pasteBackEnabled) authorized=\(TextSelection.authorized)")
            let status = copied
                ? "英文 Prompt 已完成並複製；自動貼回已關閉，請自行 ⌘V。"
                : "英文 Prompt 已完成，但複製失敗；請在結果窗選取文字後按 ⌘C。"
            notify(status, error: !copied)
            resultPanel.finish(prompt: prompt,
                               status: copied ? "已複製；自動貼回已關閉，可按「貼回原文」或自行 ⌘V。" : status,
                               canPasteBack: sourceCapture != nil, error: !copied, eventSequence: activeEventSequence)
            return
        }
        if PasteBack.paste(prompt, expectedTarget: sourceCapture) {
            DebugLog.write("pasteBack ok")
            notify("英文 Prompt 已取代來源輸入框中的選取文字；原剪貼簿已還原。")
            resultPanel.finish(prompt: prompt, status: "已自動貼回，取代來源輸入框中的選取文字。", canPasteBack: false, error: false, eventSequence: activeEventSequence)
        } else {
            let copied = PasteBack.write(prompt)
            DebugLog.write("pasteBack fallback copy: sourcePID=\(sourcePID.map(String.init) ?? "nil")")
            let reason = sourceCapture == nil ? "無法確認來源輸入框與選取位置" : "來源輸入框或選取內容已改變"
            let status = copied
                ? "\(reason)，為避免貼錯位置，Prompt 已複製，請自行 ⌘V。"
                : "\(reason)，且複製失敗；請在結果窗選取文字後按 ⌘C。"
            notify(status, error: true)
            resultPanel.finish(prompt: prompt, status: status, canPasteBack: false, error: true, eventSequence: activeEventSequence)
        }
    }

    // Result window buttons.
    func pasteBackFromPanel() {
        guard let result else { return }
        if TextSelection.authorized, PasteBack.paste(result.prompt, expectedTarget: sourceCapture) {
            notify("英文 Prompt 已貼回來源輸入框。")
            resultPanel.finish(prompt: result.prompt, status: "已貼回，取代來源輸入框中的選取文字。", canPasteBack: false, error: false, eventSequence: activeEventSequence)
        } else {
            let copied = PasteBack.write(result.prompt)
            let status = copied
                ? "來源輸入框或選取內容已改變；為避免貼錯位置，已複製，請自行 ⌘V。"
                : "無法安全貼回且複製失敗；請在結果窗選取文字後按 ⌘C。"
            notify(status, error: true)
            resultPanel.finish(prompt: result.prompt, status: status, canPasteBack: false, error: true, eventSequence: activeEventSequence)
        }
    }

    func copyFromPanel() {
        guard let result else { return }
        let copied = PasteBack.write(result.prompt)
        let status = copied ? "已複製 Prompt。" : "複製失敗，請選取結果後按 ⌘C。"
        notify(status, error: !copied)
        resultPanel.finish(prompt: result.prompt, status: copied ? "已複製到剪貼簿。" : status,
                           canPasteBack: false, error: !copied, eventSequence: activeEventSequence)
    }

    func closeResultPanel() {
        if busy { cancel(); notify("已取消生成。") }
        DebugLog.write("resultPanel seq=\(activeEventSequence.map(String.init) ?? "-") hidden=close-button")
        resultPanel.orderOut(nil)
    }

    func copy() {
        guard let result else { return }
        if PasteBack.write(result.prompt) { notify("已複製 Prompt，未包含優化說明。") }
        else { notify("複製失敗，請在結果區選取文字後按 ⌘C。", error: true) }
    }

    func cancel() {
        generationID = UUID()
        operation?.cancel(); operation = nil; busy = false
    }

    func clear() {
        cancel()
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
            do { config = try await backend.selectConfiguration(url); notify("模型設定已載入。") }
            catch { notify(error.localizedDescription, error: true) }
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
                    Text("多語言原文 → 英文 Prompt").font(.system(size: 25, weight: .semibold))
                    Text("可選取或貼上任何語言的文字。生成指令一律使用英文；原文指定的答案語言會保留，已是英文的指令會直接整理。")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.settingsVisible = true } label: { Label("設定", systemImage: "gearshape") }
                    .accessibilityIdentifier("settings")
            }
            HStack(spacing: 8) {
                Circle().fill(model.config?.mode == "live" && model.config?.ready == true ? accent : .orange).frame(width: 7, height: 7)
                Text(model.modeLabel).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("內容僅在記憶體中保留").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("原始需求").font(.headline)
                    TextEditor(text: $model.original).font(.system(size: 14))
                        .padding(8).background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
                        .frame(minHeight: 190)
                        .disabled(model.busy).accessibilityIdentifier("originalPrompt")
                    HStack {
                        Picker("用途", selection: $model.task) {
                            Text("通用").tag("general"); Text("寫作").tag("writing"); Text("分析").tag("analysis")
                            Text("程式開發").tag("coding"); Text("摘要").tag("summary"); Text("行銷").tag("marketing")
                        }.frame(maxWidth: 185)
                        Spacer()
                        Text("\(model.original.utf16.count) / 12,000").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.disabled(model.busy)
                    TextField("目標模型（選填，例如 Claude）", text: $model.targetModel).textFieldStyle(.roundedBorder).disabled(model.busy)
                    HStack {
                        Button { model.clipboard() } label: { Label("讀取剪貼簿", systemImage: "doc.on.clipboard") }.disabled(model.busy)
                        Spacer()
                        Button("清除") { model.clear() }.accessibilityIdentifier("clear")
                    }
                    Button { model.generate() } label: {
                        HStack { if model.busy { ProgressView().controlSize(.small) }; Text(model.busy ? "生成中…" : "生成英文 Prompt").fontWeight(.semibold) }
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).tint(accent).disabled(model.busy)
                        .keyboardShortcut(.return, modifiers: .command).accessibilityIdentifier("generate")
                    Text("執行生成或轉換後才會傳至你設定的模型服務；不保存需求或結果。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(minWidth: 285, maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("可複製的 Prompt").font(.headline)
                        Spacer()
                        Button { model.copy() } label: { Label("複製", systemImage: "doc.on.doc") }
                            .disabled(model.result == nil).accessibilityIdentifier("copyPrompt")
                    }
                    if let result = model.result {
                        Text(result.mode == "mock" ? "示範結果 · 未經語意優化" : "生成來源：\(result.generationModel ?? "模型服務")")
                            .font(.system(size: 11)).foregroundStyle(result.mode == "mock" ? Color.orange : .secondary)
                    }
                    ScrollView {
                        Text(model.result?.prompt ?? "英文 Prompt 會顯示在這裡。\n\n只會整理指令，不會代你執行原始任務。")
                            .font(.system(size: 14)).foregroundStyle(model.result == nil ? .secondary : .primary)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .accessibilityIdentifier("resultPrompt")
                    }.frame(minHeight: 255, maxHeight: .infinity)
                        .background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.15)))
                    if let result = model.result {
                        DisclosureGroup("優化重點與假設") {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(result.improvements.enumerated()), id: \.offset) { _, item in Text("• \(item)") }
                                    if !result.assumptions.isEmpty {
                                        Text("非關鍵假設（獨立說明，不另附於 Prompt）").fontWeight(.semibold).padding(.top, 6)
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
                if model.busy { Button("取消") { model.cancel(); model.notify("已取消生成。") } }
            }.foregroundStyle(model.isError ? Color.red : .secondary).frame(minHeight: 30)
        }.padding(24).frame(minWidth: 760, minHeight: 620).background(Color(nsColor: .windowBackgroundColor))
            .sheet(isPresented: $model.settingsVisible) { SettingsView(model: model) }
            .onChange(of: model.original) { _ in
                if model.result != nil { model.notify("原始需求已變更，請重新生成；右側仍是上次結果。") }
            }
            .onChange(of: model.task) { _ in
                if model.result != nil { model.notify("用途已變更，請重新生成；右側仍是上次結果。") }
            }
            .onChange(of: model.targetModel) { _ in
                if model.result != nil { model.notify("目標模型已變更，請重新生成；右側仍是上次結果。") }
            }
    }
}

struct SettingsView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var permission = TextSelection.authorized
    @State private var watcherLeft = SelectionWatcher.leftTrigger
    @State private var watcherRight = SelectionWatcher.rightTrigger

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("模型與取字設定").font(.title2).fontWeight(.semibold)
            Text("使用伺服器 .env 設定 DeepSeek 或其他相容模型。金鑰由 Node.js 後端讀取，不會複製進 App。")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(model.backend.configurationPath.isEmpty ? "目前使用示範模式" : "設定檔：\(URL(fileURLWithPath: model.backend.configurationPath).lastPathComponent)")
                    .font(.system(size: 12)).lineLimit(1)
                Spacer()
                Button("選擇 .env…") { chooseConfig() }
            }
            HStack {
                Button("建立 / 編輯模型設定") { createConfig() }
                Button("重新載入設定") { model.restart() }
                Button("使用示範模式") { model.useConfig(nil) }
            }
            Divider()
            Text("全域快捷鍵：⌥⌘P").font(.headline)
            Text("\(permission ? "輔助使用權限已開啟。" : "快捷鍵與浮動按鈕尚未取得輔助使用權限。")右鍵「服務」不需要這項權限。少數軟體不提供選取文字，可改用剪貼簿。")
                .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("開啟輔助使用設定") {
                    TextSelection.requestPermission()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("重新檢查權限") {
                    permission = TextSelection.authorized
                    model.watcher.start()
                }
            }
            Divider()
            Text("一鍵轉換（IDE 輸入框適用）").font(.headline)
            Toggle("選取文字後顯示浮動按鈕", isOn: $watcherLeft)
                .onChange(of: watcherLeft) { _ in model.setWatcher(left: watcherLeft, right: watcherRight) }
            Toggle("選取文字後按右鍵顯示操作選單", isOn: $watcherRight)
                .onChange(of: watcherRight) { _ in model.setWatcher(left: watcherLeft, right: watcherRight) }
            Text("只有點選「轉為英文 Prompt」才會生成；原軟體的右鍵選單仍保留。")
                .font(.caption).foregroundColor(.secondary)
            Toggle("生成後自動貼回選取位置", isOn: $model.pasteBackEnabled)
            Text("在支援讀取選取文字的輸入框中按右鍵，助手會關閉原右鍵選單、直接生成結果浮窗，並依設定貼回選取處。Electron 軟體的原生選單由軟體自行繪製；未選取文字時，原右鍵選單保持正常。需要輔助使用權限。")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("執行環境：Node.js 22 以上").font(.system(size: 12))
                Spacer()
                Button("指定 Node 執行檔…") { chooseNode() }
            }
            Text("本機服務固定使用 127.0.0.1:3210；原本網頁工作台的 3000 埠仍可獨立使用。只保存設定檔位置、用途和目標模型，不保存原文、結果或剪貼簿紀錄。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("完成") { model.settingsVisible = false }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 565)
    }

    private func chooseConfig() {
        let panel = NSOpenPanel()
        panel.title = "選擇模型設定檔（.env）"; panel.showsHiddenFiles = true
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { model.useConfig(url) }
    }

    private func chooseNode() {
        let panel = NSOpenPanel(); panel.title = "選擇 Node.js 執行檔"
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
                guard let template = Bundle.main.url(forResource: "deepseek", withExtension: "env.example") else { throw ToolError.message("缺少設定範本，請重新建置。") }
                try FileManager.default.copyItem(at: template, to: destination)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
            }
            if let editor = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
                NSWorkspace.shared.open([destination], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            } else { NSWorkspace.shared.open(destination) }
            model.useConfig(destination)
        } catch { model.notify(error.localizedDescription, error: true) }
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
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        hotKey.action = { [weak self] in self?.model.selection() }
        if !hotKey.register() { model.notify("⌥⌘P 已被其他程式佔用，請改用右鍵「服務」或剪貼簿。", error: true) }
        model.watcher.onSelection = { [weak model] capture, anchor, eventSequence in
            model?.convert(capture.text, sourcePID: capture.pid, sourceCapture: capture, anchor: anchor,
                           eventSequence: eventSequence)
        }
        model.watcher.canStartConversion = { [weak model] in model?.busy != true }
        model.watcher.activate()
        if !TextSelection.authorized {
            model.notify("浮動按鈕與 ⌥⌘P 未生效：請在「系統設定 → 輔助使用」允許 PromptFinch，授權後自動生效。", error: true)
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
        for (title, selector) in [("開啟 PromptFinch", #selector(openWorkspace)), ("讀取選取文字  ⌥⌘P", #selector(readSelection)), ("從剪貼簿生成英文 Prompt", #selector(readClipboard)), ("設定…", #selector(settings)), ("結束", #selector(quit))] {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self
            menu.addItem(item)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "PromptFinch")
        statusItem.menu = menu

        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let servicesItem = NSMenuItem(title: "服務", action: nil, keyEquivalent: "")
        servicesItem.submenu = NSMenu(title: "服務"); appMenu.addItem(servicesItem); NSApp.servicesMenu = servicesItem.submenu
        let quitItem = NSMenuItem(title: "結束 PromptFinch", action: #selector(quit), keyEquivalent: "q"); quitItem.target = self; appMenu.addItem(quitItem)
        let editItem = NSMenuItem(); editItem.title = "編輯"; main.addItem(editItem)
        let edit = NSMenu(title: "編輯"); editItem.submenu = edit
        for (title, action, key) in [("復原", "undo:", "z"), ("剪下", "cut:", "x"), ("複製", "copy:", "c"), ("貼上", "paste:", "v"), ("全選", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        NSApp.mainMenu = main
    }

    @objc(generateEnglishPrompt:userData:error:)
    func generateEnglishPrompt(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "請先選取要優化的文字。"; return
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
            Task { @MainActor in
                guard let self, TextSelection.authorized else { return }
                self.permissionTimer?.invalidate(); self.permissionTimer = nil
                self.model.watcher.start()
                self.model.notify("輔助使用權限已開啟，浮動按鈕與 ⌥⌘P 已生效。")
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
