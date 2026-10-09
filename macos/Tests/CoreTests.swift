import Foundation
import AppKit
import ApplicationServices

@main
struct CoreTests {
    @MainActor
    static func main() async throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        func invalid(_ request: PromptRequest) -> Bool {
            do { try request.validate(); return false } catch { return true }
        }
        check(invalid(PromptRequest(prompt: " \n", task: "general", targetModel: "")), "blank input rejected")
        check(invalid(PromptRequest(prompt: String(repeating: "😀", count: 6001), task: "general", targetModel: "")), "UTF-16 limit matches server")
        check(invalid(PromptRequest(prompt: "請整理", task: "general", targetModel: "a\nb")), "multiline model rejected")
        let input = PromptRequest(prompt: "寫一封繁體中文邀請信，100 字內，日期 10 月 15 日，不提折扣。", task: "writing", targetModel: "Claude")
        try input.validate()
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as! [String: Any]
        check(encoded["promptLanguage"] as? String == "en", "explicit English prompt language")
        check(encoded["prompt"] as? String == input.prompt, "raw input preserved for provider")
        let multilingual = PromptRequest(prompt: "日本語の依頼。Escribe un aviso breve en español. أجب بالعربية. Keep 「設定変更」 exactly.",
                                         task: "writing", targetModel: "")
        try multilingual.validate()
        let multilingualEncoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(multilingual)) as! [String: Any]
        check(multilingualEncoded["prompt"] as? String == multilingual.prompt,
              "native request preserves mixed Unicode source text")
        let client = PromptClient(baseURL: URL(string: CommandLine.arguments[1])!)
        let backendID = String(repeating: "a", count: 64)
        let instanceID = "3f5dbd86-9ae6-43a1-a938-02d6739f5e36"
        let config = try await client.config(expectedBackendID: backendID, expectedInstanceID: instanceID)
        check(config.mode == "mock" && config.ready, "mock startup works")
        check(config.backendID == backendID && config.backendInstanceID == instanceID, "owned backend identity parsed")
        do {
            _ = try await client.config(expectedBackendID: backendID, expectedInstanceID: "different-instance-000000000000")
            preconditionFailure("old backend process must be rejected")
        } catch let error as ToolError {
            check(error.localizedDescription.contains("不是此 App 本次啟動"), "old backend process rejected")
        }
        let result = try await client.optimize(input)
        check(result.mode == "mock" && result.promptLanguage == "en", "result metadata parsed")
        check(result.prompt.contains("NOT been translated") && result.prompt.contains(input.prompt), "mock is explicitly untranslated")
        for source in ["한국어로 두 문장. 안녕하세요-42", "Напиши по-русски. Привет-42",
                       "اَلْعَرَبِيَّة خوش‌آمدید", "한글 Cafe\u{0301} 👩🏽‍💻 ${user_name}"] {
            let request = PromptRequest(prompt: source, task: "writing", targetModel: "")
            try request.validate()
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
            check((object["prompt"] as! String).utf16.elementsEqual(source.utf16), "multilingual encoding keeps exact UTF-16 units")
            let response = try await client.optimize(request)
            check(response.prompt.range(of: source, options: .literal) != nil, "native JSON result preserves multilingual mock source")
            let wrapper = "prefix " + source + " suffix"
            let slice = TextSelection.utf16Slice(wrapper, range: SelectionRange(location: 7, length: source.utf16.count))
            check(slice?.utf16.elementsEqual(source.utf16) == true, "bounded AX range keeps Hangul/Cyrillic/RTL/combining/emoji units")
        }
        check(!invalid(PromptRequest(prompt: String(repeating: "😀", count: 6000), task: "general", targetModel: "")), "exact UTF-16 limit accepted without truncation")

        let range = SelectionRange(location: 12, length: 8)
        let appElement = AXUIElementCreateApplication(getpid())
        let sameAppElement = AXUIElementCreateApplication(getpid())
        let otherElement = AXUIElementCreateSystemWide()
        let firstCapture = SelectionCapture(text: "相同選取", bounds: nil, pid: 77, element: appElement, range: range)
        let recaptured = SelectionCapture(text: "相同選取", bounds: nil, pid: 77, element: sameAppElement, range: range)
        let differentField = SelectionCapture(text: "相同選取", bounds: nil, pid: 77, element: otherElement, range: range)
        let movedRange = SelectionCapture(text: "相同選取", bounds: nil, pid: 77, element: appElement,
                                          range: SelectionRange(location: 13, length: 8))
        let changedText = SelectionCapture(text: "另一段文字", bounds: nil, pid: 77, element: appElement, range: range)
        check(firstCapture.stillTargetsSameSelection(as: recaptured), "recaptured same AX app element accepted")
        check(!firstCapture.stillTargetsSameSelection(as: differentField), "different AX element rejected even with same PID, text and range")
        check(!firstCapture.stillTargetsSameSelection(as: movedRange), "changed selected range rejected")
        check(!firstCapture.stillTargetsSameSelection(as: changedText), "changed selected text rejected")

        check(SelectionMenuPolicy.canConvert(sourceMatches: true, sourcePID: 77, frontPID: 77,
                                              enabled: true, busy: false, age: 1),
              "explicit menu choice accepts an unchanged foreground selection")
        check(!SelectionMenuPolicy.canConvert(sourceMatches: false, sourcePID: 77, frontPID: 77,
                                               enabled: true, busy: false, age: 1),
              "menu choice rejects changed text, field or range")
        check(!SelectionMenuPolicy.canConvert(sourceMatches: true, sourcePID: 77, frontPID: 78,
                                               enabled: true, busy: false, age: 1),
              "menu choice rejects an app switch")
        check(!SelectionMenuPolicy.canConvert(sourceMatches: true, sourcePID: 77, frontPID: nil,
                                               enabled: true, busy: false, age: 1),
              "menu choice rejects missing foreground identity")
        check(!SelectionMenuPolicy.canConvert(sourceMatches: true, sourcePID: 77, frontPID: 77,
                                               enabled: false, busy: false, age: 1),
              "disabling right-click actions prevents a previously offered action")
        check(!SelectionMenuPolicy.canConvert(sourceMatches: true, sourcePID: 77, frontPID: 77,
                                               enabled: true, busy: true, age: 1),
              "menu choice cannot interrupt an active conversion")
        check(!SelectionMenuPolicy.canConvert(sourceMatches: true, sourcePID: 77, frontPID: 77,
                                               enabled: true, busy: false, age: 12),
              "expired menu choices are rejected")
        check(!SelectionMenuPolicy.canConvert(sourceMatches: true, sourcePID: 77, frontPID: 77,
                                               enabled: true, busy: false, age: -0.01),
              "future-dated menu choices are rejected")

        // Exercise actual AppKit button actions without displaying a window,
        // sending key events, accessing host text or calling a real model.
        _ = NSApplication.shared
        let menu = SelectionActionMenu()
        let buttons = menu.contentView!.subviews.compactMap { $0 as? NSButton }
        let convertItem = buttons.first { $0.title.contains("轉為英文 Prompt") }!
        let cancelItem = buttons.first { $0.title == "取消" }!
        var conversions = 0
        var cancellations = 0
        menu.configure(onConvert: { _ in conversions += 1 }, onCancel: { cancellations += 1 })
        check(conversions == 0, "offering a right-click menu never starts generation")
        cancelItem.performClick(nil)
        check(conversions == 0 && cancellations == 1, "cancel menu item does not generate")
        convertItem.performClick(nil)
        check(conversions == 0, "a dismissed menu cannot execute a stale conversion")
        menu.configure(onConvert: { _ in conversions += 1 }, onCancel: {})
        convertItem.performClick(nil)
        check(conversions == 1, "explicit convert menu item invokes the conversion")
        convertItem.performClick(nil)
        check(conversions == 1, "double clicking cannot invoke the same menu action twice")
        menu.configure(onConvert: { _ in conversions += 1 }, onCancel: {})
        menu.dismiss()
        convertItem.performClick(nil)
        check(conversions == 1, "outside-click, keyboard, timeout and stop dismissal discard pending actions")
        menu.configure(onConvert: { _ in conversions += 100 }, onCancel: {})
        menu.configure(onConvert: { _ in conversions += 1 }, onCancel: {})
        convertItem.performClick(nil)
        check(conversions == 2, "replacing a menu discards its previous conversion action")

        check(RightClickCapturePolicy.delayedInspectMatches(expectedSequence: 41, actualSequence: 41,
                                                             expectedPID: 77, capturePID: 77),
              "delayed selection is accepted only from its expected inspect sequence and PID")
        check(!RightClickCapturePolicy.delayedInspectMatches(expectedSequence: 41, actualSequence: 42,
                                                              expectedPID: 77, capturePID: 77),
              "delayed selection from a different mouse-up cannot satisfy this right click")
        check(!RightClickCapturePolicy.delayedInspectMatches(expectedSequence: 41, actualSequence: 41,
                                                              expectedPID: 77, capturePID: 78),
              "delayed selection from another process is rejected")
        check(RightClickCapturePolicy.canReuseRecentCandidate(candidatePID: 77, frontPID: 77, age: 2,
                                                               candidateGestureSequence: 40, latestGestureSequence: 40,
                                                               clickPoint: CGPoint(x: 105, y: 98),
                                                               selectionPoint: CGPoint(x: 100, y: 100)),
              "recent candidate near the selection release point is accepted")
        check(!RightClickCapturePolicy.canReuseRecentCandidate(candidatePID: 77, frontPID: 77, age: 2,
                                                                candidateGestureSequence: 40, latestGestureSequence: 40,
                                                                clickPoint: CGPoint(x: 400, y: 100),
                                                                selectionPoint: CGPoint(x: 100, y: 100)),
              "recent candidate from another field in the same app is rejected by pointer distance")
        check(!RightClickCapturePolicy.canReuseRecentCandidate(candidatePID: 77, frontPID: 77, age: 2,
                                                                candidateGestureSequence: 40, latestGestureSequence: 41,
                                                                clickPoint: CGPoint(x: 105, y: 98),
                                                                selectionPoint: CGPoint(x: 100, y: 100)),
              "a new selection gesture invalidates a nearby cached candidate from the same app")
        check(!RightClickCapturePolicy.canReuseRecentCandidate(candidatePID: 77, frontPID: 77, age: 2,
                                                                candidateGestureSequence: nil, latestGestureSequence: 41,
                                                                clickPoint: CGPoint(x: 105, y: 98),
                                                                selectionPoint: CGPoint(x: 100, y: 100)),
              "candidate without a correlated selection gesture is rejected")
        check(!RightClickCapturePolicy.canReuseRecentCandidate(candidatePID: 77, frontPID: 77, age: 8.01,
                                                                candidateGestureSequence: 40, latestGestureSequence: 40,
                                                                clickPoint: CGPoint(x: 100, y: 100),
                                                                selectionPoint: CGPoint(x: 100, y: 100)),
              "expired same-app candidate is rejected")
        check(!RightClickCapturePolicy.canReuseRecentCandidate(candidatePID: 77, frontPID: 77, age: -0.1,
                                                                candidateGestureSequence: 40, latestGestureSequence: 40,
                                                                clickPoint: CGPoint(x: 100, y: 100),
                                                                selectionPoint: CGPoint(x: 100, y: 100)),
              "future-dated candidate is rejected")
        check(RightClickCapturePolicy.shouldWaitForDelayedInspect(hasPendingCapture: false,
                                                                   awaitedSequence: 41, scheduledSequence: 41,
                                                                   allowRetry: true),
              "empty pending capture waits once for its matching delayed inspect")
        check(!RightClickCapturePolicy.shouldWaitForDelayedInspect(hasPendingCapture: false,
                                                                    awaitedSequence: 41, scheduledSequence: 42,
                                                                    allowRetry: true),
              "unrelated delayed inspect cannot postpone right-click completion")
        check(!RightClickCapturePolicy.shouldWaitForDelayedInspect(hasPendingCapture: false,
                                                                    awaitedSequence: 41, scheduledSequence: 41,
                                                                    allowRetry: false),
              "delayed inspect is not retried twice")
        check(RightClickCapturePolicy.shouldInvalidateRecentCandidate(explicitlyEmpty: true,
                                                                       candidatePID: 77, inspectPID: 77),
              "explicitly empty selection invalidates same-process cached text")
        check(!RightClickCapturePolicy.shouldInvalidateRecentCandidate(explicitlyEmpty: false,
                                                                        candidatePID: 77, inspectPID: 77),
              "AX-unavailable result does not masquerade as explicit empty selection")
        check(!RightClickCapturePolicy.shouldInvalidateRecentCandidate(explicitlyEmpty: true,
                                                                        candidatePID: 77, inspectPID: 78),
              "empty selection in another process leaves this candidate untouched")

        let unicodeSource = "Ａ😀B"
        check(TextSelection.utf16Slice(unicodeSource, range: SelectionRange(location: 1, length: 2)) == "😀",
              "UTF-16 fallback preserves a complete supplementary character")
        check(TextSelection.utf16Slice(unicodeSource, range: SelectionRange(location: 0, length: 3)) == "Ａ😀",
              "UTF-16 fallback preserves mixed Unicode selection")
        check(TextSelection.utf16Slice(unicodeSource, range: SelectionRange(location: 1, length: 1)) == nil,
              "UTF-16 fallback rejects a range ending inside a surrogate pair")
        check(TextSelection.utf16Slice(unicodeSource, range: SelectionRange(location: 2, length: 1)) == nil,
              "UTF-16 fallback rejects a range starting inside a surrogate pair")
        check(TextSelection.utf16Slice(unicodeSource, range: SelectionRange(location: 3, length: 2)) == nil,
              "UTF-16 fallback rejects an out-of-bounds range")
        check(TextSelection.utf16Slice(unicodeSource, range: SelectionRange(location: 0, length: 0)) == nil,
              "UTF-16 fallback rejects an empty range")
        check(TextSelection.utf16Slice(unicodeSource, range: SelectionRange(location: Int.max, length: 2)) == nil,
              "UTF-16 fallback rejects integer overflow")
        check(TextSelection.utf16Slice(unicodeSource, range: SelectionRange(location: 0, length: 12_001)) == nil,
              "UTF-16 fallback enforces the selected-text limit")
        check(TextSelection.isMenuOrSecureRole(role: "AXSecureTextField", subrole: nil),
              "secure role is excluded")
        check(TextSelection.isMenuOrSecureRole(role: "AXTextField", subrole: "AXSecureTextField"),
              "secure subrole is excluded")
        check(TextSelection.isMenuOrSecureRole(role: "AXMenuItem", subrole: nil),
              "menu role is excluded")
        check(TextSelection.allowsValueRangeFallback(role: "AXTextView", subrole: nil),
              "text view permits bounded value-range fallback")
        check(TextSelection.allowsValueRangeFallback(role: "AXTextArea", subrole: nil),
              "text area permits bounded value-range fallback")
        check(TextSelection.allowsValueRangeFallback(role: "AXTextField", subrole: "AXTextField"),
              "identified text field permits bounded value-range fallback")
        check(!TextSelection.allowsValueRangeFallback(role: "AXTextField", subrole: nil),
              "text field without a readable subrole is excluded")
        check(!TextSelection.allowsValueRangeFallback(role: "AXButton", subrole: nil),
              "non-editable control cannot provide AXValue fallback")

        let lease = PasteRestoreLease()
        check(lease.isCurrent(lease), "current clipboard restore lease accepted")
        check(!lease.isCurrent(PasteRestoreLease()), "superseded clipboard restore lease rejected")
        check(!ClipboardRestorePolicy.shouldRestore(currentCount: 10, currentText: "使用者新複製", generatedText: "prompt", afterWrite: 9),
              "user clipboard change is preserved")
        check(ClipboardRestorePolicy.shouldRestore(currentCount: 10, currentText: "prompt", generatedText: "prompt", afterWrite: 9),
              "browser count-only change still allows restore")

        let clipboardBehavior = await testClipboardRestoreBehavior()
        check(clipboardBehavior[0], "scheduled restore does not overwrite a later copy")
        check(clipboardBehavior[1], "empty clipboard is restored after paste")
        check(clipboardBehavior[2], "consecutive pastes restore the original clipboard")
        print("Swift 核心、本機 API、選取目標與剪貼簿競態：\(checks) 項檢查通過。")
    }
}

