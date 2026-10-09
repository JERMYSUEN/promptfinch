import AppKit
import ApplicationServices

// Global mouse listener with an explicit right-click action menu and optional
// selection bar. Host context menus remain owned by their apps. Also owns the
// automatic paste-back flow after the user chooses a conversion action.

@MainActor private var activeWatcher: SelectionWatcher?

// Ignore only the Escape we post after an explicit companion-menu choice.
// Host/user keyboard input must still invalidate offered actions.
private let contextMenuDismissalMarker: Int64 = 0x50464D454E55

// Flow tracing without content: statuses and counts only, never prompt text.
enum DebugLog {
    static let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PromptSelection/debug.log", isDirectory: false)

    static func write(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let text = "[\(stamp)] \(line)\n"
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(text.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? text.data(using: .utf8)?.write(to: fileURL)
        }
    }
}

enum RightClickCapturePolicy {
    static func delayedInspectMatches(expectedSequence: UInt64?, actualSequence: UInt64,
                                      expectedPID: pid_t?, capturePID: pid_t?) -> Bool {
        expectedSequence == actualSequence && expectedPID != nil && expectedPID == capturePID
    }

    static func canReuseRecentCandidate(candidatePID: pid_t?, frontPID: pid_t?, age: TimeInterval,
                                        candidateGestureSequence: UInt64?, latestGestureSequence: UInt64?,
                                        clickPoint: CGPoint, selectionPoint: CGPoint,
                                        maximumAge: TimeInterval = 8, maximumDistance: CGFloat = 180) -> Bool {
        guard candidatePID != nil, candidatePID == frontPID,
              candidateGestureSequence != nil, candidateGestureSequence == latestGestureSequence,
              age >= 0, age <= maximumAge else { return false }
        let dx = clickPoint.x - selectionPoint.x
        let dy = clickPoint.y - selectionPoint.y
        return dx * dx + dy * dy <= maximumDistance * maximumDistance
    }

    static func shouldWaitForDelayedInspect(hasPendingCapture: Bool, awaitedSequence: UInt64?,
                                            scheduledSequence: UInt64?, allowRetry: Bool) -> Bool {
        !hasPendingCapture && allowRetry && awaitedSequence != nil && awaitedSequence == scheduledSequence
    }

    static func shouldInvalidateRecentCandidate(explicitlyEmpty: Bool,
                                                candidatePID: pid_t?, inspectPID: pid_t?) -> Bool {
        explicitlyEmpty && candidatePID != nil && candidatePID == inspectPID
    }
}

enum SelectionMenuPolicy {
    static func canConvert(sourceMatches: Bool, sourcePID: pid_t, frontPID: pid_t?,
                           enabled: Bool, busy: Bool, age: TimeInterval,
                           maximumAge: TimeInterval = 12) -> Bool {
        sourceMatches && sourcePID == frontPID && enabled && !busy && age >= 0 && age < maximumAge
    }
}

@MainActor
final class SelectionWatcher {
    static let leftKey = "watcherLeftTrigger"
    static let rightKey = "watcherRightTrigger"
    static let pasteBackKey = "pasteBack"

