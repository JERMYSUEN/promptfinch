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
            check(error.localizedDescription == L10n.text(.backendInstanceMismatch), "old backend process rejected")
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

        _ = NSApplication.shared
        // Localization checks use temporary preferences and a volatile argument
        // domain, never changing the user's saved language or calling a real model.
        let suiteName = "PromptFinch-localization-tests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suiteName)!
        let argumentDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            preferences.removePersistentDomain(forName: suiteName)
            UserDefaults.standard.setVolatileDomain(argumentDomain, forName: UserDefaults.argumentDomain)
        }
        check(Set(L10n.Key.allCases) == Set(L10n.translations.keys), "every UI key has a translation entry")
        check(L10n.translations.values.allSatisfy { $0.count == UILanguage.allCases.count && $0.allSatisfy { !$0.isEmpty } },
              "all four languages have complete nonempty translations")
        check(L10n.translations.values.allSatisfy { values in
            Set(values.map { $0.components(separatedBy: "%@").count }).count == 1
        }, "format placeholders agree across languages")
        check(UILanguage.load(from: preferences) == .traditionalChinese, "new installs keep Traditional Chinese default")
        preferences.set("unsupported", forKey: UILanguage.preferenceKey)
        check(UILanguage.load(from: preferences) == .traditionalChinese, "unknown stored locale falls back safely")
        for language in UILanguage.allCases {
            language.save(to: preferences)
            check(UILanguage.load(from: preferences) == language, "language survives preference reload")
        }
        for language in UILanguage.allCases {
            var domain = argumentDomain
            domain[UILanguage.preferenceKey] = language.rawValue
            UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
            check(L10n.language == language, "current UI language follows preferences")
            let filename = "config-日本語-한국어-100%.env"
            check(L10n.relocalize(L10n.text(.configFile, filename, language: .traditionalChinese),
                                 from: .traditionalChinese) == L10n.text(.configFile, filename),
                  "switching language preserves inserted filenames exactly")
            check(L10n.relocalize(L10n.text(.unsafePasteCopied, L10n.text(.unknownTarget, language: .traditionalChinese),
                                          language: .traditionalChinese), from: .traditionalChinese)
                  == L10n.text(.unsafePasteCopied, L10n.text(.unknownTarget)),
                  "switching language translates nested status messages")
            check(L10n.errorDescription(ToolError.message(L10n.text(.providerAuth, language: .traditionalChinese)))
                  == L10n.text(.providerAuth), "provider errors use the selected UI language")
            let untouched = "Do not translate this note: 你好 안녕하세요 日本語 %@"
            check(L10n.relocalize(untouched, from: .traditionalChinese) == untouched,
                  "unrecognized text is not rewritten by UI localization")
            let apiInput = try JSONSerialization.jsonObject(with: JSONEncoder().encode(multilingual)) as! [String: Any]
            check(apiInput["promptLanguage"] as? String == "en" && apiInput["prompt"] as? String == multilingual.prompt,
                  "UI language never changes prompt language or original input")
            let localizedMenu = SelectionActionMenu()
            var invoked = false
            localizedMenu.configure(onConvert: { _ in invoked = true }, onCancel: {})
            let items = localizedMenu.contentView!.subviews.compactMap { $0 as? NSButton }
            check(items.contains { $0.title.contains(L10n.text(.convert)) } && items.contains { $0.title == L10n.text(.cancel) },
                  "real context action buttons are localized")
            check(items.allSatisfy { $0.frame.width >= $0.intrinsicContentSize.width },
                  "context menu labels fit all supported languages")
            localizedMenu.dismiss()
            check(!invoked, "changing or dismissing a localized menu never generates")
            let localizedBar = FloatingBarPanel()
            localizedBar.configure(text: untouched, action: { _ in invoked = true })
            let barButton = localizedBar.contentView!.subviews.compactMap { $0 as? NSButton }.first!
            check(barButton.frame.width >= barButton.intrinsicContentSize.width,
                  "floating action grows to fit translated labels")
        }
        UserDefaults.standard.setVolatileDomain(argumentDomain, forName: UserDefaults.argumentDomain)

        let range = SelectionRange(location: 12, length: 4)
        let appElement = AXUIElementCreateApplication(getpid())
        let sameAppElement = AXUIElementCreateApplication(getpid())
        let otherElement = AXUIElementCreateSystemWide()
        let firstCapture = SelectionCapture(text: "相同選取", bounds: nil, pid: 77, element: appElement, range: range)
        let recaptured = SelectionCapture(text: "相同選取", bounds: nil, pid: 77, element: sameAppElement, range: range)
        let differentField = SelectionCapture(text: "相同選取", bounds: nil, pid: 77, element: otherElement, range: range)
        let movedRange = SelectionCapture(text: "相同選取", bounds: nil, pid: 77, element: appElement,
                                          range: SelectionRange(location: 13, length: 4))
        let changedText = SelectionCapture(text: "另一段文字", bounds: nil, pid: 77, element: appElement, range: range)
        check(firstCapture.stillTargetsSameSelection(as: recaptured), "recaptured same AX app element accepted")
        check(!firstCapture.stillTargetsSameSelection(as: differentField), "different AX element rejected even with same PID, text and range")
        check(!firstCapture.stillTargetsSameSelection(as: movedRange), "changed selected range rejected")
        check(!firstCapture.stillTargetsSameSelection(as: changedText), "changed selected text rejected")
        let textOnly = SelectionCapture(text: firstCapture.text, bounds: nil, pid: 77, element: appElement, range: nil)
        check(textOnly.matchesForConversion(as: textOnly), "unchanged text-only selection still supports conversion")
        check(!textOnly.hasReliableRange && !textOnly.stillTargetsSameSelection(as: textOnly),
              "two missing ranges never authorize an ambiguous paste")
        check(!firstCapture.matchesForConversion(as: textOnly), "loss of an offered range rejects conversion of a stale capture")
        let composed = SelectionCapture(text: "é", bounds: nil, pid: 77, element: appElement, range: nil)
        let decomposed = SelectionCapture(text: "e\u{0301}", bounds: nil, pid: 77, element: appElement, range: nil)
        check(!composed.matchesForConversion(as: decomposed), "source confirmation preserves exact Unicode units rather than normalized equality")
        for invalidRange in [SelectionRange(location: -1, length: 4), SelectionRange(location: 0, length: 0),
                             SelectionRange(location: 0, length: 3), SelectionRange(location: Int.max, length: 4)] {
            let invalidCapture = SelectionCapture(text: firstCapture.text, bounds: nil, pid: 77,
                                                  element: appElement, range: invalidRange)
            check(!invalidCapture.hasReliableRange && !invalidCapture.stillTargetsSameSelection(as: invalidCapture),
                  "negative, empty, length-mismatched or overflowing ranges cannot authorize paste")
        }
        let emojiCapture = SelectionCapture(text: "😀", bounds: nil, pid: 77, element: appElement,
                                            range: SelectionRange(location: 10, length: 2))
        check(emojiCapture.hasReliableRange, "paste validation uses UTF-16 rather than character count")

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
        for (value, message) in testSelectionBarBehavior() { check(value, message) }

        // Exercise actual AppKit button actions without displaying a window,
        // sending key events, accessing host text or calling a real model.
        _ = NSApplication.shared
        let menu = SelectionActionMenu()
        let buttons = menu.contentView!.subviews.compactMap { $0 as? NSButton }
        let convertItem = buttons.first { $0.title.contains(L10n.text(.convert)) }!
        let cancelItem = buttons.first { $0.title == L10n.text(.cancel) }!
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
        for (value, message) in await testPasteBackFlow() { check(value, message) }
        await checkWorkspacePasteFeedback(check: { value, message in check(value, message) })
        print("Swift 核心、本機 API、選取目標與剪貼簿競態：\(checks) 項檢查通過。")
    }
}

