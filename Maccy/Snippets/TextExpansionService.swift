import AppKit
import Carbon
import Defaults
import Observation
import Security

@MainActor
@Observable
final class TextExpansionService {
  static let shared = TextExpansionService()
  private(set) var status = "Text expansion is off."
  private(set) var isListening = false
  let isSandboxed: Bool = {
    guard let task = SecTaskCreateFromSelf(nil) else { return true }
    return (SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool) == true
  }()

  @ObservationIgnored private var settingsTask: Task<Void, Never>?
  @ObservationIgnored private var healthTask: Task<Void, Never>?
  @ObservationIgnored private var policyTasks: [Task<Void, Never>] = []
  @ObservationIgnored private var workspaceObserver: NSObjectProtocol?
  @ObservationIgnored private var inputSourceObserver: NSObjectProtocol?
  @ObservationIgnored private var snippetLibraryObserver: NSObjectProtocol?
  @ObservationIgnored private var policyGeneration: UInt64 = 0
  @ObservationIgnored private var refreshSequence: UInt64 = 0
  @ObservationIgnored private var lastPolicy: ExpansionTapPolicy?
  @ObservationIgnored private lazy var runtime = ExpansionEventTapRuntime { [weak self] candidate in
    guard let self else { return }
    await self.handle(candidate)
  }
  @ObservationIgnored private var feedbackPanel: NSPanel?
  @ObservationIgnored private var feedbackTask: Task<Void, Never>?
  static let eventTag = ExpansionEventTapRuntime.eventTag