    var onSelection: ((SelectionCapture, CGPoint, UInt64) -> Void)?
    var canStartConversion: (() -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private let panel: FloatingBarPanel
    private let actionMenu = SelectionActionMenu()
    private let frontmostPID: () -> pid_t?
    private let captureForAction: (pid_t, CGPoint, UInt64, String) -> SelectionCapture?
    private let now: () -> Date
    private let presentPanel: (NSPanel) -> Void
    private var barSessionID: UUID?
    private var menuHideWorkItem: DispatchWorkItem?
    private var menuSessionID: UUID?
    private var activationObserver: NSObjectProtocol?
    private var hideWorkItem: DispatchWorkItem?
    private var leftInspectWorkItem: DispatchWorkItem?
    private var scheduledLeftInspectSequence: UInt64?
    private var scheduledLeftInspectPID: pid_t?
    private var scheduledLeftInspectPoint: CGPoint?
    private var scheduledLeftInspectGestureSequence: UInt64?
    private var latestLeftSelectionSequence: UInt64?
    private var recentCapture: SelectionCapture?
    private var recentCaptureDate: Date?
    private var recentCaptureSequence: UInt64?
    private var recentCapturePoint: CGPoint?
    private var pendingRightCapture: SelectionCapture?
    private var pendingRightClickDate: Date?
    private var pendingRightClickAllowed = false
    private var pendingRightEventSequence: UInt64?
    private var pendingRightFrontPID: pid_t?
    private var pendingRightAwaitedInspectSequence: UInt64?
    private var pendingRightFinishWorkItem: DispatchWorkItem?
    private var nextEventSequence: UInt64 = 0

    // Narrow action-time seams allow real button-flow checks without reading
    // another app's text, displaying a panel or installing a global event tap.
    init(floatingBar: FloatingBarPanel? = nil,
         frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
         captureForAction: ((pid_t, CGPoint, UInt64, String) -> SelectionCapture?)? = nil,
         now: @escaping () -> Date = Date.init,
         presentPanel: ((NSPanel) -> Void)? = nil) {
        self.panel = floatingBar ?? FloatingBarPanel()
        self.frontmostPID = frontmostPID
        self.captureForAction = captureForAction ?? {
            TextSelection.capture(expectedPID: $0, eventSequence: $2, phase: $3, hitTestPoint: $1)
        }
        self.now = now
        self.presentPanel = presentPanel ?? { $0.orderFrontRegardless() }
    }

    private static func eventMask(_ type: CGEventType) -> CGEventMask {
        CGEventMask(1) << type.rawValue
    }

    static var leftTrigger: Bool { UserDefaults.standard.object(forKey: leftKey) as? Bool ?? true }
    static var rightTrigger: Bool { UserDefaults.standard.object(forKey: rightKey) as? Bool ?? true }
    static var pasteBack: Bool { UserDefaults.standard.object(forKey: pasteBackKey) as? Bool ?? true }

    func updateLanguage() {
        // Changing language invalidates pending menu choices without generating.
        invalidatePendingActions(reason: "language-changed")
        actionMenu.updateLanguage()
    }

    func invalidatePendingActions(reason: String = "settings-changed") {
        hideActionMenu(reason: reason)
        hideBar(reason: reason)
        cancelScheduledLeftInspect()
        clearPendingRightClick()
        clearRecentCandidate()
        latestLeftSelectionSequence = nil
    }

    func foregroundChanged() {
        invalidatePendingActions(reason: "foreground-changed")
    }

    func keyboardInputReceived() {
        invalidatePendingActions(reason: "keyboard")
    }

    func activate() {
        activeWatcher = self
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.foregroundChanged()
                }
            }
        }
        start()
    }

    func start() {
        guard tap == nil else { return }
        guard TextSelection.authorized else {
            DebugLog.write("watcher start skipped: accessibility permission off")
            return
        }
        let mask = Self.eventMask(.leftMouseDown)
            | Self.eventMask(.leftMouseUp)
            | Self.eventMask(.rightMouseDown)
            | Self.eventMask(.rightMouseUp)
            | Self.eventMask(.keyDown)
        // listenOnly: we never modify or swallow the user's clicks.
        guard let port = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: { _, type, event, _ in
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    Task { @MainActor in
                        activeWatcher?.recoverTap(after: type)
                    }
                    return Unmanaged.passUnretained(event)
                }
                if event.getIntegerValueField(.eventSourceUserData) == contextMenuDismissalMarker {
                    return Unmanaged.passUnretained(event)
                }
                // The CGEvent is only valid inside this callback; copy what we need.
                let location = event.location
                Task { @MainActor in activeWatcher?.process(type: type, location: location) }
                return Unmanaged.passUnretained(event)
            }, userInfo: nil) else {
                DebugLog.write("watcher start failed: event tap unavailable")
                return
            }
        tap = port
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(RunLoop.main.getCFRunLoop(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        DebugLog.write("watcher started")
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(RunLoop.main.getCFRunLoop(), source, .commonModes) }
        tap = nil; source = nil
        invalidatePendingActions(reason: "watcher-stop")
    }

    private func recoverTap(after type: CGEventType) {
        guard let tap else { return }
        let reason = type == .tapDisabledByTimeout ? "timeout" : "user-input"
        DebugLog.write("watcher tap-disabled reason=\(reason) recovery=reenable")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func process(type: CGEventType, location: CGPoint) {
        switch type {
        case .keyDown:
            // Escape, copy, typing or navigation cancels the offered action.
            // listenOnly leaves the original key event with the source app.
            keyboardInputReceived()
        case .leftMouseUp where Self.leftTrigger && !panel.isVisible && menuSessionID == nil:
            let sequence = makeEventSequence()
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            DebugLog.write("event seq=\(sequence) kind=left-up gesture=\(latestLeftSelectionSequence.map(String.init) ?? "nil") frontPID=\(frontPID.map(String.init) ?? "nil")")
            // Chromium updates its AX selection slightly after mouse-up.
            scheduleLeftInspect(mouse: location, eventSequence: sequence,
                                sourceGestureSequence: latestLeftSelectionSequence, expectedPID: frontPID)
        case .leftMouseDown:
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let appKitLocation = TextSelection.appKitPoint(fromQuartz: location)
            if menuSessionID != nil {
                if actionMenu.isVisible && actionMenu.frame.contains(appKitLocation) { break }
                hideActionMenu(reason: "outside-click")
            }
            guard frontPID != ProcessInfo.processInfo.processIdentifier,
                  !(panel.isVisible && panel.frame.contains(appKitLocation)) else { break }
            let sequence = makeEventSequence()
            latestLeftSelectionSequence = sequence
            clearRecentCandidate()
            DebugLog.write("event seq=\(sequence) kind=left-down frontPID=\(frontPID.map(String.init) ?? "nil") recentCandidate=invalidated")
            if panel.isVisible { hideBar(reason: "outside-click", eventSequence: sequence) }
        case .rightMouseDown:
            let sequence = makeEventSequence()
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            DebugLog.write("event seq=\(sequence) kind=right-down frontPID=\(frontPID.map(String.init) ?? "nil")")
            beginRightClick(location: location, eventSequence: sequence, frontPID: frontPID)
        case .rightMouseUp where Self.rightTrigger:
            let sequence = makeEventSequence()
            DebugLog.write("event seq=\(sequence) kind=right-up gesture=\(pendingRightEventSequence.map(String.init) ?? "nil") frontPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier.description ?? "nil")")
            finishRightClick(location: location, eventSequence: sequence)
        case .rightMouseUp:
            DebugLog.write("event seq=\(makeEventSequence()) kind=right-up right-trigger=off")
            clearPendingRightClick()
        default: break
        }
    }

    private func makeEventSequence() -> UInt64 {
        nextEventSequence &+= 1
        return nextEventSequence
    }

    private func inspectSelection(mouse: CGPoint, eventSequence: UInt64,
                                  sourceGestureSequence: UInt64?, expectedPID: pid_t?) {
        let outcome: TextSelection.CaptureOutcome = panel.isVisible
            ? .unavailable
            : TextSelection.captureOutcome(expectedPID: expectedPID, eventSequence: eventSequence,
                                           phase: "left-inspect", hitTestPoint: mouse)
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        switch outcome {
        case let .selected(capture) where capture.pid == expectedPID && frontPID == expectedPID
                && capture.pid != ProcessInfo.processInfo.processIdentifier:
            remember(capture, sourceSequence: sourceGestureSequence, point: mouse)
            if pendingRightClickAllowed,
               RightClickCapturePolicy.delayedInspectMatches(expectedSequence: pendingRightAwaitedInspectSequence,
                                                              actualSequence: eventSequence,
                                                              expectedPID: pendingRightFrontPID,
                                                              capturePID: capture.pid) {
                pendingRightCapture = capture
                pendingRightAwaitedInspectSequence = nil
                DebugLog.write("right seq=\(pendingRightEventSequence.map(String.init) ?? "-") late-selection-captured inspectSeq=\(eventSequence) capturePID=\(capture.pid) selectedUTF16=\(capture.text.utf16.count)")
                return
            }
            if pendingRightClickDate != nil, pendingRightFrontPID == capture.pid {
                DebugLog.write("inspect seq=\(eventSequence) suppressed=right-click-in-progress capturePID=\(capture.pid) awaitedSeq=\(pendingRightAwaitedInspectSequence.map(String.init) ?? "-")")
                return
            }
            DebugLog.write("inspect seq=\(eventSequence) result=selected capturePID=\(capture.pid) frontPID=\(frontPID!) selectedUTF16=\(capture.text.utf16.count) bounds=\(capture.bounds != nil)")
            offerLeftSelection(capture: capture, mouse: mouse, eventSequence: eventSequence)
        case .explicitlyEmpty:
            invalidateRecentCandidate(for: expectedPID, reason: "explicit-empty-selection", inspectSequence: eventSequence)
            if RightClickCapturePolicy.delayedInspectMatches(expectedSequence: pendingRightAwaitedInspectSequence,
                                                             actualSequence: eventSequence,
                                                             expectedPID: pendingRightFrontPID,
                                                             capturePID: expectedPID) {
                pendingRightAwaitedInspectSequence = nil
            }
            DebugLog.write("inspect seq=\(eventSequence) result=explicitly-empty-selection frontPID=\(frontPID.map(String.init) ?? "nil")")
        case .accessibilityActivated:
            invalidateRecentCandidate(for: expectedPID, reason: "accessibility-bootstrap", inspectSequence: eventSequence)
            clearPendingRightClick()
            showAccessibilityNotice(at: mouse, waiting: false)
        case .accessibilityActivationPending:
            invalidateRecentCandidate(for: expectedPID, reason: "accessibility-bootstrap", inspectSequence: eventSequence)
            clearPendingRightClick()
            showAccessibilityNotice(at: mouse, waiting: true)
        case .selected(_), .unavailable:
            if RightClickCapturePolicy.delayedInspectMatches(expectedSequence: pendingRightAwaitedInspectSequence,
                                                             actualSequence: eventSequence,
                                                             expectedPID: pendingRightFrontPID,
                                                             capturePID: expectedPID) {
                pendingRightAwaitedInspectSequence = nil
            }
            DebugLog.write("inspect seq=\(eventSequence) result=skipped capturePID=nil frontPID=\(frontPID.map(String.init) ?? "nil") reason=\(frontPID == expectedPID ? "no-readable-selection" : "foreground-changed")")
        }
    }

    private func scheduleLeftInspect(mouse: CGPoint, eventSequence: UInt64, sourceGestureSequence: UInt64?,
                                     expectedPID: pid_t?, delay: TimeInterval = 0.12) {
        leftInspectWorkItem?.cancel()
        scheduledLeftInspectSequence = eventSequence
        scheduledLeftInspectPID = expectedPID
        scheduledLeftInspectPoint = mouse
        scheduledLeftInspectGestureSequence = sourceGestureSequence
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.scheduledLeftInspectSequence == eventSequence else { return }
            self.leftInspectWorkItem = nil
            self.inspectSelection(mouse: mouse, eventSequence: eventSequence,
                                  sourceGestureSequence: sourceGestureSequence, expectedPID: expectedPID)
            if self.scheduledLeftInspectSequence == eventSequence {
                self.scheduledLeftInspectSequence = nil
                self.scheduledLeftInspectPID = nil
                self.scheduledLeftInspectPoint = nil
                self.scheduledLeftInspectGestureSequence = nil
            }
        }
        leftInspectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func invalidateRecentCandidate(for pid: pid_t?, reason: String, inspectSequence: UInt64) {
        guard let pid, recentCapture?.pid == pid else { return }
        DebugLog.write("recentCandidate invalidated reason=\(reason) inspectSeq=\(inspectSequence) candidateSeq=\(recentCaptureSequence.map(String.init) ?? "-") pid=\(pid)")
        clearRecentCandidate()
    }

    private func beginRightClick(location: CGPoint, eventSequence: UInt64, frontPID: pid_t?) {
        let appKitLocation = TextSelection.appKitPoint(fromQuartz: location)
        let clickedActionMenu = actionMenu.isVisible && actionMenu.frame.contains(appKitLocation)
        hideActionMenu(reason: "new-right-click")
        if clickedActionMenu {
            clearPendingRightClick()
            return
        }
        if panel.isVisible && panel.frame.contains(appKitLocation) {
            hideBar(reason: "right-click-on-floating-bar", eventSequence: eventSequence)
            clearPendingRightClick()
            pendingRightClickDate = Date()
            pendingRightClickAllowed = false
            pendingRightCapture = nil
            pendingRightEventSequence = eventSequence
            pendingRightFrontPID = frontPID
            DebugLog.write("right seq=\(eventSequence) ignored=click-on-floating-bar frontPID=\(frontPID.map(String.init) ?? "nil")")
            return
        }
        if panel.isVisible { hideBar(reason: "right-click", eventSequence: eventSequence) }
        clearPendingRightClick()
        pendingRightCapture = nil
        pendingRightClickDate = Date()
        pendingRightEventSequence = eventSequence
        pendingRightFrontPID = frontPID
        pendingRightClickAllowed = Self.rightTrigger && (canStartConversion?() ?? true)
        guard pendingRightClickAllowed else {
            DebugLog.write("right seq=\(eventSequence) ignored=trigger-disabled-or-busy frontPID=\(frontPID.map(String.init) ?? "nil")")
            return
        }

        let awaitingSequence: UInt64?
        if leftInspectWorkItem != nil, scheduledLeftInspectPID == frontPID,
           let scheduledPoint = scheduledLeftInspectPoint,
           RightClickCapturePolicy.canReuseRecentCandidate(candidatePID: scheduledLeftInspectPID,
                                                            frontPID: frontPID, age: 0,
                                                            candidateGestureSequence: scheduledLeftInspectGestureSequence,
                                                            latestGestureSequence: latestLeftSelectionSequence,
                                                            clickPoint: location, selectionPoint: scheduledPoint) {
            awaitingSequence = scheduledLeftInspectSequence
        } else {
            awaitingSequence = nil
        }
        pendingRightAwaitedInspectSequence = awaitingSequence

        let outcome = TextSelection.captureOutcome(expectedPID: frontPID, eventSequence: eventSequence,
                                                   phase: "right-down", hitTestPoint: location)
        switch outcome {
        case let .selected(fresh) where fresh.pid == frontPID
                && fresh.pid != ProcessInfo.processInfo.processIdentifier
                && !fresh.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            pendingRightCapture = fresh
            pendingRightAwaitedInspectSequence = nil
            DebugLog.write("right seq=\(eventSequence) selection=captured capturePID=\(fresh.pid) selectedUTF16=\(fresh.text.utf16.count)")
        case .accessibilityActivated:
            invalidateRecentCandidate(for: frontPID, reason: "accessibility-bootstrap", inspectSequence: eventSequence)
            cancelScheduledLeftInspect()
            clearPendingRightClick()
            showAccessibilityNotice(at: location, waiting: false)
        case .accessibilityActivationPending:
            invalidateRecentCandidate(for: frontPID, reason: "accessibility-bootstrap", inspectSequence: eventSequence)
            cancelScheduledLeftInspect()
            clearPendingRightClick()
            showAccessibilityNotice(at: location, waiting: true)
        case .explicitlyEmpty:
            invalidateRecentCandidate(for: frontPID, reason: "explicit-empty-selection", inspectSequence: eventSequence)
            if awaitingSequence != nil {
                DebugLog.write("right seq=\(eventSequence) selection=waiting-for-current-inspect inspectSeq=\(awaitingSequence!) frontPID=\(frontPID.map(String.init) ?? "nil")")
            } else {
                pendingRightClickAllowed = false
                pendingRightAwaitedInspectSequence = nil
                DebugLog.write("right seq=\(eventSequence) ignored=explicitly-empty-selection frontPID=\(frontPID.map(String.init) ?? "nil")")
            }
        case .unavailable:
            if awaitingSequence != nil {
                DebugLog.write("right seq=\(eventSequence) selection=waiting-for-current-inspect inspectSeq=\(awaitingSequence!) frontPID=\(frontPID.map(String.init) ?? "nil")")
            } else if let recentCapture, let recentCaptureDate, let recentCapturePoint,
                      RightClickCapturePolicy.canReuseRecentCandidate(candidatePID: recentCapture.pid,
                                                                       frontPID: frontPID,
                                                                       age: Date().timeIntervalSince(recentCaptureDate),
                                                                       candidateGestureSequence: recentCaptureSequence,
                                                                       latestGestureSequence: latestLeftSelectionSequence,
                                                                       clickPoint: location,
                                                                       selectionPoint: recentCapturePoint),
                      !recentCapture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pendingRightCapture = recentCapture
                pendingRightAwaitedInspectSequence = nil
                DebugLog.write("right seq=\(eventSequence) selection=recent-cache capturePID=\(recentCapture.pid) sourceSeq=\(recentCaptureSequence.map(String.init) ?? "-") selectedUTF16=\(recentCapture.text.utf16.count)")
            } else {
                pendingRightClickAllowed = false
                pendingRightAwaitedInspectSequence = nil
                DebugLog.write("right seq=\(eventSequence) ignored=no-readable-selection frontPID=\(frontPID.map(String.init) ?? "nil")")
            }
        case .selected:
            pendingRightClickAllowed = false
            pendingRightAwaitedInspectSequence = nil
            DebugLog.write("right seq=\(eventSequence) ignored=selection-from-other-process frontPID=\(frontPID.map(String.init) ?? "nil")")
        }
    }

    private func finishRightClick(location: CGPoint, eventSequence: UInt64, allowDelayedRetry: Bool = true) {
        let gestureSequence = pendingRightEventSequence
        guard pendingRightClickAllowed,
              let started = pendingRightClickDate,
              Date().timeIntervalSince(started) < 3,
              (canStartConversion?() ?? true) else {
            DebugLog.write("right seq=\(gestureSequence.map(String.init) ?? "nil") up-seq=\(eventSequence) ignored=no-pending-selection-or-busy")
            clearPendingRightClick()
            return
        }
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard frontPID == pendingRightFrontPID,
              let capture = pendingRightCapture,
              capture.pid == frontPID,
              !capture.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            let mayWait = RightClickCapturePolicy.shouldWaitForDelayedInspect(
                hasPendingCapture: pendingRightCapture != nil,
                awaitedSequence: pendingRightAwaitedInspectSequence,
                scheduledSequence: leftInspectWorkItem == nil ? nil : scheduledLeftInspectSequence,
                allowRetry: allowDelayedRetry && frontPID == pendingRightFrontPID
            )
            if mayWait, let gestureSequence {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.pendingRightEventSequence == gestureSequence else { return }
                    self.pendingRightFinishWorkItem = nil
                    self.finishRightClick(location: location, eventSequence: eventSequence, allowDelayedRetry: false)
                }
                pendingRightFinishWorkItem?.cancel()
                pendingRightFinishWorkItem = work
                DebugLog.write("right seq=\(gestureSequence) up-seq=\(eventSequence) deferred=matching-inspect inspectSeq=\(pendingRightAwaitedInspectSequence.map(String.init) ?? "-")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
                return
            }
            DebugLog.write("right seq=\(gestureSequence.map(String.init) ?? "nil") up-seq=\(eventSequence) ignored=selection-lost frontPID=\(frontPID.map(String.init) ?? "nil")")
            clearPendingRightClick()
            return
        }
        cancelScheduledLeftInspect()
        hideBar(reason: "right-click-menu", eventSequence: eventSequence)
        showActionMenu(capture: capture, mouse: location, eventSequence: gestureSequence ?? eventSequence)
        clearRecentCandidate()
        clearPendingRightClick()
    }

    private func showActionMenu(capture: SelectionCapture, mouse: CGPoint, eventSequence: UInt64) {
        hideActionMenu(reason: "replace")
        let session = UUID()
        let offeredAt = now()
        menuSessionID = session
        actionMenu.configure(onConvert: { [weak self] anchor in
            guard let self, self.menuSessionID == session,
                  self.frontmostPID() == capture.pid,
                  Self.rightTrigger, self.canStartConversion?() ?? true else { return }
            self.menuHideWorkItem?.cancel()
            self.menuHideWorkItem = nil
            // Dismiss the host menu only after an explicit conversion choice.
            PasteBack.dismissContextMenu(processID: capture.pid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                guard let self, self.menuSessionID == session else { return }
                let current = self.captureForAction(capture.pid, mouse, eventSequence, "right-menu-confirm")
                let matches = current.map { capture.matchesForConversion(as: $0) } ?? false
                let allowed = SelectionMenuPolicy.canConvert(
                    sourceMatches: matches, sourcePID: capture.pid, frontPID: self.frontmostPID(),
                    enabled: Self.rightTrigger, busy: !(self.canStartConversion?() ?? true),
                    age: self.now().timeIntervalSince(offeredAt))
                self.hideActionMenu(reason: allowed ? "convert-chosen" : "selection-changed")
                guard allowed else {
                    DebugLog.write("right-menu seq=\(eventSequence) rejected=source-changed-or-unavailable")
                    self.showMenuNotice(L10n.text(.selectionExpired), at: mouse)
                    return
                }
                DebugLog.write("right-menu seq=\(eventSequence) action=convert capturePID=\(capture.pid) selectedUTF16=\(capture.text.utf16.count)")
                self.onSelection?(capture, anchor, eventSequence)
            }
        }, onCancel: { [weak self] in self?.hideActionMenu(reason: "cancel-chosen") })
        actionMenu.placeAbove(pointer: TextSelection.appKitPoint(fromQuartz: mouse))
        actionMenu.orderFrontRegardless()
        DebugLog.write("right-menu seq=\(eventSequence) offered capturePID=\(capture.pid) generation=not-started")
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.menuSessionID == session else { return }
            self.hideActionMenu(reason: "timeout")
        }
        menuHideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: item)
    }

    private func hideActionMenu(reason: String) {
        menuHideWorkItem?.cancel(); menuHideWorkItem = nil
        if menuSessionID != nil { DebugLog.write("right-menu hidden reason=\(reason)") }
        menuSessionID = nil
        actionMenu.dismiss()
    }

    private func showMenuNotice(_ message: String, at mouse: CGPoint) {
        panel.showNotice(message)
        panel.placeNear(topLeft: TextSelection.appKitPoint(fromQuartz: mouse))
        presentPanel(panel)
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hideBar(reason: "menu-notice-timeout") }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: item)
    }

    private func remember(_ capture: SelectionCapture, sourceSequence: UInt64?, point: CGPoint) {
        guard let sourceSequence else { return }
        recentCapture = capture
        recentCaptureDate = Date()
        recentCaptureSequence = sourceSequence
        recentCapturePoint = point
    }

    private func clearRecentCandidate() {
        recentCapture = nil
        recentCaptureDate = nil
        recentCaptureSequence = nil
        recentCapturePoint = nil
    }

    private func cancelScheduledLeftInspect() {
        leftInspectWorkItem?.cancel()
        leftInspectWorkItem = nil
        scheduledLeftInspectSequence = nil
        scheduledLeftInspectPID = nil
        scheduledLeftInspectPoint = nil
        scheduledLeftInspectGestureSequence = nil
    }

    private func showAccessibilityNotice(at mouse: CGPoint, waiting: Bool) {
        let message = waiting
            ? L10n.text(.accessibilityWarming)
            : L10n.text(.accessibilityEnabled)
        panel.showNotice(message)
        panel.placeNear(topLeft: TextSelection.appKitPoint(fromQuartz: mouse))
        presentPanel(panel)
        DebugLog.write("floatingBar notice=accessibility-bootstrap waiting=\(waiting) frame=\(Int(panel.frame.minX)),\(Int(panel.frame.minY)),\(Int(panel.frame.width)),\(Int(panel.frame.height))")
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hideBar(reason: "accessibility-notice-timeout") }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: item)
    }

    func offerLeftSelection(capture: SelectionCapture, mouse: CGPoint, eventSequence: UInt64) {
        hideBar(reason: "replace", eventSequence: eventSequence)
        let session = UUID()
        let offeredAt = now()
        barSessionID = session
        let top = capture.bounds.map { TextSelection.topLeftPoint(from: $0) } ?? mouse
        panel.configure(text: capture.text) { [weak self] barTopLeft in
            guard let self, self.barSessionID == session else { return }
            let frontPID = self.frontmostPID()
            let mayInspect = SelectionMenuPolicy.canConvert(
                sourceMatches: true, sourcePID: capture.pid, frontPID: frontPID,
                enabled: Self.leftTrigger, busy: !(self.canStartConversion?() ?? true),
                age: self.now().timeIntervalSince(offeredAt), maximumAge: 8)
            let current = mayInspect
                ? self.captureForAction(capture.pid, mouse, eventSequence, "left-bar-confirm") : nil
            let allowed = mayInspect && SelectionMenuPolicy.canConvert(
                sourceMatches: current.map { capture.matchesForConversion(as: $0) } ?? false,
                sourcePID: capture.pid, frontPID: self.frontmostPID(),
                enabled: Self.leftTrigger, busy: !(self.canStartConversion?() ?? true),
                age: self.now().timeIntervalSince(offeredAt), maximumAge: 8)
            self.hideBar(reason: allowed ? "convert-chosen" : "selection-changed", eventSequence: eventSequence)
            guard allowed else {
                DebugLog.write("floatingBar seq=\(eventSequence) rejected=source-changed-disabled-expired-or-busy")
                self.showMenuNotice(L10n.text(.selectionExpired), at: mouse)
                return
            }
            self.onSelection?(capture, barTopLeft, eventSequence)
        }
        panel.placeNear(topLeft: top)
        presentPanel(panel)
        DebugLog.write("floatingBar seq=\(eventSequence) shown capturePID=\(capture.pid) sourceBounds=\(capture.bounds != nil) frame=\(Int(panel.frame.minX)),\(Int(panel.frame.minY)),\(Int(panel.frame.width)),\(Int(panel.frame.height)) screens=\(NSScreen.screens.count)")
        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hideBar(reason: "eight-second-timeout", eventSequence: eventSequence) }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: item)
    }

    private func hideBar(reason: String, eventSequence: UInt64? = nil) {
        hideWorkItem?.cancel(); hideWorkItem = nil
        barSessionID = nil
        if panel.isVisible {
            DebugLog.write("floatingBar seq=\(eventSequence.map(String.init) ?? "-") hidden reason=\(reason)")
        }
        panel.dismiss()
    }

    private func clearPendingRightClick() {
        pendingRightFinishWorkItem?.cancel(); pendingRightFinishWorkItem = nil
        pendingRightCapture = nil
        pendingRightClickDate = nil
        pendingRightClickAllowed = false
        pendingRightEventSequence = nil
        pendingRightFrontPID = nil
        pendingRightAwaitedInspectSequence = nil
    }
}

