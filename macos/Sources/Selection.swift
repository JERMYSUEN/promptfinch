import AppKit
import ApplicationServices
import Carbon

struct SelectionRange: Equatable {
    let location: Int
    let length: Int
}

struct SelectionCapture {
    let text: String
    let bounds: CGRect?
    let pid: pid_t
    let element: AXUIElement
    let range: SelectionRange?

    // Text-only accessibility clients can still offer conversion. A missing
    // range, however, cannot establish where an automatic paste will land.
    var hasReliableRange: Bool {
        guard let range else { return false }
        return range.location >= 0 && range.length > 0
            && range.length == text.utf16.count
            && range.location <= Int.max - range.length
    }

    func matchesForConversion(as current: SelectionCapture) -> Bool {
        pid == current.pid && CFEqual(element, current.element)
            && text.utf16.elementsEqual(current.text.utf16) && range == current.range
    }

    // Refuse paste-back when the field, text or exact UTF-16 range changed.
    // nil == nil is adequate for conversion, but never for replacing text.
    func stillTargetsSameSelection(as current: SelectionCapture) -> Bool {
        hasReliableRange && current.hasReliableRange && matchesForConversion(as: current)
    }
}

@MainActor
enum TextSelection {
    private static let maxSelectedUTF16Length = 12_000
    private static let maxValueUTF16Length = 65_536

    private struct AXAttribute {
        let error: AXError
        let value: CFTypeRef?
    }

    private struct RangeAttribute {
        let error: AXError
        let type: String
        let range: SelectionRange?
        let isExplicitlyEmpty: Bool
        let detail: String
    }

    enum CaptureOutcome {
        case selected(SelectionCapture)
        case explicitlyEmpty
        case accessibilityActivated
        case accessibilityActivationPending
        case unavailable
    }

    private struct ProcessIdentity: Hashable {
        let pid: pid_t
        let bundleID: String
        let launchTime: TimeInterval
    }

    private enum AccessibilityActivation {
        case activated
        case pending
        case notNeeded
    }

    private static var manualAccessibilityAttemptedProcesses = Set<ProcessIdentity>()
    private static var manualAccessibilityRetryDates: [ProcessIdentity: Date] = [:]

    static var authorized: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func read() throws -> String { try readCapture().text }

    // Reject only positively known read-only controls; unavailable editable
    // attributes are common in Electron and are not evidence of read-only text.
    static func isKnownReadOnly(_ element: AXUIElement) -> Bool {
        let editable = read("AXEditable", from: element)
        if editable.error == .success, let value = editable.value,
           CFGetTypeID(value) == CFBooleanGetTypeID() {
            return !CFBooleanGetValue((value as! CFBoolean))
        }
        let role = read(kAXRoleAttribute as String, from: element).value as? String
        return role == (kAXStaticTextRole as String)
    }

