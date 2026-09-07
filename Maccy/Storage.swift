import AppKit
import Observation
import SwiftData

@MainActor
@Observable
class Storage {
  static let shared = Storage()

  let container: ModelContainer
  var context: ModelContext { container.mainContext }
  var errorMessage: String?

  init(configuration: ModelConfiguration? = nil) {
    var config = configuration
    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif
    // Never replace an unreadable database with an empty one.
    while true {
      do {
        let resolved = try config ?? ModelConfiguration(url: AppDataLocations.databaseURL())
        container = try ModelContainer(for: HistoryItem.self, Snippet.self, configurations: resolved)
        return
      } catch {
        let alert = NSAlert()
        alert.messageText = "Clipp couldn’t open its saved data"
        alert.informativeText = "Your existing database has been kept. Check available disk space and file access, then retry.\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Quit")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() != .alertFirstButtonReturn { exit(EXIT_FAILURE) }
      }
    }
  }

  // Commit before updating visible history, and roll back failed changes together.
  @discardableResult
  func commit(_ changes: () throws -> Void, save: (() throws -> Void)? = nil) -> Bool {
    do {
      try changes()
      if let save { try save() } else { try context.save() }
      return true
    } catch {
      context.rollback()
      errorMessage = "The change could not be saved. Your previous data has been kept.\n\n\(error.localizedDescription)"
      return false
    }
  }
}

// Upgrades keep the existing store (including WAL and external blobs) in place.
// New installations use Application Support, with a distinct development directory.
enum AppDataLocations {
  static func databaseURL(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                          identifier: String = Bundle.main.bundleIdentifier ?? "futurialabs.clipp") throws -> URL {
    let legacy = home.appending(path: "Library/Containers/\(identifier)/Data/Library/Application Support/Maccy/Storage.sqlite")
    do {
      _ = try FileManager.default.attributesOfItem(atPath: legacy.path)
      return legacy
    } catch let error as NSError {
      guard error.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) else { throw error }
    }
    let directory = home.appending(path: "Library/Application Support/\(identifier.hasSuffix(".dev") ? "Clipp Dev" : "Clipp")")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "Storage.sqlite")
  }

  static func importPreferences(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                defaults: UserDefaults = .standard,
                                identifier: String = Bundle.main.bundleIdentifier ?? "futurialabs.clipp") throws {
    let current = defaults.persistentDomain(forName: identifier) ?? [:]
    guard current["clippContainerPreferencesImported"] as? Bool != true else { return }
    let legacy = home.appending(path: "Library/Containers/\(identifier)/Data/Library/Preferences/\(identifier).plist")
    var merged = current
    do {
      let data = try Data(contentsOf: legacy)
      guard let saved = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        throw CocoaError(.propertyListReadCorrupt)
      }
      merged = saved.merging(current) { _, currentValue in currentValue }
    } catch let error as NSError {
      guard error.domain == NSCocoaErrorDomain && [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) else { throw error }
    }
    merged["clippContainerPreferencesImported"] = true
    defaults.setPersistentDomain(merged, forName: identifier)
  }
}