@MainActor
final class SelectionActionMenu: NSPanel {
    private let convert = SelectionMenuButton(title: "", target: nil, action: nil)
    private let cancel = SelectionMenuButton(title: "", target: nil, action: nil)
    private var onConvert: ((CGPoint) -> Void)?
    private var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 232, height: 94),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear
        level = .popUpMenu; hasShadow = true
        let view = FlippedView(frame: NSRect(x: 0, y: 0, width: 232, height: 94))
        let effect = NSVisualEffectView(frame: view.bounds)
        effect.material = .menu; effect.blendingMode = .behindWindow; effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8; effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        view.addSubview(effect)
        view.setAccessibilityRole(.menu)
        view.setAccessibilityLabel(L10n.text(.actionMenu))

        let title = NSTextField(labelWithString: "PromptFinch")
        title.font = .systemFont(ofSize: 11)
        title.textColor = .secondaryLabelColor
        title.frame = NSRect(x: 12, y: 7, width: 208, height: 16)
        view.addSubview(title)
        convert.title = "⇄  " + L10n.text(.convert)
        convert.target = self; convert.action = #selector(chooseConversion)
        convert.frame = NSRect(x: 5, y: 25, width: 222, height: 30)
        convert.toolTip = L10n.text(.convertTooltip)
        view.addSubview(convert)
        let separator = NSBox(frame: NSRect(x: 10, y: 59, width: 212, height: 1))
        separator.boxType = .separator
        view.addSubview(separator)
        cancel.title = L10n.text(.cancel)
        cancel.target = self; cancel.action = #selector(cancelChoice)
        cancel.frame = NSRect(x: 5, y: 63, width: 222, height: 26)
        view.addSubview(cancel)
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Offering a menu has no conversion side effects. Only chooseConversion
    // invokes the supplied action, once; dismiss and cancel discard it.
    func updateLanguage() {
        convert.title = "⇄  " + L10n.text(.convert)
        convert.toolTip = L10n.text(.convertTooltip)
        cancel.title = L10n.text(.cancel)
        contentView?.setAccessibilityLabel(L10n.text(.actionMenu))
        let width = max(232, ceil(convert.intrinsicContentSize.width) + 30)
        setContentSize(NSSize(width: width, height: 94))
        convert.frame.size.width = width - 10
        cancel.frame.size.width = width - 10
    }

    func configure(onConvert: @escaping (CGPoint) -> Void, onCancel: @escaping () -> Void) {
        updateLanguage()
        self.onConvert = onConvert
        self.onCancel = onCancel
    }

    func placeAbove(pointer: CGPoint) {
        let visible = NSScreen.screens.first(where: { $0.frame.contains(pointer) })?.visibleFrame
            ?? NSScreen.main?.visibleFrame ?? frame
        var x = pointer.x + 6
        var y = pointer.y + 12
        if y + frame.height > visible.maxY {
            x = pointer.x - frame.width - 12
            y = pointer.y - frame.height
        }
        x = min(max(x, visible.minX + 4), visible.maxX - frame.width - 4)
        y = min(max(y, visible.minY + 4), visible.maxY - frame.height - 4)
        setFrameOrigin(CGPoint(x: x, y: y))
    }

    func dismiss() {
        onConvert = nil; onCancel = nil
        orderOut(nil)
    }

    @objc func chooseConversion() {
        let action = onConvert
        let anchor = CGPoint(x: frame.minX, y: frame.maxY)
        dismiss()
        action?(anchor)
    }

    @objc func cancelChoice() {
        let action = onCancel
        dismiss()
        action?()
    }
}

