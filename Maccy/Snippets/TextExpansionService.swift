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

  @ObservationIgnored private var tap: CFMachPort?
  @ObservationIgnored private var source: CFRunLoopSource?
  @ObservationIgnored private var settingsTask: Task<Void, Never>?
  @ObservationIgnored private var transactionTask: Task<Void, Never>?
  @ObservationIgnored private var matcher = SnippetMatcher()
  @ObservationIgnored private var lastElement: AXUIElement?
  @ObservationIgnored private var lastInputAt = Date.distantPast
  @ObservationIgnored private var queuedEvents: [CGEvent] = []
  @ObservationIgnored private var isReplacing = false
  @ObservationIgnored private var feedbackPanel: NSPanel?
  @ObservationIgnored private var feedbackTask: Task<Void, Never>?
  private static let eventTag: Int64 = 0x434C495050

  func start() {
    guard settingsTask == nil else { return }
    settingsTask = Task {
      for await _ in Defaults.updates(.textExpansionEnabled) { refresh() }
    }
  }

  func refresh() {
    guard !isSandboxed else {
      stopListening()
      status = "System-wide expansion requires a build outside App Sandbox. The library and Try it here remain available."
      return
    }
    guard Defaults[.textExpansionEnabled] else { stopListening(); status = "Text expansion is off."; return }
    guard AXIsProcessTrusted() else { stopListening(); status = "Allow Accessibility to replace typed shortcuts."; return }
    guard CGPreflightListenEventAccess() else { stopListening(); status = "Allow Input Monitoring to detect typed shortcuts."; return }
    guard tap == nil else { status = "Ready. Shortcuts expand in supported text fields."; return }
    let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
                               .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
    let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    let callback: CGEventTapCallBack = { _, type, event, context in
      guard let context else { return Unmanaged.passUnretained(event) }
      return MainActor.assumeIsolated {
        Unmanaged<TextExpansionService>.fromOpaque(context).takeUnretainedValue().handle(type, event)
      }
    }
    guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
      status = "Keyboard monitoring could not start. Check permissions, then try again."
      return
    }
    tap = created
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: created, enable: true)
    isListening = true
    status = "Ready. Shortcuts expand in supported text fields."
  }

  func openPermissionSettings(accessibility: Bool) {
    let pane = accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
      NSWorkspace.shared.open(url)
    }
  }

  private func stopListening() {
    // A transaction owns the clipboard until it finishes; it must be allowed to clean up.
    matcher.reset()
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    if let tap { CFMachPortInvalidate(tap) }
    tap = nil
    source = nil
    isListening = false
    flushEvents()
  }

  private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    let unchanged = Unmanaged.passUnretained(event)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      matcher.reset()
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return unchanged
    }
    if event.getIntegerValueField(.eventSourceUserData) == Self.eventTag { return unchanged }
    if isReplacing {
      if let copy = event.copy() { queuedEvents.append(copy) }
      return nil
    }
    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown || type == .scrollWheel {
      matcher.reset()
      lastElement = nil
      return unchanged
    }
    guard type == .keyDown else { return unchanged }
    guard !IsSecureEventInputEnabled(), !NSApp.isActive,
          let app = NSWorkspace.shared.frontmostApplication,
          !Defaults[.expansionExcludedApps].contains(app.bundleIdentifier ?? ""),
          allowsApplication(app.bundleIdentifier ?? ""),
          let field = FocusedText.current(), !field.isSecure else {
      matcher.reset(); lastElement = nil; return unchanged
    }
    if lastElement == nil || !CFEqual(lastElement, field.element) || Date.now.timeIntervalSince(lastInputAt) > 10 {
      matcher.reset()
    }
    lastElement = field.element
    lastInputAt = .now
    let flags = event.flags.intersection([.maskCommand, .maskControl, .maskAlternate])
    guard flags.isEmpty else { matcher.reset(); return unchanged }
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    if code == 51 { matcher.backspace(); return unchanged }
    if [36, 48, 53, 76, 117, 123, 124, 125, 126].contains(code) { matcher.reset(); return unchanged }
    // Input methods own composition; do not reinterpret their intermediate keystrokes.
    let inputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    if let raw = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceType) {
      let kind = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
      if kind != kTISTypeKeyboardLayout { matcher.reset(); return unchanged }
    }
    var characters = [UniChar](repeating: 0, count: 32)
    var length = 0
    event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
    guard length > 0, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
      matcher.reset(); return unchanged
    }
    let text = String(utf16CodeUnits: characters, count: length)
    guard let match = matcher.append(text, snippets: SnippetLibrary.shared.definitions) else { return unchanged }
    // Keep Space away from the target's autocorrection until the abbreviation is replaced.
    let delimiterEvent = match.snippet.waitsForSpace ? event.copy() : nil
    if match.snippet.waitsForSpace {
      guard delimiterEvent != nil else { return unchanged }
    }
    isReplacing = true
    transactionTask = Task {
      var attempted = false
      // Wait for the target to commit the final character; never select an unverified range.
      for _ in 0..<20 {
        try? await Task.sleep(for: .milliseconds(10))
        guard let current = FocusedText.current(), CFEqual(current.element, field.element) else { break }
        if let selection = current.selection, let value = current.value, selection.length == 0,
           Self.replacementRange(value: value, caret: selection.location, match: match) != nil {
          attempted = await replace(match, in: current)
          break
        }
      }
      if !attempted, let delimiterEvent {
        delimiterEvent.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
        delimiterEvent.post(tap: .cgSessionEventTap)
      }
      isReplacing = false
      flushEvents()
    }
    return delimiterEvent == nil ? unchanged : nil
  }

  private func allowsApplication(_ identifier: String) -> Bool {
    let listed = Defaults[.ignoredApps].contains(identifier)
    return Defaults[.ignoreAllAppsExceptListed] ? listed : !listed
  }

  private func replace(_ match: SnippetMatcher.Match, in original: FocusedText) async -> Bool {
    guard Defaults[.textExpansionEnabled], !IsSecureEventInputEnabled(),
          let field = FocusedText.current(), CFEqual(field.element, original.element),
          let selection = field.selection, selection.length == 0,
          let value = field.value,
          let range = Self.replacementRange(value: value, caret: selection.location, match: match) else { return false }
    let pasteboard = NSPasteboard.general
    guard let expansion = SnippetTemplate.render(match.snippet, clipboard: pasteboard.string(forType: .string) ?? "") else {
      status = SnippetTemplate.sizeError; return false
    }
    let rendered = expansion + match.suffix
    guard rendered.utf16.count <= 100_000 else { status = "Expansion is too large to insert."; return false }
    let snapshot = PasteboardSnapshot(pasteboard)
    guard snapshot.isComplete, pasteboard.changeCount == snapshot.changeCount else {
      status = "The current clipboard cannot be preserved. Shortcut left unchanged."
      return false
    }
    guard field.setSelection(range) else { status = "This text field does not support shortcut replacement."; return false }
    let ownedCount = writeTemporary(rendered, to: pasteboard)
    postPaste()
    var inserted = false
    for _ in 0..<50 {
      try? await Task.sleep(for: .milliseconds(10))
      if field.contains(rendered, at: range.location) { inserted = true; break }
    }
    // Never replace a clipboard item copied by the user or another application during expansion.
    if pasteboard.changeCount == ownedCount { snapshot.restore(to: pasteboard); Clipboard.shared.changeCount = pasteboard.changeCount }
    if inserted {
      UsageStatistics.shared.recordExpansion(expandedCharacters: expansion.count, abbreviationCharacters: match.snippet.abbreviation.count)
      showFeedback(name: match.snippet.name, bounds: field.bounds(for: CFRange(location: range.location, length: rendered.utf16.count)))
    } else {
      status = "The target app did not confirm insertion. Check its text before continuing."
    }
    // Once paste has been posted, never replay a delimiter that might arrive after it.
    return true
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
      Clipboard.shared.copy(text)
      _ = Accessibility.check()
      return
    }
    guard !isReplacing, text.utf16.count <= 100_000 else { return }
    isReplacing = true
    transactionTask = Task {
      defer { isReplacing = false; flushEvents() }
      try? await Task.sleep(for: .milliseconds(40))
      guard !NSApp.isActive, !IsSecureEventInputEnabled() else { return }
      let field = FocusedText.current()
      let insertionLocation = field?.selection?.location
      Clipboard.shared.copy(text)
      postPaste()
      for _ in 0..<50 {
        try? await Task.sleep(for: .milliseconds(10))
        if let field, let insertionLocation, field.contains(text, at: insertionLocation) { break }
      }
      if let field, let insertionLocation, field.contains(text, at: insertionLocation) {
        showFeedback(name: name, bounds: field.bounds(for: CFRange(location: insertionLocation, length: text.utf16.count)))
      }
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

  private func flushEvents() {
    let events = queuedEvents
    queuedEvents.removeAll()
    events.forEach { event in
      event.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
      event.post(tap: .cgSessionEventTap)
    }
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

  static func current() -> FocusedText? {
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, 0.05)
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &result) == .success,
          let result, CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
    let element = unsafeBitCast(result, to: AXUIElement.self)
    AXUIElementSetMessagingTimeout(element, 0.05)
    return FocusedText(element: element)
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
