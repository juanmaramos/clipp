import AppKit
import Defaults
import SwiftData
import XCTest
@testable import Clipp

@MainActor
final class QualityTests: XCTestCase {
  private var temporaryHome: URL!
  private var domain: String!
  private var preferences: UserDefaults!

  override func setUpWithError() throws {
    domain = "ClippQualityTests.\(UUID().uuidString)"
    preferences = UserDefaults(suiteName: domain)!
    temporaryHome = FileManager.default.temporaryDirectory.appending(path: domain)
    try FileManager.default.createDirectory(at: temporaryHome, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    preferences.removePersistentDomain(forName: domain)
    try FileManager.default.removeItem(at: temporaryHome)
  }

  func testMigrationPreservesChoicesAndOtherMarkers() {
    preferences.setPersistentDomain([
      "migrations": ["clipp_v1.0_defaults": true, "other-migration": true],
      "pasteByDefault": false, "showSearch": false, "hideSearch": false,
      "SUEnableAutomaticChecks": false, "popupPosition": "statusItem", "previewDelay": 2300
    ], forName: domain)
    PreferencesMigration.apply(to: preferences, domainName: domain)
    PreferencesMigration.apply(to: preferences, domainName: domain)
    XCTAssertFalse(preferences.bool(forKey: "pasteByDefault"))
    XCTAssertFalse(preferences.bool(forKey: "showSearch"))
    XCTAssertFalse(preferences.bool(forKey: "SUEnableAutomaticChecks"))
    XCTAssertEqual(preferences.string(forKey: "popupPosition"), "statusItem")
    XCTAssertEqual(preferences.integer(forKey: "previewDelay"), 2300)
    XCTAssertTrue((preferences.dictionary(forKey: "migrations")?["other-migration"] as? Bool) == true)
    XCTAssertNil(preferences.object(forKey: "hideSearch"))
  }

  func testMigrationRetainsOldEffectiveDefaults() {
    preferences.register(defaults: ["pasteByDefault": true, "showSpecialSymbols": false])
    preferences.set(["2024-07-01-version-2": true], forKey: "migrations")
    PreferencesMigration.apply(to: preferences, domainName: domain)
    XCTAssertFalse(preferences.bool(forKey: "pasteByDefault"))
    XCTAssertTrue(preferences.bool(forKey: "showSpecialSymbols"))
    XCTAssertEqual(preferences.integer(forKey: "previewDelay"), 1500)
  }

  func testFreshInstallUsesNewDefaultsAndMigratesLegacyHideKeysOnlyWhenPresent() {
    preferences.register(defaults: ["pasteByDefault": true, "showSearch": true])
    PreferencesMigration.apply(to: preferences, domainName: domain)
    XCTAssertTrue(preferences.bool(forKey: "pasteByDefault"))
    XCTAssertNil(preferences.persistentDomain(forName: domain)?["showSearch"])
    preferences.removePersistentDomain(forName: domain)
    preferences.set(true, forKey: "hideSearch")
    PreferencesMigration.apply(to: preferences, domainName: domain)
    XCTAssertFalse(preferences.bool(forKey: "showSearch"))
  }

  func testImportPreservesCurrentChoicesAndRunsOnce() throws {
    let file = temporaryHome.appending(path: "Library/Containers/\(domain!)/Data/Library/Preferences/\(domain!).plist")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let old: [String: Any] = ["pasteByDefault": true, "SUEnableAutomaticChecks": false, "migrations": ["old": true]]
    try PropertyListSerialization.data(fromPropertyList: old, format: .xml, options: 0).write(to: file)
    preferences.set(false, forKey: "pasteByDefault")
    try AppDataLocations.importPreferences(home: temporaryHome, defaults: preferences, identifier: domain)
    XCTAssertFalse(preferences.bool(forKey: "pasteByDefault"))
    XCTAssertFalse(preferences.bool(forKey: "SUEnableAutomaticChecks"))
    XCTAssertEqual(preferences.dictionary(forKey: "migrations")?["old"] as? Bool, true)
    preferences.set(true, forKey: "SUEnableAutomaticChecks")
    try AppDataLocations.importPreferences(home: temporaryHome, defaults: preferences, identifier: domain)
    XCTAssertTrue(preferences.bool(forKey: "SUEnableAutomaticChecks"))
  }

  func testCorruptLegacyPreferencesAreNotSilentlyDiscarded() throws {
    let file = temporaryHome.appending(path: "Library/Containers/\(domain!)/Data/Library/Preferences/\(domain!).plist")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not a plist".utf8).write(to: file)
    XCTAssertThrowsError(try AppDataLocations.importPreferences(home: temporaryHome, defaults: preferences, identifier: domain))
    XCTAssertFalse(preferences.bool(forKey: "clippContainerPreferencesImported"))
    XCTAssertEqual(try Data(contentsOf: file), Data("not a plist".utf8))
  }

  func testStoreLocationPreservesLegacyDatabaseAndSeparatesDevelopment() throws {
    let old = temporaryHome.appending(path: "Library/Containers/futurialabs.clipp/Data/Library/Application Support/Maccy/Storage.sqlite")
    try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("existing database".utf8).write(to: old)
    XCTAssertEqual(try AppDataLocations.databaseURL(home: temporaryHome, identifier: "futurialabs.clipp"), old)
    let dev = try AppDataLocations.databaseURL(home: temporaryHome, identifier: "futurialabs.clipp.dev")
    XCTAssertTrue(dev.path.contains("Application Support/Clipp Dev/"))
    XCTAssertNotEqual(dev, old)
    XCTAssertEqual(try Data(contentsOf: old), Data("existing database".utf8))
  }

  func testFailedSaveRollsBackDeletion() throws {
    let storage = Storage(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
    let item = HistoryItem()
    item.title = "Must remain"
    storage.context.insert(item)
    try storage.context.save()
    let savedID = item.id
    let committed = storage.commit({ storage.context.delete(item) }, save: { throw CocoaError(.fileWriteOutOfSpace) })
    XCTAssertFalse(committed)
    XCTAssertNotNil(storage.errorMessage)
    XCTAssertEqual(try storage.context.fetch(FetchDescriptor<HistoryItem>()).map(\.id), [savedID])
  }

  func testPrivacyRulesAndSkipNextAreIndependent() {
    let savedRules = Defaults[.ignoreRegexp]
    let savedPause = Defaults[.ignoreEvents]
    let savedSkip = Defaults[.ignoreOnlyNextEvent]
    let savedTypes = Defaults[.enabledPasteboardTypes]
    let savedApps = Defaults[.ignoredApps]
    let savedInverse = Defaults[.ignoreAllAppsExceptListed]
    defer {
      Defaults[.ignoreRegexp] = savedRules; Defaults[.ignoreEvents] = savedPause
      Defaults[.ignoreOnlyNextEvent] = savedSkip; Defaults[.enabledPasteboardTypes] = savedTypes
      Defaults[.ignoredApps] = savedApps; Defaults[.ignoreAllAppsExceptListed] = savedInverse
    }
    Defaults[.ignoreRegexp] = ["[", "^secret"]
    Defaults[.ignoreEvents] = false; Defaults[.ignoreOnlyNextEvent] = false
    Defaults[.enabledPasteboardTypes] = [.string]
    Defaults[.ignoredApps] = []; Defaults[.ignoreAllAppsExceptListed] = false
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let clipboard = Clipboard(pasteboard: board)
    var captured: [String] = []
    clipboard.onNewCopy { captured.append($0.title) }
    func copy(_ value: String) {
      board.clearContents(); board.setString(value, forType: .string)
      clipboard.checkForChangesInPasteboard()
    }
    copy("secret hidden")
    XCTAssertTrue(captured.isEmpty)
    copy("visible")
    XCTAssertEqual(captured.count, 1)
    Defaults[.ignoreOnlyNextEvent] = true
    copy("skip me")
    XCTAssertFalse(Defaults[.ignoreOnlyNextEvent])
    XCTAssertEqual(captured.count, 1)
    copy("visible again")
    XCTAssertEqual(captured.count, 2)
    Defaults[.ignoreEvents] = true; Defaults[.ignoreOnlyNextEvent] = true
    copy("paused")
    XCTAssertTrue(Defaults[.ignoreEvents])
    copy("still paused")
    XCTAssertEqual(captured.count, 2)
  }

  func testPopupMonitorCanBeRemovedAndReattached() {
    let popup = Popup()
    XCTAssertTrue(popup.hasEventsMonitor)
    popup.deinitEventsMonitor()
    XCTAssertFalse(popup.hasEventsMonitor)
    popup.initEventsMonitor()
    XCTAssertTrue(popup.hasEventsMonitor)
  }
}