@MainActor
private final class SelectionMenuButton: NSButton {
    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        alignment = .left
        font = .menuFont(ofSize: 13)
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = 4
        setButtonType(.momentaryChange)
        setAccessibilityRole(.menuItem)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        hoverArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor
        contentTintColor = .alternateSelectedControlTextColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
        contentTintColor = .labelColor
    }
}

@MainActor
final class FloatingBarPanel: NSPanel {
    private var action: ((CGPoint) -> Void)?
    private let button = NSButton(title: "⇄ " + L10n.text(.convert), target: nil, action: nil)
    private let noticeLabel = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 158, height: 30),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear
        level = .popUpMenu
        isMovable = false; hasShadow = true

        let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 158, height: 30))
        effect.material = .hudWindow; effect.blendingMode = .behindWindow
        effect.state = .active; effect.wantsLayer = true
        effect.autoresizingMask = [.width, .height]
        effect.layer?.cornerRadius = 9; effect.layer?.masksToBounds = true
        button.isBordered = false
        button.contentTintColor = .white
        button.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        button.setButtonType(.momentaryChange)
        button.frame = effect.bounds.insetBy(dx: 8, dy: 2)
        button.autoresizingMask = [.width, .height]
        button.target = self; button.action = #selector(fire)
        effect.addSubview(button)
        noticeLabel.textColor = .white
        noticeLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        noticeLabel.alignment = .center
        noticeLabel.frame = effect.bounds.insetBy(dx: 12, dy: 5)
        noticeLabel.autoresizingMask = [.width, .height]
        noticeLabel.isHidden = true
        effect.addSubview(noticeLabel)
        contentView = effect
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func configure(text: String, action: @escaping (CGPoint) -> Void) {
        self.action = action
        button.title = "⇄ " + L10n.text(.convert)
        setContentSize(NSSize(width: max(158, ceil(button.intrinsicContentSize.width) + 20), height: 30))
        button.isEnabled = true
        button.isHidden = false
        noticeLabel.isHidden = true
        button.toolTip = text.count > 40 ? String(text.prefix(40)) + "…" : text
    }

    func showNotice(_ message: String) {
        action = nil
        setContentSize(NSSize(width: 360, height: 72))
        button.isHidden = true
        noticeLabel.stringValue = message
        noticeLabel.isHidden = false
    }

    func dismiss() {
        action = nil
        orderOut(nil)
    }

    func placeNear(topLeft: CGPoint) {
        let wanted = NSRect(x: topLeft.x, y: topLeft.y + 6, width: frame.width, height: frame.height)
        let visible = NSScreen.screens.first(where: { $0.visibleFrame.intersects(wanted) })?.visibleFrame ?? wanted
        let x = min(max(wanted.minX, visible.minX + 4), visible.maxX - wanted.width - 4)
        let y = min(wanted.maxY, visible.maxY - 4)
        setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    @objc private func fire() {
        DebugLog.write("bar button fired")
        // Anchor the result window where the bar was, right next to the text.
        let topLeft = CGPoint(x: frame.minX, y: frame.maxY)
        let handler = action
        action = nil
        orderOut(nil)
        handler?(topLeft)
    }
}