  func start() {
    guard settingsTask == nil else { return }
    workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in await self?.refreshNow() }
    }
    inputSourceObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
      object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in await self?.refreshNow() }
    }
    snippetLibraryObserver = NotificationCenter.default.addObserver(
      forName: SnippetLibrary.definitionsDidChange, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in await self?.refreshNow() }
    }
    policyTasks = [
      Task { [weak self] in
        for await _ in Defaults.updates(.expansionExcludedApps) { await self?.refreshNow() }
      },
      Task { [weak self] in
        for await _ in Defaults.updates(.ignoredApps) { await self?.refreshNow() }
      },
      Task { [weak self] in
        for await _ in Defaults.updates(.ignoreAllAppsExceptListed) { await self?.refreshNow() }
      },
    ]
    settingsTask = Task { [weak self] in
      guard let self else { return }
      await self.refreshNow()
      for await enabled in Defaults.updates(.textExpansionEnabled) { self.monitor(enabled: enabled) }
    }
  }

  private func monitor(enabled: Bool) {
    healthTask?.cancel()
    healthTask = nil
    Task { await refreshNow() }
    guard enabled, !isSandboxed else { return }
    // Permissions can return while another app is active, and taps can stop across sleep.
    healthTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        guard !Task.isCancelled, Defaults[.textExpansionEnabled] else { return }
        await self?.refreshNow()
      }
    }
  }

  func refresh() {
    Task { await refreshNow() }
  }

  private func refreshNow() async {
    refreshSequence &+= 1
    let request = refreshSequence
    let wasListening = isListening
    let enabled = Defaults[.textExpansionEnabled]
    let trusted = AXIsProcessTrusted()
    let application = NSWorkspace.shared.frontmostApplication
    let identifier = application?.bundleIdentifier ?? ""
    let isKeyboardLayout = Self.currentInputSourceIsKeyboardLayout()
    var policy = ExpansionTapPolicy(
      enabled: enabled && !isSandboxed && trusted,
      snippets: SnippetLibrary.shared.definitions,
      excludedApps: Set(Defaults[.expansionExcludedApps]),
      ignoredApps: Set(Defaults[.ignoredApps]),
      ignoreAllAppsExceptListed: Defaults[.ignoreAllAppsExceptListed],
      applicationPID: application?.processIdentifier,
      applicationIdentifier: identifier.isEmpty ? nil : identifier,
      applicationIsActive: NSApp.isActive,
      keyboardLayoutIsActive: isKeyboardLayout,
      validUntil: ContinuousClock.now.advanced(by: .seconds(5))
    )
    if lastPolicy == nil || lastPolicy?.hasSameRules(as: policy) == false {
      policyGeneration &+= 1
    }
    policyGeneration = max(policyGeneration, 1)
    policy.generation = policyGeneration
    lastPolicy = policy
    await runtime.updatePolicy(policy)
    guard request == refreshSequence else { return }

    guard !isSandboxed else {
      await runtime.stopListening(expectedGeneration: policy.generation)
      guard request == refreshSequence else { return }
      isListening = false
      status = "System-wide expansion requires a build outside App Sandbox. The library and Try it here remain available."
      return
    }
    guard enabled else {
      await runtime.stopListening(expectedGeneration: policy.generation)
      guard request == refreshSequence else { return }
      isListening = false
      status = "Text expansion is off."
      return
    }
    guard trusted else {
      await runtime.stopListening(expectedGeneration: policy.generation)
      guard request == refreshSequence else { return }
      isListening = false
      status = "Allow Accessibility to replace typed shortcuts."
      return
    }
    let started = await runtime.startListening(expectedGeneration: policy.generation)
    guard request == refreshSequence else { return }
    guard started else {
      isListening = false
      status = "Keyboard monitoring could not start. Check permissions, then try again."
      return
    }
    isListening = true
    if !wasListening { status = "Ready. Shortcuts expand in supported text fields." }
  }

  private static func currentInputSourceIsKeyboardLayout() -> Bool {
    let inputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let raw = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceType) else { return true }
    let kind = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
    return kind == kTISTypeKeyboardLayout
  }

  func openPermissionSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  private func handle(_ candidate: ExpansionCandidate) async {
    guard candidate.generation == policyGeneration,
          await runtime.isCurrent(candidate),
          candidateContextIsCurrent(candidate),
          let original = FocusedText.current(), original.pid == candidate.applicationPID,
          !original.isSecure else {
      await runtime.finishCandidate(candidate, replayDelimiter: true)
      return
    }

    var verified: (FocusedText, CFRange)?
    let preparationDeadline = ContinuousClock.now.advanced(by: .milliseconds(200))
    while ContinuousClock.now < preparationDeadline {
      guard candidate.generation == policyGeneration,
            candidate.gate.phase() == .preparing,
            await runtime.isCurrent(candidate),
            let field = FocusedText.current(), field.pid == candidate.applicationPID,
            CFEqual(field.element, original.element), !field.isSecure else { break }
      if let selection = field.selection, selection.length == 0, let value = field.value,
         let range = Self.replacementRange(value: value, caret: selection.location, match: candidate.match) {
        verified = (field, range)
        break
      }
      try? await Task.sleep(for: .milliseconds(10))
    }
    guard let (field, _) = verified,
          candidate.generation == policyGeneration,
          candidateContextIsCurrent(candidate) else {
      await runtime.finishCandidate(candidate, replayDelimiter: true)
      return
    }

    let pasteboard = NSPasteboard.general
    guard let expansion = SnippetTemplate.render(candidate.match.snippet, clipboard: pasteboard.string(forType: .string) ?? "") else {
      status = SnippetTemplate.sizeError
      await runtime.finishCandidate(candidate, replayDelimiter: true)
      return
    }
    let rendered = expansion + candidate.match.suffix
    guard rendered.utf16.count <= 100_000 else {
      status = "Expansion is too large to insert."
      await runtime.finishCandidate(candidate, replayDelimiter: true)
      return
    }
    let snapshot = PasteboardSnapshot(pasteboard)
    guard snapshot.isComplete, pasteboard.changeCount == snapshot.changeCount else {
      status = "The current clipboard cannot be preserved. Shortcut left unchanged."
      await runtime.finishCandidate(candidate, replayDelimiter: true)
      return
    }

    guard candidate.generation == policyGeneration,
          candidate.gate.phase() == .preparing,
          candidateContextIsCurrent(candidate),
          let currentField = FocusedText.current(), currentField.pid == candidate.applicationPID,
          CFEqual(currentField.element, field.element), !currentField.isSecure,
          let currentSelection = currentField.selection, currentSelection.length == 0,
          let currentValue = currentField.value,
          let currentRange = Self.replacementRange(value: currentValue, caret: currentSelection.location,
                                                   match: candidate.match),
          pasteboard.changeCount == snapshot.changeCount,
          candidate.gate.beginCommit(currentGeneration: policyGeneration) else {
      await runtime.finishCandidate(candidate, replayDelimiter: true)
      return
    }
    // The gate claim and first Accessibility mutation stay in one uninterrupted main-actor turn.
    guard currentField.setSelection(currentRange) else {
      status = "This text field does not support shortcut replacement."
      await runtime.finishCommitted(candidate.token, replayDelimiter: true)
      return
    }

    let ownedCount = writeTemporary(rendered, to: pasteboard)
    postPaste()
    var inserted = false
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
    while ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
      guard ContinuousClock.now < deadline else { break }
      if currentField.contains(rendered, at: currentRange.location) { inserted = true; break }
    }
    // Never replace a clipboard item copied by the user or another application during expansion.
    if pasteboard.changeCount == ownedCount { snapshot.restore(to: pasteboard); Clipboard.shared.changeCount = pasteboard.changeCount }
    await runtime.finishCommitted(candidate.token, replayDelimiter: false)
    if inserted {
      UsageStatistics.shared.recordExpansion(expandedCharacters: expansion.count,
                                             abbreviationCharacters: candidate.match.snippet.abbreviation.count)
      showFeedback(name: candidate.match.snippet.name,
                   bounds: currentField.bounds(for: CFRange(location: currentRange.location,
                                                            length: rendered.utf16.count)))
    } else {
      status = "The target app did not confirm insertion. Check its text before continuing."
    }
  }

  private func candidateContextIsCurrent(_ candidate: ExpansionCandidate) -> Bool {
    guard Defaults[.textExpansionEnabled], !NSApp.isActive, !IsSecureEventInputEnabled(),
          Self.currentInputSourceIsKeyboardLayout(),
          let application = NSWorkspace.shared.frontmostApplication,
          application.processIdentifier == candidate.applicationPID,
          application.bundleIdentifier == candidate.applicationIdentifier,
          !Defaults[.expansionExcludedApps].contains(candidate.applicationIdentifier),
          allowsApplication(candidate.applicationIdentifier),
          SnippetLibrary.shared.definitions.contains(candidate.match.snippet) else { return false }
    return true
  }

  private func allowsApplication(_ identifier: String) -> Bool {
    let listed = Defaults[.ignoredApps].contains(identifier)
    return Defaults[.ignoreAllAppsExceptListed] ? listed : !listed
  }

  static func replacementRange(value: String, caret: Int, match: SnippetMatcher.Match) -> CFRange? {
    let string = value as NSString
    // The delimiter is held by the event tap and has not reached the editor.
    let typedText = String(match.typedText.dropLast(match.suffix.count))
    let length = typedText.utf16.count
    guard caret >= length, caret <= string.length else { return nil }
    let range = NSRange(location: caret - length, length: length)
    guard string.substring(with: range) == typedText else { return nil }
    if match.snippet.requiresWordBoundary, range.location > 0 {
      let prefix = string.substring(to: range.location)
      guard prefix.last?.isWhitespace == true else { return nil }
    }
    return CFRange(location: range.location, length: range.length)
  }

  func pasteSnippet(_ text: String, name: String) {
    guard Accessibility.allowed else {
      Task {
        await copyManualSnippet(text)
        _ = Accessibility.check()
      }
      return
    }
    guard text.utf16.count <= 100_000 else { return }
    Task { await performManualPaste(text, name: name) }
  }

  private func copyManualSnippet(_ text: String) async {
    guard text.utf16.count <= 100_000,
          let transaction = await runtime.beginManualTransaction() else { return }
    guard transaction.gate.beginCommit(currentGeneration: nil) else {
      await runtime.cancelManualTransaction(transaction)
      return
    }
    Clipboard.shared.copy(text)
    await runtime.finishManualTransaction(transaction)
  }

  private func performManualPaste(_ text: String, name: String) async {
    guard let transaction = await runtime.beginManualTransaction() else { return }
    try? await Task.sleep(for: .milliseconds(40))
    guard transaction.gate.phase() == .preparing, !NSApp.isActive, !IsSecureEventInputEnabled() else {
      await runtime.cancelManualTransaction(transaction)
      return
    }
    let field = FocusedText.current()
    let insertionLocation = field?.selection?.location
    guard transaction.gate.beginCommit(currentGeneration: nil) else {
      await runtime.cancelManualTransaction(transaction)
      return
    }
    // Commit immediately before writing the requested clipboard contents and posting Paste.
    Clipboard.shared.copy(text)
    postPaste()
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
    while ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(10))
      guard ContinuousClock.now < deadline else { break }
      if let field, let insertionLocation, field.contains(text, at: insertionLocation) { break }
    }
    let inserted = if let field, let insertionLocation { field.contains(text, at: insertionLocation) } else { false }
    await runtime.finishManualTransaction(transaction)
    if inserted, let field, let insertionLocation {
      showFeedback(name: name, bounds: field.bounds(for: CFRange(location: insertionLocation, length: text.utf16.count)))
    }
  }

  private func writeTemporary(_ text: String, to pasteboard: NSPasteboard) -> Int {
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    pasteboard.setString("", forType: .transient)
    Clipboard.shared.changeCount = pasteboard.changeCount
    return pasteboard.changeCount
  }

  private func postPaste() {
    Clipboard.shared.postPaste(eventTag: Self.eventTag)
  }

  func playExpansionSound() {
    let sound = NSSound(named: "Pop")
    sound?.volume = 0.3
    sound?.play()
  }

  func showFeedback(name: String, bounds: CGRect?) {
    if Defaults[.expansionSound] { playExpansionSound() }
    let style = Defaults[.expansionFeedback]
    guard style != "off" else { return }
    feedbackTask?.cancel()
    feedbackPanel?.orderOut(nil)
    let screen = NSScreen.forPopup ?? NSScreen.main
    guard let screen else { return }
    let frame: CGRect
    let highlight = style == "highlight" && bounds != nil
    if let bounds, highlight {
      let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
      frame = CGRect(x: bounds.minX - 3, y: top - bounds.maxY - 2,
                     width: max(bounds.width + 6, 8), height: max(bounds.height + 4, 16))
    } else {
      // Keep feedback near the menu bar when the app does not expose text geometry.
      frame = CGRect(x: screen.visibleFrame.maxX - 210, y: screen.visibleFrame.maxY - 45, width: 195, height: 32)
    }
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.ignoresMouseEvents = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    if highlight {
      let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
      view.wantsLayer = true
      view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
      view.layer?.cornerRadius = 4
      panel.contentView = view
    } else {
      let label = NSTextField(labelWithString: "Expanded · \(name)")
      label.font = .systemFont(ofSize: 12)
      label.alignment = .center
      label.lineBreakMode = .byTruncatingTail
      let view = NSVisualEffectView(frame: CGRect(origin: .zero, size: frame.size))
      view.material = .hudWindow
      view.state = .active
      view.wantsLayer = true
      view.layer?.cornerRadius = 8
      view.layer?.masksToBounds = true
      label.frame = view.bounds.insetBy(dx: 8, dy: 8)
      view.addSubview(label)
      panel.contentView = view
    }
    feedbackPanel = panel
    panel.orderFrontRegardless()
    feedbackTask = Task {
      try? await Task.sleep(for: .milliseconds(highlight ? 350 : 650))
      guard !Task.isCancelled else { return }
      if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        NSAnimationContext.runAnimationGroup({ context in
          context.duration = 0.12
          panel.animator().alphaValue = 0
        }, completionHandler: nil)
        try? await Task.sleep(for: .milliseconds(130))
      }
      panel.orderOut(nil)
    }
  }
}

