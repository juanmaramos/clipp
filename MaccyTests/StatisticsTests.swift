import AppKit
import XCTest
@testable import Clipp

@MainActor
final class StatisticsTests: XCTestCase {
  private var domain: String!
  private var preferences: UserDefaults!

  override func setUp() {
    domain = "ClippStatisticsTests.\(UUID().uuidString)"
    preferences = UserDefaults(suiteName: domain)!
  }

  override func tearDown() { preferences.removePersistentDomain(forName: domain) }

  func testKnownTypingFormulaAndShortExpansions() {
    let statistics = UsageStatistics(preferences: preferences)
    statistics.recordExpansion(expandedCharacters: 253, abbreviationCharacters: 3)
    statistics.recordExpansion(expandedCharacters: 2, abbreviationCharacters: 5)
    let summary = statistics.summary()
    XCTAssertEqual(summary.charactersAvoided, 250)
    XCTAssertEqual(summary.expansions, 2)
    XCTAssertEqual(summary.typingSeconds(wordsPerMinute: 50), 60)
    XCTAssertEqual(summary.typingSeconds(wordsPerMinute: 100), 30)
    XCTAssertEqual(summary.clipboardSeconds(secondsPerReuse: 5), 0)
  }

  func testReuseEstimateCanBeExcludedAndRecalculated() {
    let statistics = UsageStatistics(preferences: preferences)
    statistics.recordClipboardReuse()
    statistics.recordClipboardReuse()
    let summary = statistics.summary()
    XCTAssertEqual(summary.clipboardReuses, 2)
    XCTAssertEqual(summary.clipboardSeconds(secondsPerReuse: 5), 10)
    XCTAssertEqual(summary.clipboardSeconds(secondsPerReuse: 0), 0)
    XCTAssertEqual(summary.clipboardSeconds(secondsPerReuse: 3), 6)
    XCTAssertEqual(summary.charactersAvoided, 0)
  }

  func testDailyPeriodsIncludeTodayWithoutCountingInactiveDays() throws {
    let statistics = UsageStatistics(preferences: preferences)
    let now = Date.now
    let calendar = Calendar.current
    statistics.recordClipboardReuse(at: now)
    statistics.recordExpansion(expandedCharacters: 20, abbreviationCharacters: 3, at: now)
    statistics.recordClipboardReuse(at: try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: now)))
    statistics.recordClipboardReuse(at: try XCTUnwrap(calendar.date(byAdding: .day, value: -7, to: now)))
    XCTAssertEqual(statistics.summary(lastDays: 1, now: now).clipboardReuses, 1)
    XCTAssertEqual(statistics.summary(lastDays: 7, now: now).clipboardReuses, 2)
    XCTAssertEqual(statistics.summary(lastDays: 7, now: now).activeDays, 2)
    XCTAssertEqual(statistics.summary(now: now).activeDays, 3)
  }

  func testPausePersistsAndResetOnlyRemovesUsageData() {
    let statistics = UsageStatistics(preferences: preferences)
    preferences.set("keep", forKey: "otherSetting")
    statistics.recordClipboardReuse()
    statistics.enabled = false
    statistics.wordsPerMinute = 75
    statistics.recordClipboardReuse()
    statistics.recordExpansion(expandedCharacters: 30, abbreviationCharacters: 2)
    let reloaded = UsageStatistics(preferences: preferences)
    XCTAssertFalse(reloaded.enabled)
    XCTAssertEqual(reloaded.wordsPerMinute, 75)
    XCTAssertEqual(reloaded.summary().clipboardReuses, 1)
    XCTAssertEqual(reloaded.summary().expansions, 0)
    reloaded.reset()
    XCTAssertEqual(reloaded.summary().activeDays, 0)
    XCTAssertNil(preferences.data(forKey: UsageStatistics.storageKey))
    XCTAssertEqual(preferences.string(forKey: "otherSetting"), "keep")
  }

  func testCorruptStatisticsArePreservedUntilExplicitReset() {
    let corrupt = Data("not json".utf8)
    preferences.set(corrupt, forKey: UsageStatistics.storageKey)
    let statistics = UsageStatistics(preferences: preferences)
    XCTAssertNotNil(statistics.errorMessage)
    statistics.recordClipboardReuse()
    XCTAssertEqual(preferences.data(forKey: UsageStatistics.storageKey), corrupt)
    statistics.reset()
    statistics.recordClipboardReuse()
    XCTAssertEqual(statistics.summary().clipboardReuses, 1)
  }

  func testTestModeDoesNotRecordActivity() {
    let statistics = UsageStatistics(preferences: preferences, recordsUsage: false)
    statistics.recordClipboardReuse()
    statistics.recordExpansion(expandedCharacters: 20, abbreviationCharacters: 3)
    XCTAssertNil(preferences.data(forKey: UsageStatistics.storageKey))
  }

  func testClipboardReuseComparesPayloadWithoutSourceMetadata() {
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let clipboard = Clipboard(pasteboard: board)
    let item = HistoryItem(contents: [HistoryItemContent(type: NSPasteboard.PasteboardType.string.rawValue, value: Data("hello".utf8))])
    board.setString("hello", forType: .string)
    board.setString("different source", forType: .source)
    XCTAssertTrue(clipboard.contains(item))
    board.clearContents()
    board.setString("another item", forType: .string)
    XCTAssertFalse(clipboard.contains(item))
    XCTAssertTrue(clipboard.contains(HistoryItem(contents: [])))
  }

  func testTimeDisplayAvoidsFalsePrecision() {
    XCTAssertEqual(StatisticsSettingsPane.duration(0), "0 min")
    XCTAssertEqual(StatisticsSettingsPane.duration(1.2), "<1 min")
    XCTAssertEqual(StatisticsSettingsPane.duration(95), "≈2 min")
    XCTAssertEqual(StatisticsSettingsPane.duration(3660), "≈1 hr 1 min")
  }
}