// Floating result window: appears next to the selection, shows the generated
// prompt without switching to the main app window. Non-activating, so the
// source app keeps keyboard focus and the paste-back ⌘V lands there.
@MainActor
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class ResultPanel: NSPanel {
    var onPasteBack: (() -> Void)?
    var onCopy: (() -> Void)?
    var onClose: (() -> Void)?

    private let header = NSTextField(labelWithString: L10n.text(.englishPrompt))
    private let closeButton = NSButton(title: "✕", target: nil, action: nil)
    private let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 438, height: 158))
    private let statusLine = NSTextField(wrappingLabelWithString: "")
    private let pasteButton = NSButton(title: L10n.text(.pasteBack), target: nil, action: nil)
    private let copyButton = NSButton(title: L10n.text(.copy), target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private let busyLabel = NSTextField(labelWithString: L10n.text(.converting))

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 470, height: 300),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear
        level = .popUpMenu
        hasShadow = true
        isMovableByWindowBackground = true

        let container = FlippedView(frame: NSRect(x: 0, y: 0, width: 470, height: 300))
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .hudWindow; effect.blendingMode = .behindWindow
        effect.state = .active; effect.wantsLayer = true
        effect.layer?.cornerRadius = 12; effect.layer?.masksToBounds = true
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        header.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .white
        header.frame = NSRect(x: 16, y: 12, width: 300, height: 22)
        container.addSubview(header)

        closeButton.isBordered = false
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.7)
        closeButton.font = NSFont.systemFont(ofSize: 13)
        closeButton.frame = NSRect(x: 432, y: 10, width: 26, height: 22)
        closeButton.target = self; closeButton.action = #selector(closeTapped)
        container.addSubview(closeButton)

        let scroll = NSScrollView(frame: NSRect(x: 16, y: 40, width: 438, height: 158))
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        textView.isEditable = false; textView.isSelectable = true
        textView.drawsBackground = false; textView.backgroundColor = .clear
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textColor = .white
        textView.textContainerInset = NSSize(width: 6, height: 8)
        scroll.documentView = textView
        container.addSubview(scroll)

        spinner.style = .spinning
        spinner.frame = NSRect(x: 225, y: 92, width: 20, height: 20)
        spinner.isDisplayedWhenStopped = false
        container.addSubview(spinner)
        busyLabel.font = NSFont.systemFont(ofSize: 12)
        busyLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        busyLabel.alignment = .center
        busyLabel.frame = NSRect(x: 16, y: 122, width: 438, height: 18)
        container.addSubview(busyLabel)

        statusLine.font = NSFont.systemFont(ofSize: 12)
        statusLine.textColor = NSColor.white.withAlphaComponent(0.75)
        statusLine.frame = NSRect(x: 16, y: 204, width: 438, height: 36)
        container.addSubview(statusLine)

        for (button, action) in [(pasteButton, #selector(pasteTapped)), (copyButton, #selector(copyTapped))] {
            button.bezelStyle = .rounded
            button.frame = .zero
            button.target = self; button.action = action
            container.addSubview(button)
        }
        pasteButton.frame = NSRect(x: 16, y: 248, width: 190, height: 30)
        copyButton.frame = NSRect(x: 214, y: 248, width: 110, height: 30)
        contentView = container
        closeButton.setAccessibilityLabel(L10n.text(.close))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateLanguage(from previous: UILanguage) {
        header.stringValue = L10n.text(.englishPrompt)
        pasteButton.title = L10n.text(.pasteBack)
        copyButton.title = L10n.text(.copy)
        busyLabel.stringValue = L10n.text(.converting)
        closeButton.setAccessibilityLabel(L10n.text(.close))
        statusLine.stringValue = L10n.relocalize(statusLine.stringValue, from: previous)
    }

    func present(anchor: CGPoint, eventSequence: UInt64? = nil) {
        let wanted = NSRect(x: anchor.x, y: anchor.y + 8, width: 470, height: 300)
        let matchingScreen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(wanted) })
        let visible = matchingScreen?.visibleFrame ?? wanted
        let x = min(max(wanted.minX, visible.minX + 4), visible.maxX - wanted.width - 4)
        let y = min(wanted.maxY, visible.maxY - 4)
        setFrameTopLeftPoint(NSPoint(x: x, y: y))
        textView.string = ""
        statusLine.stringValue = ""
        busy(true)
        orderFrontRegardless()
        DebugLog.write("resultPanel seq=\(eventSequence.map(String.init) ?? "-") presented=true screenMatch=\(matchingScreen != nil) screenCount=\(NSScreen.screens.count) anchor=\(Int(anchor.x)),\(Int(anchor.y)) visible=\(Int(visible.minX)),\(Int(visible.minY)),\(Int(visible.width)),\(Int(visible.height)) frame=\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))")
    }

    func finish(prompt: String, status: String, canPasteBack: Bool, error: Bool, eventSequence: UInt64? = nil) {
        busy(false)
        textView.string = prompt
        statusLine.stringValue = status
        statusLine.textColor = error ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.75)
        pasteButton.isHidden = !canPasteBack
        copyButton.isHidden = false
        orderFrontRegardless()
        DebugLog.write("resultPanel seq=\(eventSequence.map(String.init) ?? "-") finished=true visible=\(isVisible) promptUTF16=\(prompt.utf16.count) pasteButton=\(!pasteButton.isHidden) error=\(error)")
    }

    func fail(status: String, eventSequence: UInt64? = nil) {
        busy(false)
        textView.string = ""
        statusLine.stringValue = status
        statusLine.textColor = .systemOrange
        pasteButton.isHidden = true; copyButton.isHidden = true
        DebugLog.write("resultPanel seq=\(eventSequence.map(String.init) ?? "-") failed=true visible=\(isVisible)")
    }

    // Delayed clipboard outcomes update the existing result only. They never
    // reopen a closed panel or replace the generated text/action buttons.
    func updateStatus(_ status: String, error: Bool) {
        statusLine.stringValue = status
        statusLine.textColor = error ? NSColor.systemOrange : NSColor.white.withAlphaComponent(0.75)
    }

    private func busy(_ running: Bool) {
        spinner.isHidden = !running
        busyLabel.isHidden = !running
        if running { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        if running {
            pasteButton.isHidden = true
            copyButton.isHidden = true
        }
    }

    @objc private func pasteTapped() { onPasteBack?() }
    @objc private func copyTapped() { onCopy?() }
    @objc private func closeTapped() { onClose?() }
}