@MainActor
private func testSelectionBarBehavior() -> [(Bool, String)] {
    let oldDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
    var domain = oldDomain
    domain[SelectionWatcher.leftKey] = true
    UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    defer { UserDefaults.standard.setVolatileDomain(oldDomain, forName: UserDefaults.argumentDomain) }

    let element = AXUIElementCreateApplication(getpid())
    let selected = SelectionCapture(text: "selected", bounds: nil, pid: 77, element: element,
                                   range: SelectionRange(location: 2, length: 8))
    var current: SelectionCapture? = selected
    var frontPID: pid_t? = 77
    var busy = false
    var time = Date(timeIntervalSince1970: 100)
    var switchDuringInspection = false
    var inspections = 0
    var conversions = 0
    let bar = FloatingBarPanel()
    let watcher = SelectionWatcher(floatingBar: bar, frontmostPID: { frontPID },
                                   captureForAction: { _, _, _, _ in
                                       inspections += 1
                                       if switchDuringInspection { frontPID = 78 }
                                       return current
                                   },
                                   now: { time }, presentPanel: { _ in })
    watcher.canStartConversion = { !busy }
    watcher.onSelection = { _, _, _ in conversions += 1 }
    let button = bar.contentView!.subviews.compactMap { $0 as? NSButton }.first!
    var results: [(Bool, String)] = []
    func offerAndClick() {
        watcher.offerLeftSelection(capture: selected, mouse: .zero, eventSequence: 1)
        button.performClick(nil)
    }
    offerAndClick()
    results.append((conversions == 1 && inspections == 1, "real floating bar re-reads the unchanged selection before conversion"))
    button.performClick(nil)
    results.append((conversions == 1, "floating bar choice is consumed once"))
    current = SelectionCapture(text: "edited", bounds: nil, pid: 77, element: element, range: selected.range)
    offerAndClick()
    results.append((conversions == 1, "floating bar rejects text edited since the offer"))
    current = SelectionCapture(text: selected.text, bounds: nil, pid: 77, element: element,
                               range: SelectionRange(location: 20, length: 8))
    offerAndClick()
    results.append((conversions == 1, "floating bar rejects moved same-text selection"))
    current = SelectionCapture(text: selected.text, bounds: nil, pid: 77,
                               element: AXUIElementCreateSystemWide(), range: selected.range)
    offerAndClick()
    results.append((conversions == 1, "floating bar rejects another field with identical text and range"))
    current = nil
    offerAndClick()
    results.append((conversions == 1, "floating bar rejects cleared or unavailable selection"))
    current = selected
    frontPID = 78
    let inspectionsBeforeGuards = inspections
    offerAndClick()
    results.append((conversions == 1 && inspections == inspectionsBeforeGuards, "app switch rejects a bar before accessing source text"))
    frontPID = 77
    busy = true
    offerAndClick()
    results.append((conversions == 1 && inspections == inspectionsBeforeGuards, "busy conversion cannot be replaced by an older bar"))
    busy = false
    domain[SelectionWatcher.leftKey] = false
    UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    offerAndClick()
    results.append((conversions == 1 && inspections == inspectionsBeforeGuards, "disabled selection actions reject an already offered bar"))
    domain[SelectionWatcher.leftKey] = true
    UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    watcher.offerLeftSelection(capture: selected, mouse: .zero, eventSequence: 1)
    time = time.addingTimeInterval(8)
    button.performClick(nil)
    results.append((conversions == 1 && inspections == inspectionsBeforeGuards, "expired floating bar rejects conversion"))
    watcher.offerLeftSelection(capture: selected, mouse: .zero, eventSequence: 1)
    watcher.keyboardInputReceived()
    button.performClick(nil)
    results.append((conversions == 1 && inspections == inspectionsBeforeGuards, "keyboard input discards the floating bar callback"))
    watcher.offerLeftSelection(capture: selected, mouse: .zero, eventSequence: 1)
    watcher.foregroundChanged()
    button.performClick(nil)
    results.append((conversions == 1 && inspections == inspectionsBeforeGuards, "application activation discards the floating bar callback"))
    watcher.offerLeftSelection(capture: selected, mouse: .zero, eventSequence: 1)
    watcher.invalidatePendingActions()
    button.performClick(nil)
    results.append((conversions == 1 && inspections == inspectionsBeforeGuards, "settings save discards the floating bar callback"))
    switchDuringInspection = true
    offerAndClick()
    results.append((conversions == 1, "app switch during action-time source lookup rejects floating bar conversion"))
    switchDuringInspection = false
    frontPID = 77
    let textOnly = SelectionCapture(text: selected.text, bounds: nil, pid: 77, element: element, range: nil)
    current = textOnly
    watcher.offerLeftSelection(capture: textOnly, mouse: .zero, eventSequence: 1)
    button.performClick(nil)
    results.append((conversions == 2, "unchanged nil-range text-only apps keep explicit floating bar conversion"))
    watcher.stop()
    return results
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

@MainActor
private func testPasteBackFlow() async -> [(Bool, String)] {
    let board = NSPasteboard(name: NSPasteboard.Name("org.promptfinch.paste-flow.\(UUID().uuidString)"))
    defer { board.clearContents(); board.releaseGlobally() }
    let clipboard = ClipboardRestoreCoordinator(pasteboard: board)
    let element = AXUIElementCreateApplication(getpid())
    let source = SelectionCapture(text: "selected", bounds: nil, pid: 77, element: element,
                                 range: SelectionRange(location: 2, length: 8))
    var current: SelectionCapture? = source
    var foreground: pid_t? = 77
    var permission = true
    var readOnly = false
    var maySend = true
    var sent = 0
    var inspections = 0
    let coordinator = PasteBackCoordinator(clipboard: clipboard, authorized: { permission },
                                           frontmostPID: { foreground },
                                           capture: { _ in inspections += 1; return current },
                                           isKnownReadOnly: { _ in readOnly },
                                           sendCommandV: { if maySend { sent += 1 }; return maySend },
                                           restoreDelay: 0.03)
    var results: [(Bool, String)] = []
    func resetBoard() { board.clearContents(); _ = board.setString("original", forType: .string) }
    func request(_ target: SelectionCapture? = nil,
                 callback: ((ClipboardRestoreOutcome) -> Void)? = nil) -> PasteBackOutcome {
        coordinator.paste("generated", expectedTarget: target ?? source, onRestore: callback)
    }
    resetBoard()
    permission = false
    results.append((request() == .notAttempted && inspections == 0 && sent == 0
                    && board.string(forType: .string) == "original", "denied accessibility performs no capture, keys or clipboard write"))
    permission = true
    foreground = 78
    results.append((request() == .notAttempted && inspections == 0 && sent == 0,
                    "changed foreground app rejects paste before accessing source"))
    foreground = 77
    let textOnly = SelectionCapture(text: source.text, bounds: nil, pid: 77, element: element, range: nil)
    current = textOnly
    results.append((request(textOnly) == .notAttempted && sent == 0 && board.string(forType: .string) == "original",
                    "nil-range conversion results cannot initiate automatic paste"))
    current = SelectionCapture(text: source.text, bounds: nil, pid: 77, element: element,
                               range: SelectionRange(location: 10, length: 8))
    results.append((request() == .notAttempted && sent == 0, "paste flow rejects moved identical text"))
    current = SelectionCapture(text: source.text, bounds: nil, pid: 77,
                               element: AXUIElementCreateSystemWide(), range: source.range)
    results.append((request() == .notAttempted && sent == 0, "paste flow rejects another field in the same app"))
    current = source
    readOnly = true
    results.append((request() == .notAttempted && sent == 0 && board.string(forType: .string) == "original",
                    "positively read-only target rejects paste without touching clipboard"))
    readOnly = false
    maySend = false
    var callbacks: [ClipboardRestoreOutcome] = []
    let failedKeys = request(callback: { callbacks.append($0) })
    results.append((failedKeys == .notAttempted && sent == 0 && callbacks == [.restored]
                    && board.string(forType: .string) == "original", "failed event creation immediately restores clipboard and never claims a paste"))
    maySend = true
    callbacks = []
    let requested = request(callback: { callbacks.append($0) })
    results.append((requested == .pasteRequested && sent == 1 && callbacks.isEmpty
                    && board.string(forType: .string) == "generated", "sent events report only a paste request, not a completed write or restoration"))
    try? await Task.sleep(nanoseconds: 100_000_000)
    results.append((callbacks == [.restored] && board.string(forType: .string) == "original",
                    "completed delayed restoration reports restored exactly once"))

    callbacks = []
    _ = request(callback: { callbacks.append($0) })
    board.clearContents(); _ = board.setString("new user copy", forType: .string)
    try? await Task.sleep(nanoseconds: 100_000_000)
    results.append((callbacks == [.skippedNewerCopy] && board.string(forType: .string) == "new user copy",
                    "new external copy is preserved with a distinct skipped restoration outcome"))

    resetBoard()
    var firstCallbacks: [ClipboardRestoreOutcome] = []
    var secondCallbacks: [ClipboardRestoreOutcome] = []
    _ = request(callback: { firstCallbacks.append($0) })
    _ = request(callback: { secondCallbacks.append($0) })
    try? await Task.sleep(nanoseconds: 100_000_000)
    results.append((firstCallbacks == [.superseded] && secondCallbacks == [.restored]
                    && board.string(forType: .string) == "original", "consecutive paste callbacks distinguish supersession and preserve original backup"))

    resetBoard()
    var writeFailureOutcomes: [ClipboardRestoreOutcome] = []
    let failedWriteClipboard = ClipboardRestoreCoordinator(pasteboard: board, writeString: { _ in false })
    let failedWrite = failedWriteClipboard.preparePaste("generated", onFailure: { writeFailureOutcomes.append($0) })
    results.append((failedWrite == nil && writeFailureOutcomes == [.restored]
                    && board.string(forType: .string) == "original", "failed clipboard write after clearing recovers the original snapshot"))
    var unavailableEvents = 0
    let failedWriteFlow = PasteBackCoordinator(clipboard: failedWriteClipboard, authorized: { true },
                                               frontmostPID: { 77 }, capture: { _ in source },
                                               isKnownReadOnly: { _ in false },
                                               sendCommandV: { unavailableEvents += 1; return true })
    writeFailureOutcomes = []
    let failedWriteResult = failedWriteFlow.paste("generated", expectedTarget: source) { writeFailureOutcomes.append($0) }
    results.append((failedWriteResult == .clipboardUnavailable && unavailableEvents == 0
                    && writeFailureOutcomes == [.restored] && board.string(forType: .string) == "original",
                    "temporary clipboard write failure requests preservation rather than an automatic fallback copy"))

    // Real custom/promised clipboard data that its owner cannot supply. The
    // refusal must preserve every original item/type and must not send keys.
    let unavailableType = NSPasteboard.PasteboardType("org.promptfinch.tests.unavailable-data")
    let unavailableProvider = UnavailableClipboardDataProvider()
    let promisedItem = NSPasteboardItem()
    let promisedSetup = promisedItem.setString("protected original", forType: .string)
        && promisedItem.setDataProvider(unavailableProvider, forTypes: [unavailableType])
    board.clearContents()
    let promisedWritten = board.writeObjects([promisedItem])
    let countBeforeRefusal = board.changeCount
    let typesBeforeRefusal = board.pasteboardItems?.map { $0.types } ?? []
    var refusalOutcomes: [ClipboardRestoreOutcome] = []
    let refusal = PasteBackCoordinator(clipboard: clipboard, authorized: { true },
                                       frontmostPID: { 77 }, capture: { _ in source },
                                       isKnownReadOnly: { _ in false },
                                       sendCommandV: { unavailableEvents += 1; return true })
        .paste("generated", expectedTarget: source) { refusalOutcomes.append($0) }
    results.append((promisedSetup && promisedWritten && refusal == .clipboardUnavailable
                    && refusalOutcomes == [.failed] && unavailableEvents == 0
                    && board.changeCount == countBeforeRefusal
                    && board.pasteboardItems?.map({ $0.types }) == typesBeforeRefusal
                    && board.string(forType: .string) == "protected original",
                    "unsnapshottable promised clipboard type preserves items/count and suppresses keys and fallback copy"))
    withExtendedLifetime(unavailableProvider) {}

    resetBoard()
    let failedRestoreClipboard = ClipboardRestoreCoordinator(pasteboard: board, writeItems: { _ in false })
    var restoreFailureOutcomes: [ClipboardRestoreOutcome] = []
    if let transaction = failedRestoreClipboard.preparePaste("generated") {
        failedRestoreClipboard.scheduleRestore(transaction, after: 0.01) { restoreFailureOutcomes.append($0) }
    }
    try? await Task.sleep(nanoseconds: 100_000_000)
    results.append((restoreFailureOutcomes == [.failed], "clipboard restoration write failure is explicitly reported"))
    resetBoard()
    var failedRecoveryOutcomes: [ClipboardRestoreOutcome] = []
    let failedRecoveryFlow = PasteBackCoordinator(clipboard: failedRestoreClipboard, authorized: { true },
                                                  frontmostPID: { 77 }, capture: { _ in source },
                                                  isKnownReadOnly: { _ in false }, sendCommandV: { false })
    let failedRecoveryResult = failedRecoveryFlow.paste("generated", expectedTarget: source) { failedRecoveryOutcomes.append($0) }
    results.append((failedRecoveryResult == .clipboardUnavailable && failedRecoveryOutcomes == [.failed],
                    "failed immediate restoration stops automatic writes instead of disguising the failure as a source mismatch"))
    resetBoard()
    var racedCopyOutcomes: [ClipboardRestoreOutcome] = []
    let failedKeysWithNewCopy = PasteBackCoordinator(clipboard: clipboard, authorized: { true },
                                                    frontmostPID: { 77 }, capture: { _ in source },
                                                    isKnownReadOnly: { _ in false }, sendCommandV: {
                                                        board.clearContents()
                                                        _ = board.setString("new copy during failed event creation", forType: .string)
                                                        return false
                                                    })
    let racedCopyResult = failedKeysWithNewCopy.paste("generated", expectedTarget: source) { racedCopyOutcomes.append($0) }
    results.append((racedCopyResult == .clipboardUnavailable && racedCopyOutcomes == [.skippedNewerCopy]
                    && board.string(forType: .string) == "new copy during failed event creation",
                    "new user copy during failed event creation survives recovery without an automatic fallback overwrite"))

    resetBoard()
    var reentrantOutcomes: [ClipboardRestoreOutcome] = []
    if let transaction = clipboard.preparePaste("first") {
        clipboard.scheduleRestore(transaction, after: 0.01) { outcome in
            reentrantOutcomes.append(outcome)
            if let next = clipboard.preparePaste("second") {
                clipboard.scheduleRestore(next, after: 0.01) { reentrantOutcomes.append($0) }
            }
        }
    }
    try? await Task.sleep(nanoseconds: 120_000_000)
    results.append((reentrantOutcomes == [.restored, .restored] && board.string(forType: .string) == "original",
                    "restore callback can start a new transaction without an old lease clearing it"))

    resetBoard()
    var foregroundReads = 0
    var switchEvents = 0
    let switching = PasteBackCoordinator(clipboard: clipboard, authorized: { true },
                                         frontmostPID: { foregroundReads += 1; return foregroundReads <= 2 ? 77 : 78 },
                                         capture: { _ in source }, isKnownReadOnly: { _ in false },
                                         sendCommandV: { switchEvents += 1; return true })
    var switchOutcomes: [ClipboardRestoreOutcome] = []
    let switchResult = switching.paste("generated", expectedTarget: source) { switchOutcomes.append($0) }
    results.append((switchResult == .notAttempted && switchEvents == 0 && switchOutcomes == [.restored]
                    && board.string(forType: .string) == "original", "late app switch after clipboard preparation cancels keys and restores immediately"))
    return results
}

private final class UnavailableClipboardDataProvider: NSObject, NSPasteboardItemDataProvider {
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        // Deliberately provide no payload, reproducing an unavailable promised type.
    }
}
