import AppKit
import Defaults
import SwiftData
import XCTest
@testable import Clipp

@MainActor
final class SnippetTests: XCTestCase {
  private var email: SnippetDefinition {
    .init(name: "Email", abbreviation: ";em", content: "person@example.com", isEnabled: true)
  }

  private func listenerPort() throws -> CFMachPort {
    var context = CFMachPortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
    return try XCTUnwrap(CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, &context, nil))
  }

  func testHealthyListenerIsNotInterruptedByHealthCheck() throws {
    let tap = try listenerPort()
    defer { CFMachPortInvalidate(tap) }
    XCTAssertTrue(TextExpansionService.resumeTap(tap, isEnabled: { _ in true }, enable: { _ in
      XCTFail("A healthy listener must not be restarted")
    }))
  }

  func testDisabledListenerResumesAndVerifiesItsState() throws {
    let tap = try listenerPort()
    defer { CFMachPortInvalidate(tap) }
    var enabled = false
    var attempts = 0
    XCTAssertTrue(TextExpansionService.resumeTap(tap, isEnabled: { _ in enabled }, enable: { _ in
      attempts += 1
      enabled = true
    }))
    XCTAssertEqual(attempts, 1)
    XCTAssertTrue(enabled)
  }

  func testListenerThatCannotResumeIsNotReportedHealthy() throws {
    let tap = try listenerPort()
    defer { CFMachPortInvalidate(tap) }
    var attempts = 0
    XCTAssertFalse(TextExpansionService.resumeTap(tap, isEnabled: { _ in false }, enable: { _ in
      attempts += 1
    }))
    XCTAssertEqual(attempts, 1)
  }

  func testInvalidListenerRequiresRecreation() throws {
    let tap = try listenerPort()
    CFMachPortInvalidate(tap)
    XCTAssertFalse(TextExpansionService.resumeTap(tap, isEnabled: { _ in
      XCTFail("An invalid port must not be queried as an event tap")
      return true
    }, enable: { _ in XCTFail("An invalid port cannot be resumed") }))
  }

  func testListenerInvalidatedDuringResumeIsNotReportedHealthy() throws {
    let tap = try listenerPort()
    XCTAssertFalse(TextExpansionService.resumeTap(tap, isEnabled: { _ in false }, enable: {
      CFMachPortInvalidate($0)
    }))
  }

  func testMatcherRequiresBoundaryAndDoesNotRecurse() {
    var matcher = SnippetMatcher()
    XCTAssertNil(matcher.append("word;em", snippets: [email]))
    XCTAssertNotNil(matcher.append(" ;em", snippets: [email]))
    XCTAssertEqual(matcher.buffer, "")
    XCTAssertNil(matcher.append("person@example.com", snippets: [email]))
  }

  private func keyboardEvent(_ code: CGKeyCode, down: Bool, repeating: Bool = false) throws -> CGEvent {
    let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down))
    event.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
    event.flags = []
    return event
  }

  func testShortcutModifiersIncludeCommandControlAndOptionOnly() throws {
    let event = try keyboardEvent(48, down: true)
    let unmodifiedFlags: [CGEventFlags] = [.maskShift, .maskAlphaShift, []]
    for flags in unmodifiedFlags {
      event.flags = flags
      XCTAssertFalse(ExpansionEventBuffer.hasShortcutModifier(event))
    }
    let shortcutFlags: [CGEventFlags] = [
      .maskCommand, .maskControl, .maskAlternate,
      .maskCommand.union(.maskShift), .maskControl.union(.maskAlternate),
    ]
    for flags in shortcutFlags {
      event.flags = flags
      XCTAssertTrue(ExpansionEventBuffer.hasShortcutModifier(event))
    }
  }

  func testIdleShortcutIsForwardedAndLeavesTheBufferEmpty() throws {
    let service = TextExpansionService()
    let event = try keyboardEvent(48, down: true)
    event.flags = .maskCommand

    let forwarded = service.handle(.keyDown, event)?.takeUnretainedValue()

    XCTAssertTrue(forwarded === event)
    var queuedEvents = service.queuedEvents
    XCTAssertTrue(queuedEvents.drain().isEmpty)
  }

  func testModifierReleaseStaysQueuedAfterShortcutDuringReplacement() throws {
    let shortcuts: [(flags: CGEventFlags, modifierCode: CGKeyCode)] = [
      (.maskCommand, 55), (.maskControl, 59), (.maskAlternate, 58),
    ]
    for (flags, modifierCode) in shortcuts {
      let service = TextExpansionService()
      service.isReplacing = true

      let tabDown = try keyboardEvent(48, down: true)
      tabDown.flags = flags
      XCTAssertNil(service.handle(.keyDown, tabDown))

      let modifierUp = try keyboardEvent(modifierCode, down: false)
      modifierUp.type = .flagsChanged
      modifierUp.flags = []
      XCTAssertNil(service.handle(.flagsChanged, modifierUp))

      let tabUp = try keyboardEvent(48, down: false)
      tabUp.flags = []
      XCTAssertNil(service.handle(.keyUp, tabUp))
      var queuedEvents = service.queuedEvents
      let events = queuedEvents.drain()
      XCTAssertEqual(events.map(\.type), [.keyDown, .flagsChanged, .keyUp])
      XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [48, Int64(modifierCode), 48])
    }
  }

  func testModifiedRepeatOfQueuedKeyStaysWithItsPair() throws {
    let service = TextExpansionService()
    service.isReplacing = true

    XCTAssertNil(service.handle(.keyDown, try keyboardEvent(7, down: true)))
    let repeated = try keyboardEvent(7, down: true, repeating: true)
    repeated.flags = .maskCommand
    XCTAssertNil(service.handle(.keyDown, repeated))
    let released = try keyboardEvent(7, down: false)
    released.flags = .maskCommand
    XCTAssertNil(service.handle(.keyUp, released))

    var queuedEvents = service.queuedEvents
    let events = queuedEvents.drain()
    XCTAssertEqual(events.map(\.type), [.keyDown, .keyDown, .keyUp])
    XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [7, 7, 7])
  }

  func testModifierChangesPassUntilAShortcutIsQueued() throws {
    var buffer = ExpansionEventBuffer()
    let modifierDown = try keyboardEvent(55, down: false)
    modifierDown.type = .flagsChanged
    modifierDown.flags = .maskCommand
    XCTAssertFalse(buffer.append(modifierDown))

    let tabDown = try keyboardEvent(48, down: true)
    tabDown.flags = .maskCommand
    XCTAssertTrue(buffer.append(tabDown))
    let commandUp = try keyboardEvent(55, down: false)
    commandUp.type = .flagsChanged
    commandUp.flags = []
    XCTAssertTrue(buffer.append(commandUp))

    XCTAssertEqual(buffer.drain().map(\.type), [.keyDown, .flagsChanged])
    XCTAssertFalse(buffer.append(commandUp))
  }

  func testTaggedShortcutPassesDuringReplacement() throws {
    let service = TextExpansionService()
    service.isReplacing = true
    let event = try keyboardEvent(9, down: true)
    event.flags = .maskCommand
    event.setIntegerValueField(.eventSourceUserData, value: TextExpansionService.eventTag)

    XCTAssertTrue(service.handle(.keyDown, event)?.takeUnretainedValue() === event)
    var queuedEvents = service.queuedEvents
    XCTAssertTrue(queuedEvents.drain().isEmpty)
  }

  func testExpansionDoesNotHoldReleasesOfAlreadyDeliveredTriggerKeys() throws {
    var buffer = ExpansionEventBuffer()
    // e and m were pressed before the replacement began; their releases must reach the app now.
    XCTAssertFalse(buffer.append(try keyboardEvent(14, down: false)))
    XCTAssertFalse(buffer.append(try keyboardEvent(46, down: false)))
    XCTAssertTrue(buffer.drain().isEmpty)
  }

  func testTypingAheadKeepsNewKeyPairsInOrderWithoutHoldingTriggerRelease() throws {
    var buffer = ExpansionEventBuffer()
    XCTAssertTrue(buffer.append(try keyboardEvent(7, down: true)))
    XCTAssertFalse(buffer.append(try keyboardEvent(46, down: false)))
    XCTAssertTrue(buffer.append(try keyboardEvent(7, down: false)))
    let events = buffer.drain()
    XCTAssertEqual(events.map(\.type), [.keyDown, .keyUp])
    XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [7, 7])
  }

  func testExpansionDoesNotHoldModifierReleaseOrRepeatOfDeliveredKey() throws {
    var buffer = ExpansionEventBuffer()
    let shiftUp = try keyboardEvent(56, down: false)
    shiftUp.type = .flagsChanged
    XCTAssertFalse(buffer.append(shiftUp))
    XCTAssertFalse(buffer.append(try keyboardEvent(14, down: true, repeating: true)))
    XCTAssertFalse(buffer.append(try keyboardEvent(14, down: false)))
    XCTAssertTrue(buffer.drain().isEmpty)
  }

  func testQueuedRepeatStaysWithItsKeyDownAndKeyUp() throws {
    var buffer = ExpansionEventBuffer()
    XCTAssertTrue(buffer.append(try keyboardEvent(7, down: true)))
    XCTAssertTrue(buffer.append(try keyboardEvent(7, down: true, repeating: true)))
    XCTAssertTrue(buffer.append(try keyboardEvent(7, down: false)))
    XCTAssertEqual(buffer.drain().map(\.type), [.keyDown, .keyDown, .keyUp])
  }

  func testDrainingBeforePhysicalReleaseDoesNotSwallowTheLaterKeyUp() throws {
    var buffer = ExpansionEventBuffer()
    XCTAssertTrue(buffer.append(try keyboardEvent(7, down: true)))
    XCTAssertEqual(buffer.drain().count, 1)
    XCTAssertFalse(buffer.append(try keyboardEvent(7, down: false)))
    XCTAssertTrue(buffer.drain().isEmpty)
  }

  func testHeldSpaceReleaseWaitsForDelimiterReplay() throws {
    var buffer = ExpansionEventBuffer()
    buffer.holdKeyDown(49)
    XCTAssertTrue(buffer.append(try keyboardEvent(49, down: false)))
    XCTAssertTrue(buffer.append(try keyboardEvent(7, down: true)))
    XCTAssertTrue(buffer.append(try keyboardEvent(7, down: false)))
    // On failure, the caller replays Space down before draining; its release must precede typing ahead.
    let events = buffer.drain()
    XCTAssertEqual(events.map(\.type), [.keyUp, .keyDown, .keyUp])
    XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [49, 7, 7])
  }

  func testPasteDoesNotSuppressPhysicalTypingOrKeyReleases() throws {
    let source = try XCTUnwrap(Clipboard.pasteEventSource())
    XCTAssertEqual(source.localEventsSuppressionInterval, 0)
    XCTAssertTrue(source.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateSuppressionInterval)
      .contains(.permitLocalKeyboardEvents))
  }

  func testSpaceModePreservesDelimiterAndAllowsBackspace() {
    var matcher = SnippetMatcher()
    var snippet = email
    snippet.abbreviation = "ddate"; snippet.waitsForSpace = true
    XCTAssertNil(matcher.append("ddatx", snippets: [snippet]))
    matcher.backspace()
    XCTAssertNil(matcher.append("e", snippets: [snippet]))
    let match = matcher.append(" ", snippets: [snippet])
    XCTAssertEqual(match?.typedText, "ddate ")
    XCTAssertEqual(match?.suffix, " ")
  }

  func testResetCaseAndDisabledSnippets() {
    var matcher = SnippetMatcher()
    XCTAssertNil(matcher.append(";EM", snippets: [email]))
    matcher.reset()
    var insensitive = email; insensitive.caseSensitive = false
    XCTAssertNotNil(matcher.append(";EM", snippets: [insensitive]))
    insensitive.isEnabled = false
    XCTAssertNil(matcher.append(";em", snippets: [insensitive]))
    matcher.reset()
    XCTAssertNil(matcher.append(";e", snippets: [email]))
    matcher.reset()
    XCTAssertNil(matcher.append("m", snippets: [email]))
  }

  func testConflictingPrefixesAndDuplicateValidation() {
    var longer = email; longer.id = UUID(); longer.abbreviation = ";email"
    XCTAssertNotNil(longer.validationError(among: [email]))
    var shorter = email; shorter.waitsForSpace = true
    XCTAssertNil(longer.validationError(among: [shorter]))
    longer.abbreviation = ";EM"; longer.caseSensitive = false
    XCTAssertNotNil(longer.validationError(among: [email]))
    longer.dayOffset = Int.min
    XCTAssertNotNil(longer.validationError(among: []))
  }

  func testDateTimeLocaleTimezoneAndRelativeDayAcrossDST() throws {
    let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-28T12:35:42Z"))
    var snippet = email
    snippet.content = "{{date}} / {{time}} / {{datetime}}"
    snippet.timeZoneIdentifier = "Europe/Madrid"
    snippet.localeIdentifier = "en_GB"
    snippet.dayOffset = 1
    XCTAssertEqual(SnippetTemplate.render(snippet, now: now), "2026-03-29 / 13:35 / 2026-03-29 13:35")
    snippet.timeZoneIdentifier = "UTC"; snippet.dayOffset = 0
    snippet.dateFormat = "d MMMM yyyy"; snippet.timeFormat = "h:mm:ss a"
    XCTAssertEqual(SnippetTemplate.render(snippet, now: now), "28 March 2026 / 12:35:42 pm / 28 March 2026 12:35:42 pm")
  }

  func testClipboardIsLiteralAndUnknownTokenIsRejected() {
    var snippet = email; snippet.content = "{{clipboard}} — {{clipboard}}"
    XCTAssertEqual(SnippetTemplate.render(snippet, clipboard: "{{date}} 🐈"), "{{date}} 🐈 — {{date}} 🐈")
    snippet.content = "{{execute}}"
    XCTAssertNotNil(snippet.validationError(among: []))
  }

  func testReplacementVerifiesExactTextAtCaretWithUTF16() throws {
    var matcher = SnippetMatcher()
    let match = try XCTUnwrap(matcher.append(";em", snippets: [email]))
    let text = "🐈 ;em tail"
    let caret = ("🐈 ;em" as NSString).length
    let range = TextExpansionService.replacementRange(value: text, caret: caret, match: match)
    XCTAssertEqual(range?.location, 3)
    XCTAssertEqual(range?.length, 3)
    XCTAssertNil(TextExpansionService.replacementRange(value: "changed", caret: 7, match: match))
    XCTAssertNil(TextExpansionService.replacementRange(value: "word;em", caret: 7, match: match))
    XCTAssertNil(TextExpansionService.replacementRange(value: ";em", caret: 99, match: match))
  }

  func testSpaceTriggerVerifiesAbbreviationBeforeDelimiterReachesEditor() throws {
    var matcher = SnippetMatcher()
    let snippet = SnippetDefinition(name: "Date", abbreviation: "ddate", content: "{{date}}", isEnabled: true, waitsForSpace: true)
    let match = try XCTUnwrap(matcher.append("ddate ", snippets: [snippet]))
    let range = TextExpansionService.replacementRange(value: "ddate", caret: 5, match: match)
    XCTAssertEqual(range?.length, 5)
    XCTAssertEqual(match.suffix, " ")
    XCTAssertNil(TextExpansionService.replacementRange(value: "Date", caret: 4, match: match))
  }

  func testClipboardExpansionStopsBeforeCreatingOversizedText() {
    var snippet = email
    snippet.content = "{{clipboard}}{{clipboard}}"
    XCTAssertNil(SnippetTemplate.render(snippet, clipboard: String(repeating: "x", count: 60_000)))
    XCTAssertEqual(SnippetTemplate.render(snippet, clipboard: "text"), "texttext")
  }

  func testImportExportPersistenceAndConflictIsAtomic() throws {
    let container = try ModelContainer(for: Snippet.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let library = SnippetLibrary(context: container.mainContext)
    XCTAssertTrue(library.save(email))
    let data = try library.exportData()
    let target = try ModelContainer(for: Snippet.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let imported = SnippetLibrary(context: target.mainContext)
    try imported.importData(data)
    XCTAssertEqual(imported.snippets.count, 1)
    XCTAssertEqual(imported.snippets.first?.content, email.content)
    XCTAssertFalse(try XCTUnwrap(imported.snippets.first).isEnabled)
    XCTAssertThrowsError(try imported.importData(data))
    XCTAssertEqual(imported.snippets.count, 1)
  }

  func testAddingSnippetSchemaKeepsExistingHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let config = ModelConfiguration(url: directory.appendingPathComponent("migration.sqlite"))
    try autoreleasepool {
      let old = try ModelContainer(for: HistoryItem.self, configurations: config)
      let item = HistoryItem(contents: [HistoryItemContent(type: "public.utf8-plain-text", value: Data("Keep me".utf8))])
      item.title = "Keep me"
      old.mainContext.insert(item)
      try old.mainContext.save()
    }
    let upgraded = try ModelContainer(for: HistoryItem.self, Snippet.self, configurations: config)
    XCTAssertEqual(try upgraded.mainContext.fetch(FetchDescriptor<HistoryItem>()).first?.title, "Keep me")
    upgraded.mainContext.insert(Snippet(email))
    try upgraded.mainContext.save()
    XCTAssertEqual(try upgraded.mainContext.fetchCount(FetchDescriptor<Snippet>()), 1)
  }

  func testPasteboardSnapshotPreservesEveryItemAndType() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let rtf = try XCTUnwrap(NSAttributedString(string: "plain").rtf(from: NSRange(location: 0, length: 5), documentAttributes: [:]))
    let first = NSPasteboardItem(); first.setString("plain", forType: .string); first.setData(rtf, forType: .rtf)
    let second = NSPasteboardItem(); second.setString("<b>second item</b>", forType: .html)
    pasteboard.writeObjects([first, second])
    let snapshot = PasteboardSnapshot(pasteboard)
    XCTAssertTrue(snapshot.isComplete, "Types: \(pasteboard.pasteboardItems?.map { $0.types.map { $0.rawValue } } ?? []), counts: \(snapshot.changeCount)/\(pasteboard.changeCount)")
    pasteboard.clearContents(); pasteboard.setString("temporary", forType: .string)
    snapshot.restore(to: pasteboard)
    XCTAssertEqual(pasteboard.pasteboardItems?.count, 2)
    XCTAssertEqual(pasteboard.pasteboardItems?.first?.data(forType: .rtf), rtf)
    XCTAssertEqual(pasteboard.pasteboardItems?.last?.string(forType: .html), "<b>second item</b>")
  }

  func testPasteboardSnapshotPreservesAccessibleFileURL() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("example".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.writeObjects([file as NSURL])
    let snapshot = PasteboardSnapshot(pasteboard)
    XCTAssertTrue(snapshot.isComplete)
    pasteboard.clearContents()
    snapshot.restore(to: pasteboard)
    XCTAssertEqual(pasteboard.string(forType: .fileURL), file.absoluteString)
  }

  func testSearchExcerptKeepsLateMatchVisible() throws {
    let title = String(repeating: "prefix ", count: 100) + "needle trailing context"
    let item = HistoryItem(contents: [])
    item.title = title
    let decorated = HistoryItemDecorator(item)
    decorated.highlight("needle", [try XCTUnwrap(title.range(of: "needle"))])
    let excerpt = try XCTUnwrap(decorated.attributedTitle)
    XCTAssertTrue(String(excerpt.characters).contains("needle"))
    XCTAssertTrue(String(excerpt.characters).hasPrefix("…"))
    XCTAssertLessThan(excerpt.characters.count, 170)
  }

  func testNumberShortcutsRequireModifierAndOnlyMatchVisibleRows() throws {
    let history = History()
    let item = HistoryItemDecorator(HistoryItem(contents: []), shortcuts: KeyShortcut.create(character: "2"))
    history.items = [item]
    let bare = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: 0, context: nil, characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19))
    let command = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
      windowNumber: 0, context: nil, characters: "2", charactersIgnoringModifiers: "2", isARepeat: false, keyCode: 19))
    XCTAssertNil(history.shortcutItem(for: bare))
    XCTAssertEqual(history.shortcutItem(for: command)?.id, item.id)
    XCTAssertEqual(item.shortcuts.first?.description, "⌘2")
    item.isVisible = false
    XCTAssertNil(history.shortcutItem(for: command))
  }
}