struct PasteRestoreLease: Equatable {
    let id = UUID()

    func isCurrent(_ current: PasteRestoreLease?) -> Bool { self == current }
}

enum ClipboardRestorePolicy {
    static func shouldRestore(currentCount: Int, currentText: String?, generatedText: String, afterWrite: Int) -> Bool {
        currentCount == afterWrite || currentText == generatedText
    }
}

struct PasteboardItemSnapshot {
    let types: [NSPasteboard.PasteboardType]
    let data: [NSPasteboard.PasteboardType: Data]
}

struct ClipboardRestoreTransaction {
    fileprivate let backup: [PasteboardItemSnapshot]
    fileprivate let written: String
    let afterWrite: Int
    fileprivate let lease: PasteRestoreLease
    let hadBackup: Bool
}

enum ClipboardRestoreOutcome: Equatable {
    case restored
    case skippedNewerCopy
    case failed
    case superseded
}

enum PasteBackOutcome: Equatable {
    case notAttempted
    // The clipboard could not be safely snapshotted/prepared/recovered. Callers
    // must preserve it and offer the result without an automatic fallback copy.
    case clipboardUnavailable
    // Posting Command-V is a request, not evidence that a host editor wrote it.
    case pasteRequested
}

// Owns the short clipboard transaction. An injected pasteboard lets tests
// exercise real delayed writes without touching the user's general clipboard.
@MainActor
final class ClipboardRestoreCoordinator {
    private let pasteboard: NSPasteboard
    private var pendingRestore: DispatchWorkItem?
    private var pendingLease: PasteRestoreLease?
    private var pendingBackup: [PasteboardItemSnapshot]?
    private var pendingWrittenText: String?
    private var pendingCompletion: ((ClipboardRestoreOutcome) -> Void)?
    private let writeString: (String) -> Bool
    private let writeItems: ([NSPasteboardItem]) -> Bool