@MainActor
private func testClipboardRestoreBehavior() async -> [Bool] {
    let boardName = NSPasteboard.Name("org.promptstudio.tests.\(UUID().uuidString)")
    let board = NSPasteboard(name: boardName)
    let coordinator = ClipboardRestoreCoordinator(pasteboard: board)
    defer {
        board.clearContents()
        board.releaseGlobally()
    }

    board.clearContents()
    guard board.setString("original clipboard", forType: .string),
          let copyRace = coordinator.preparePaste("generated prompt") else { return [false, false, false] }
    coordinator.scheduleRestore(copyRace, after: 0.04)
    let copied = coordinator.write("user copied result")
    try? await Task.sleep(nanoseconds: 120_000_000)
    let copyPreserved = copied && board.string(forType: .string) == "user copied result"

    board.clearContents()
    guard let emptyRestore = coordinator.preparePaste("temporary output") else { return [copyPreserved, false, false] }
    coordinator.scheduleRestore(emptyRestore, after: 0.04)
    try? await Task.sleep(nanoseconds: 120_000_000)
    let emptyRestored = board.string(forType: .string) == nil

    board.clearContents()
    guard board.setString("original before consecutive paste", forType: .string),
          let firstPaste = coordinator.preparePaste("first generated prompt") else {
        return [copyPreserved, emptyRestored, false]
    }
    coordinator.scheduleRestore(firstPaste, after: 0.16)
    try? await Task.sleep(nanoseconds: 20_000_000)
    guard let secondPaste = coordinator.preparePaste("second generated prompt") else {
        return [copyPreserved, emptyRestored, false]
    }
    coordinator.scheduleRestore(secondPaste, after: 0.04)
    try? await Task.sleep(nanoseconds: 140_000_000)
    let originalRestored = board.string(forType: .string) == "original before consecutive paste"
    return [copyPreserved, emptyRestored, originalRestored]
}
