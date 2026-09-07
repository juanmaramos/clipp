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

  func testMatcherRequiresBoundaryAndDoesNotRecurse() {
    var matcher = SnippetMatcher()
    XCTAssertNil(matcher.append("word;em", snippets: [email]))
    XCTAssertNotNil(matcher.append(" ;em", snippets: [email]))
    XCTAssertEqual(matcher.buffer, "")
    XCTAssertNil(matcher.append("person@example.com", snippets: [email]))
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