    init(pasteboard: NSPasteboard,
         writeString: ((String) -> Bool)? = nil,
         writeItems: (([NSPasteboardItem]) -> Bool)? = nil) {
        self.pasteboard = pasteboard
        self.writeString = writeString ?? { pasteboard.setString($0, forType: .string) }
        self.writeItems = writeItems ?? { pasteboard.writeObjects($0) }
    }

    func backUp() -> [PasteboardItemSnapshot] {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return [] }
        return items.map { item in
            let types = item.types
            let payload = Dictionary(uniqueKeysWithValues: types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
            return PasteboardItemSnapshot(types: types, data: payload)
        }
    }

    // Restore unless the user copied something else in the meantime.
    // Chromium increments changeCount on paste even when the text is unchanged,
    // so compare the string, not only the count.
    private func restore(_ backup: [PasteboardItemSnapshot], written: String,
                         afterWrite: Int) -> ClipboardRestoreOutcome {
        guard ClipboardRestorePolicy.shouldRestore(currentCount: pasteboard.changeCount,
                                                   currentText: pasteboard.string(forType: .string),
                                                   generatedText: written, afterWrite: afterWrite) else { return .skippedNewerCopy }
        return writeBackup(backup) ? .restored : .failed
    }

    private func writeBackup(_ backup: [PasteboardItemSnapshot]) -> Bool {
        guard !backup.isEmpty else {
            pasteboard.clearContents()
            return true
        }
        var items: [NSPasteboardItem] = []
        for entry in backup {
            let item = NSPasteboardItem()
            for type in entry.types {
                guard let data = entry.data[type] else { return false }
                guard item.setData(data, forType: type) else { return false }
            }
            items.append(item)
        }
        pasteboard.clearContents()
        return writeItems(items)
    }

    func write(_ text: String) -> Bool {
        // A deliberate copy must win over any delayed clipboard restoration.
        let backup = backUp()
        cancelPendingRestore(outcome: .skippedNewerCopy)
        guard writeImmediately(text) else {
            _ = writeBackup(backup)
            return false
        }
        return true
    }