    static func readCapture() throws -> SelectionCapture {
        guard authorized else { throw ToolError.message(L10n.text(.selectionPermission)) }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let capture = capture(expectedPID: frontPID, phase: "manual"), !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolError.message(L10n.text(.noSelection))
        }
        return capture
    }

    // Reads the focused element's selection without error text; returns nil when
    // the source software exposes no selection (many Electron canvases do not).
    static func capture(expectedPID: pid_t? = nil, eventSequence: UInt64? = nil,
                        phase: String = "capture", hitTestPoint: CGPoint? = nil) -> SelectionCapture? {
        guard case let .selected(capture) = captureOutcome(expectedPID: expectedPID,
                                                            eventSequence: eventSequence,
                                                            phase: phase,
                                                            hitTestPoint: hitTestPoint) else { return nil }
        return capture
    }

    static func captureOutcome(expectedPID: pid_t? = nil, eventSequence: UInt64? = nil,
                               phase: String = "capture", hitTestPoint: CGPoint? = nil) -> CaptureOutcome {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let targetPID = expectedPID ?? frontPID
        let sequence = eventSequence.map(String.init) ?? "-"
        guard let targetPID, targetPID == frontPID else {
            DebugLog.write("ax seq=\(sequence) phase=\(phase) eventFrontPID=\(expectedPID.map(String.init) ?? "nil") captureFrontPID=\(frontPID.map(String.init) ?? "nil") result=foreground-changed")
            return .unavailable
        }

        var diagnostics: [String] = []
        var sawExplicitEmptySelection = false
        var systemFocus: CFTypeRef?
        let system = AXUIElementCreateSystemWide()
        let systemError = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &systemFocus)
        diagnostics.append("systemFocusedErr=\(systemError.rawValue) type=\(typeName(systemFocus))")

        if systemError == .success, let systemFocus, CFGetTypeID(systemFocus) == AXUIElementGetTypeID() {
            let element = systemFocus as! AXUIElement
            let result = inspect(element, source: "system", expectedPID: targetPID)
            diagnostics.append(result.detail)
            sawExplicitEmptySelection = sawExplicitEmptySelection || result.isExplicitlyEmpty
            if let capture = result.capture {
                log(sequence: sequence, phase: phase, eventPID: expectedPID, capturePID: capture.pid,
                    diagnostics: diagnostics, result: "selected", length: capture.text.utf16.count)
                return .selected(capture)
            }
        }

        // Some Electron and browser fields are exposed only through the app's focused-element query.
        // This is a single focused-element lookup, never a tree scan; the candidate must still match
        // the foreground PID captured for this event.
        let application = AXUIElementCreateApplication(targetPID)
        var applicationFocus: CFTypeRef?
        let applicationError = AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString,
                                                              &applicationFocus)
        diagnostics.append("applicationFocusedErr=\(applicationError.rawValue) type=\(typeName(applicationFocus))")
        if applicationError == .success, let applicationFocus,
           CFGetTypeID(applicationFocus) == AXUIElementGetTypeID() {
            let element = applicationFocus as! AXUIElement
            let result = inspect(element, source: "application", expectedPID: targetPID)
            diagnostics.append(result.detail)
            sawExplicitEmptySelection = sawExplicitEmptySelection || result.isExplicitlyEmpty
            if let capture = result.capture {
                log(sequence: sequence, phase: phase, eventPID: expectedPID, capturePID: capture.pid,
                    diagnostics: diagnostics, result: "selected", length: capture.text.utf16.count)
                return .selected(capture)
            }
        }

        // Focus queries may return kAXErrorNoValue even while a text editor is under the pointer.
        // Hit-test only the event point in the same foreground app; never enumerate its AX tree.
        if let hitTestPoint {
            var hitElement: AXUIElement?
            let hitTestError = AXUIElementCopyElementAtPosition(application,
                                                                  Float(hitTestPoint.x),
                                                                  Float(hitTestPoint.y),
                                                                  &hitElement)
            diagnostics.append("hitTestErr=\(hitTestError.rawValue) type=\(typeName(hitElement)) point=\(Int(hitTestPoint.x)),\(Int(hitTestPoint.y))")
            if hitTestError == .success, let hitElement {
                let result = inspect(hitElement, source: "point", expectedPID: targetPID)
                diagnostics.append(result.detail)
                sawExplicitEmptySelection = sawExplicitEmptySelection || result.isExplicitlyEmpty
                if let capture = result.capture {
                    log(sequence: sequence, phase: phase, eventPID: expectedPID, capturePID: capture.pid,
                        diagnostics: diagnostics, result: "selected", length: capture.text.utf16.count)
                    return .selected(capture)
                }
            }
        }

        var activation: AccessibilityActivation = .notNeeded
        if hitTestPoint != nil, systemError == .noValue, applicationError == .noValue {
            activation = enableManualAccessibilityOnce(pid: targetPID, application: application,
                                                        eventSequence: eventSequence)
            if case .activated = activation { diagnostics.append("manualAccessibility=enabled") }
            if case .pending = activation { diagnostics.append("manualAccessibility=waiting-for-user-retry") }
        }

        log(sequence: sequence, phase: phase, eventPID: expectedPID, capturePID: nil,
            diagnostics: diagnostics,
            result: activation == .activated ? "accessibility-activated" : (activation == .pending ? "accessibility-activation-pending" : (sawExplicitEmptySelection ? "explicitly-empty-selection" : "no-readable-selection")),
            length: nil)
        if activation == .activated { return .accessibilityActivated }
        if activation == .pending { return .accessibilityActivationPending }
        return sawExplicitEmptySelection ? .explicitlyEmpty : .unavailable
    }

    private static func enableManualAccessibilityOnce(pid: pid_t, application: AXUIElement,
                                                       eventSequence: UInt64?) -> AccessibilityActivation {
        let now = Date()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let runningApp = NSRunningApplication(processIdentifier: pid),
              let bundleURL = runningApp.bundleURL,
              let bundleID = runningApp.bundleIdentifier,
              let framework = chromiumFramework(in: bundleURL) else { return .notNeeded }
        let identity = ProcessIdentity(pid: pid, bundleID: bundleID,
                                       launchTime: runningApp.launchDate?.timeIntervalSince1970 ?? 0)
        if manualAccessibilityAttemptedProcesses.contains(identity) {
            return manualAccessibilityRetryDates[identity].map { $0 > now ? .pending : .notNeeded } ?? .notNeeded
        }
        manualAccessibilityAttemptedProcesses.insert(identity)

        let roleAttribute = read("AXRole", from: application)
        let role = roleAttribute.value as? String
        var settable = DarwinBoolean(false)
        let settableError = AXUIElementIsAttributeSettable(application, "AXManualAccessibility" as CFString, &settable)
        guard roleAttribute.error == .success, role == (kAXApplicationRole as String),
              settableError == .success, settable.boolValue else {
            DebugLog.write("ax-accessibility seq=\(eventSequence.map(String.init) ?? "-") pid=\(pid) bundleID=\(bundleID) framework=\(framework) roleErr=\(roleAttribute.error.rawValue) role=\(safeLabel(role)) settableErr=\(settableError.rawValue) settable=\(settable.boolValue) setErr=skipped")
            return .notNeeded
        }

        let error = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if error == .success { manualAccessibilityRetryDates[identity] = now.addingTimeInterval(2.2) }
        DebugLog.write("ax-accessibility seq=\(eventSequence.map(String.init) ?? "-") pid=\(pid) bundleID=\(bundleID) framework=\(framework) role=\(safeLabel(role)) settableErr=\(settableError.rawValue) setErr=\(error.rawValue) retryScheduled=\(error == .success)")
        return error == .success ? .activated : .notNeeded
    }

    private static func chromiumFramework(in bundleURL: URL) -> String? {
        let frameworksURL = bundleURL.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        for name in ["Electron Framework.framework", "Codex Framework.framework", "Chromium Embedded Framework.framework"] {
            if FileManager.default.fileExists(atPath: frameworksURL.appendingPathComponent(name).path) { return name }
        }
        return nil
    }

    private static func inspect(_ element: AXUIElement, source: String,
                                expectedPID: pid_t) -> (capture: SelectionCapture?, isExplicitlyEmpty: Bool, detail: String) {
        var focusedPID: pid_t = 0
        AXUIElementGetPid(element, &focusedPID)
        let roleAttribute = read("AXRole", from: element)
        let subroleAttribute = read("AXSubrole", from: element)
        let role = roleAttribute.value as? String
        let subrole = subroleAttribute.value as? String
        let roleText = safeLabel(role)
        let subroleText = safeLabel(subrole)
        var detail = "source=\(source) focusedPID=\(focusedPID) roleErr=\(roleAttribute.error.rawValue) role=\(roleText) subroleErr=\(subroleAttribute.error.rawValue) subrole=\(subroleText)"

        func skipped(_ reason: String, explicitlyEmpty: Bool = false) -> (SelectionCapture?, Bool, String) {
            (nil, explicitlyEmpty, detail + " skip=\(reason)")
        }

        guard focusedPID == expectedPID else { return skipped("pid-mismatch") }
        guard focusedPID != getpid() else { return skipped("assistant-element") }
        guard roleAttribute.error == .success, let role else { return skipped("role-unavailable") }
        guard !isMenuOrSecureRole(role: role, subrole: subrole) else { return skipped("menu-or-secure-field") }
        // AXTextField can also represent password controls; without a readable subrole it is unsafe
        // to inspect either selected text or AXValue.
        if role == "AXTextField" && (subroleAttribute.error != .success || subrole == nil) {
            return skipped("text-field-subrole-unavailable")
        }

        let selectedAttribute = read(kAXSelectedTextAttribute as String, from: element)
        let selectedText = selectedAttribute.value as? String
        let selectedLength = selectedText?.utf16.count
        let rangeAttribute = readRange(from: element)
        detail += " selectedTextErr=\(selectedAttribute.error.rawValue) selectedTextType=\(typeName(selectedAttribute.value)) selectedTextUTF16=\(selectedLength.map(String.init) ?? "nil") rangeErr=\(rangeAttribute.error.rawValue) rangeType=\(rangeAttribute.type) range=\(rangeAttribute.detail)"

        // Some clients briefly retain the previous selectedText after clearing
        // a selection. A positively empty range must win over that stale text.
        if rangeAttribute.isExplicitlyEmpty { return skipped("explicit-empty-range", explicitlyEmpty: true) }

        if let selectedText, !selectedText.isEmpty {
            guard selectedText.utf16.count <= maxSelectedUTF16Length else { return skipped("selected-text-too-long") }
            detail += " value=not-read-selectedText-available"
            return (makeCapture(selectedText, element: element, pid: focusedPID, range: rangeAttribute.range), false, detail + " result=selectedText")
        }

        guard let range = rangeAttribute.range else {
            detail += " value=not-read-range-unavailable"
            let explicitlyEmpty = rangeAttribute.isExplicitlyEmpty
                || (selectedAttribute.error == .success && selectedText?.isEmpty == true)
            return skipped("selected-text-and-range-unavailable", explicitlyEmpty: explicitlyEmpty)
        }
        guard allowsValueRangeFallback(role: role, subrole: subrole) else {
            detail += " value=not-read-role-not-editable"
            return skipped("value-fallback-role-not-allowed")
        }

        let valueAttribute = read(kAXValueAttribute as String, from: element)
        guard valueAttribute.error == .success, let value = valueAttribute.value as? String else {
            detail += " valueErr=\(valueAttribute.error.rawValue) valueType=\(typeName(valueAttribute.value)) valueUTF16=nil"
            return skipped("value-unavailable")
        }
        let valueLength = value.utf16.count
        detail += " valueErr=\(valueAttribute.error.rawValue) valueType=String valueUTF16=\(valueLength)"
        guard valueLength <= maxValueUTF16Length else { return skipped("value-too-long") }
        guard let selected = utf16Slice(value, range: range) else { return skipped("range-invalid-or-splits-surrogate") }
        guard !selected.isEmpty else { return skipped("empty-range-selection") }
        guard selected.utf16.count <= maxSelectedUTF16Length else { return skipped("selected-text-too-long") }
        return (makeCapture(selected, element: element, pid: focusedPID, range: range), false, detail + " result=value-range-fallback selectedUTF16=\(selected.utf16.count)")
    }

    private static func makeCapture(_ text: String, element: AXUIElement, pid: pid_t,
                                    range: SelectionRange?) -> SelectionCapture {
        SelectionCapture(text: text, bounds: selectionBounds(of: element, range: range), pid: pid,
                         element: element, range: range)
    }

    private static func read(_ name: String, from element: AXUIElement) -> AXAttribute {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        return AXAttribute(error: error, value: value)
    }

    private static func readRange(from element: AXUIElement) -> RangeAttribute {
        let attribute = read(kAXSelectedTextRangeAttribute as String, from: element)
        guard attribute.error == .success else {
            return RangeAttribute(error: attribute.error, type: typeName(attribute.value), range: nil, isExplicitlyEmpty: false, detail: "unavailable")
        }
        guard let value = attribute.value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return RangeAttribute(error: attribute.error, type: typeName(attribute.value), range: nil, isExplicitlyEmpty: false, detail: "wrong-type")
        }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else {
            return RangeAttribute(error: attribute.error, type: "AXValue", range: nil, isExplicitlyEmpty: false, detail: "decode-failed")
        }
        guard range.location >= 0, range.length >= 0, range.location <= Int.max - range.length else {
            return RangeAttribute(error: attribute.error, type: "AXValue", range: nil, isExplicitlyEmpty: false, detail: "invalid-bounds")
        }
        if range.length == 0 {
            return RangeAttribute(error: attribute.error, type: "AXValue", range: nil, isExplicitlyEmpty: true, detail: "location=\(range.location),length=0")
        }
        guard range.length <= maxSelectedUTF16Length else {
            return RangeAttribute(error: attribute.error, type: "AXValue", range: nil, isExplicitlyEmpty: false, detail: "invalid-bounds")
        }
        return RangeAttribute(error: attribute.error, type: "AXValue", range: SelectionRange(location: range.location, length: range.length), isExplicitlyEmpty: false,
                              detail: "location=\(range.location),length=\(range.length)")
    }

    static func isMenuOrSecureRole(role: String?, subrole: String?) -> Bool {
        let rejected = Set(["AXMenu", "AXMenuItem", "AXMenuBar", "AXMenuBarItem", "AXSecureTextField"])
        return role.map { rejected.contains($0) } == true || subrole == "AXSecureTextField"
    }

    static func allowsValueRangeFallback(role: String?, subrole: String?) -> Bool {
        guard !isMenuOrSecureRole(role: role, subrole: subrole),
              let role, ["AXTextField", "AXTextArea", "AXTextView", "AXComboBox"].contains(role) else { return false }
        return role != "AXTextField" || subrole != nil
    }

    static func utf16Slice(_ value: String, range: SelectionRange) -> String? {
        guard range.location >= 0, range.length > 0,
              range.length <= maxSelectedUTF16Length,
              range.location <= Int.max - range.length else { return nil }
        let units = Array(value.utf16)
        let end = range.location + range.length
        guard end <= units.count else { return nil }
        if splitsSurrogatePair(units, at: range.location) || splitsSurrogatePair(units, at: end) { return nil }
        let selected = String(decoding: units[range.location..<end], as: UTF16.self)
        return selected.utf16.count == range.length ? selected : nil
    }

    private static func splitsSurrogatePair(_ units: [UInt16], at boundary: Int) -> Bool {
        guard boundary > 0, boundary < units.count else { return false }
        return (0xD800...0xDBFF).contains(units[boundary - 1])
            && (0xDC00...0xDFFF).contains(units[boundary])
    }

    private static func typeName(_ value: CFTypeRef?) -> String {
        guard let value else { return "nil" }
        let id = CFGetTypeID(value)
        if id == AXUIElementGetTypeID() { return "AXUIElement" }
        if id == AXValueGetTypeID() { return "AXValue" }
        if id == CFStringGetTypeID() { return "String" }
        if id == CFArrayGetTypeID() { return "Array" }
        if id == CFBooleanGetTypeID() { return "Boolean" }
        if id == CFNumberGetTypeID() { return "Number" }
        return "Other"
    }

    private static func safeLabel(_ value: String?) -> String {
        guard let value else { return "nil" }
        let safe = value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
        return String(safe.prefix(48))
    }

    private static func log(sequence: String, phase: String, eventPID: pid_t?, capturePID: pid_t?,
                             diagnostics: [String], result: String, length: Int?) {
        DebugLog.write("ax seq=\(sequence) phase=\(phase) eventFrontPID=\(eventPID.map(String.init) ?? "nil") capturePID=\(capturePID.map(String.init) ?? "nil") result=\(result) selectedUTF16=\(length.map(String.init) ?? "nil") probes={\(diagnostics.joined(separator: ";"))}")
    }

    private static func selectionBounds(of element: AXUIElement, range: SelectionRange?) -> CGRect? {
        guard let range else { return nil }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let cfRangeValue = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, "AXBoundsForRange" as CFString, cfRangeValue, &boundsValue) == .success,
              let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    static func topLeftPoint(from axRect: CGRect) -> CGPoint {
        let screenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? axRect.maxY
        return CGPoint(x: axRect.minX, y: screenHeight - axRect.maxY)
    }

    // CGEvent coordinates use a top-left origin; AppKit panel anchors use
    // the primary display's bottom-left coordinate space.
    static func appKitPoint(fromQuartz point: CGPoint) -> CGPoint {
        let screenHeight = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height ?? NSScreen.main?.frame.height ?? 0
        return CGPoint(x: point.x, y: screenHeight - point.y)
    }
}

final class SelectionHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?

    func register() -> Bool {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let install = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let instance = Unmanaged<SelectionHotKey>.fromOpaque(context).takeUnretainedValue()
            instance.action?()
            return noErr
        }, 1, &event, pointer, &handler)
        guard install == noErr else { return false }
        let id = EventHotKeyID(signature: 0x50534C43, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