struct FocusedText {
  let element: AXUIElement
  let pid: pid_t

  static func current() -> FocusedText? {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.05)
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &result) == .success,
          let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
    let element = unsafeBitCast(result, to: AXUIElement.self)
    AXUIElementSetMessagingTimeout(element, 0.05)
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return nil }
    return FocusedText(element: element, pid: pid)
  }

  private func attribute(_ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
  }

  var isSecure: Bool { (attribute(kAXSubroleAttribute) as? String) == kAXSecureTextFieldSubrole }
  var value: String? { attribute(kAXValueAttribute) as? String }
  var selection: CFRange? {
    guard let raw = attribute(kAXSelectedTextRangeAttribute), CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
    var range = CFRange()
    guard AXValueGetValue(unsafeBitCast(raw, to: AXValue.self), .cfRange, &range) else { return nil }
    return range
  }

  func setSelection(_ range: CFRange) -> Bool {
    var range = range
    guard let value = AXValueCreate(.cfRange, &range) else { return false }
    return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success
  }

  func contains(_ text: String, at location: Int) -> Bool {
    guard let value else { return false }
    let string = value as NSString
    let range = NSRange(location: location, length: text.utf16.count)
    return location >= 0 && NSMaxRange(range) <= string.length && string.substring(with: range) == text
  }

  func bounds(for range: CFRange) -> CGRect? {
    var range = range
    guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
    var result: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &result) == .success,
          let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(unsafeBitCast(result, to: AXValue.self), .cgRect, &rect), !rect.isEmpty else { return nil }
    return rect
  }
}

struct PasteboardSnapshot {
  let changeCount: Int
  let items: [[NSPasteboard.PasteboardType: Data]]
  let isComplete: Bool

  init(_ pasteboard: NSPasteboard) {
    changeCount = pasteboard.changeCount
    var complete = true
    items = (pasteboard.pasteboardItems ?? []).map { item in
      var data: [NSPasteboard.PasteboardType: Data] = [:]
      for type in item.types {
        if let value = item.data(forType: type) { data[type] = value } else { complete = false }
      }
      return data
    }
    isComplete = complete && pasteboard.changeCount == changeCount
  }

  func restore(to pasteboard: NSPasteboard) {
    let restored = items.map { values in
      let item = NSPasteboardItem()
      values.forEach { item.setData($0.value, forType: $0.key) }
      return item
    }
    pasteboard.clearContents()
    if !restored.isEmpty { pasteboard.writeObjects(restored) }
  }
}