    func preparePaste(_ text: String,
                      onFailure: ((ClipboardRestoreOutcome) -> Void)? = nil) -> ClipboardRestoreTransaction? {
        let backup: [PasteboardItemSnapshot]
        if let pendingBackup, let pendingWrittenText,
           pasteboard.string(forType: .string) == pendingWrittenText {
            // Keep the original snapshot if another paste starts before restore.
            backup = pendingBackup
        } else {
            backup = backUp()
        }
        guard backup.allSatisfy({ entry in entry.types.allSatisfy { entry.data[$0] != nil } }) else {
            // A promised/custom clipboard type that cannot be snapshotted must
            // remain untouched rather than be lost during a temporary paste.
            onFailure?(.failed)
            return nil
        }
        cancelPendingRestore(outcome: .superseded)
        guard writeImmediately(text) else {
            // setString can fail after clearContents. Recover the snapshot now;
            // there is no async gap in which a newer user copy can be overwritten.
            onFailure?(writeBackup(backup) ? .restored : .failed)
            return nil
        }
        let lease = PasteRestoreLease()
        pendingLease = lease
        pendingBackup = backup
        pendingWrittenText = text
        return ClipboardRestoreTransaction(backup: backup, written: text, afterWrite: pasteboard.changeCount,
                                           lease: lease, hadBackup: !backup.isEmpty)
    }

    func scheduleRestore(_ transaction: ClipboardRestoreTransaction, after delay: TimeInterval = 0.4,
                         onRestore: ((ClipboardRestoreOutcome) -> Void)? = nil) {
        guard transaction.lease.isCurrent(pendingLease) else {
            onRestore?(.superseded)
            return
        }
        pendingRestore?.cancel()
        pendingCompletion = onRestore
        let work = DispatchWorkItem { [weak self] in
            guard let self, transaction.lease.isCurrent(self.pendingLease) else { return }
            let outcome = self.restore(transaction.backup, written: transaction.written,
                                       afterWrite: transaction.afterWrite)
            self.cancelPendingRestore(outcome: outcome)
        }
        pendingRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    @discardableResult
    func restoreImmediately(_ transaction: ClipboardRestoreTransaction,
                            onRestore: ((ClipboardRestoreOutcome) -> Void)? = nil) -> ClipboardRestoreOutcome {
        guard transaction.lease.isCurrent(pendingLease) else {
            onRestore?(.superseded)
            return .superseded
        }
        let outcome = restore(transaction.backup, written: transaction.written, afterWrite: transaction.afterWrite)
        cancelPendingRestore(outcome: outcome)
        onRestore?(outcome)
        return outcome
    }

    private func writeImmediately(_ text: String) -> Bool {
        pasteboard.clearContents()
        return writeString(text)
    }

    private func cancelPendingRestore(outcome: ClipboardRestoreOutcome) {
        let completion = pendingCompletion
        pendingRestore?.cancel()
        pendingRestore = nil
        pendingLease = nil
        pendingBackup = nil
        pendingWrittenText = nil
        pendingCompletion = nil
        // Clear state before reporting, so a callback may safely start a new copy
        // or paste without the previous transaction erasing its lease afterward.
        completion?(outcome)
    }
}

// Owns target verification and the clipboard/key request. Its narrow closures
// let regression tests exercise the actual flow with fake targets and no keys.
@MainActor
final class PasteBackCoordinator {
    private let clipboard: ClipboardRestoreCoordinator
    private let authorized: () -> Bool
    private let frontmostPID: () -> pid_t?
    private let capture: (pid_t) -> SelectionCapture?
    private let isKnownReadOnly: (AXUIElement) -> Bool
    private let sendCommandV: () -> Bool
    private let restoreDelay: TimeInterval

    init(clipboard: ClipboardRestoreCoordinator, authorized: @escaping () -> Bool,
         frontmostPID: @escaping () -> pid_t?, capture: @escaping (pid_t) -> SelectionCapture?,
         isKnownReadOnly: @escaping (AXUIElement) -> Bool, sendCommandV: @escaping () -> Bool,
         restoreDelay: TimeInterval = 0.4) {
        self.clipboard = clipboard
        self.authorized = authorized
        self.frontmostPID = frontmostPID
        self.capture = capture
        self.isKnownReadOnly = isKnownReadOnly
        self.sendCommandV = sendCommandV
        self.restoreDelay = restoreDelay
    }

    func paste(_ text: String, expectedTarget: SelectionCapture?,
               onRestore: ((ClipboardRestoreOutcome) -> Void)? = nil) -> PasteBackOutcome {
        guard authorized(), let expectedTarget, expectedTarget.hasReliableRange,
              frontmostPID() == expectedTarget.pid,
              let current = capture(expectedTarget.pid),
              expectedTarget.stillTargetsSameSelection(as: current),
              !isKnownReadOnly(current.element),
              frontmostPID() == expectedTarget.pid else { return .notAttempted }

        guard let transaction = clipboard.preparePaste(text, onFailure: onRestore) else { return .clipboardUnavailable }
        guard frontmostPID() == expectedTarget.pid, sendCommandV() else {
            let recovery = clipboard.restoreImmediately(transaction, onRestore: onRestore)
            return recovery == .restored ? .notAttempted : .clipboardUnavailable
        }
        clipboard.scheduleRestore(transaction, after: restoreDelay, onRestore: onRestore)
        return .pasteRequested
    }
}

// Clipboard backup/restore around the simulated ⌘V paste-back.
@MainActor
enum PasteBack {
    private static let clipboard = ClipboardRestoreCoordinator(pasteboard: .general)
    private static let coordinator = PasteBackCoordinator(
        clipboard: clipboard, authorized: { TextSelection.authorized },
        frontmostPID: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        capture: { TextSelection.capture(expectedPID: $0, phase: "paste-target") },
        isKnownReadOnly: { TextSelection.isKnownReadOnly($0) }, sendCommandV: { sendCommandV() })

    static func write(_ text: String) -> Bool { clipboard.write(text) }

    static func sendCommandV() -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0x09, keyDown: false) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        usleep(60_000)
        up.post(tap: .cghidEventTap)
        return true
    }

    static func dismissContextMenu(processID: pid_t) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0x35, keyDown: false) else { return }
        down.setIntegerValueField(.eventSourceUserData, value: contextMenuDismissalMarker)
        up.setIntegerValueField(.eventSourceUserData, value: contextMenuDismissalMarker)
        down.postToPid(processID)
        usleep(30_000)
        up.postToPid(processID)
    }

    // The host may ignore Command-V. Never report a confirmed replacement;
    // callers show the request status and the later clipboard outcome separately.
    static func paste(_ text: String, expectedTarget: SelectionCapture?,
                      onRestore: ((ClipboardRestoreOutcome) -> Void)? = nil) -> PasteBackOutcome {
        let outcome = coordinator.paste(text, expectedTarget: expectedTarget) { restored in
            DebugLog.write("paste: clipboard-outcome=\(restored)")
            onRestore?(restored)
        }
        DebugLog.write("paste: request-outcome=\(outcome) UTF16=\(text.utf16.count)")
        return outcome
    }
}
