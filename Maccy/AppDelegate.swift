import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  var panel: FloatingPanel<ContentView>!

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.behavior = .removalAllowed
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.image = Defaults[.menuIcon].image
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    return statusItem
  }()

  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") || CommandLine.arguments.contains("development-preview") {
      SPUUpdater(hostBundle: Bundle.main,
                 applicationBundle: Bundle.main,
                 userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
                 delegate: nil)
      .automaticallyChecksForUpdates = false
    }
    #endif

    if !CommandLine.arguments.contains("enable-testing") {
      while true {
        do { try AppDataLocations.importPreferences(); break }
        catch {
          let alert = NSAlert()
          alert.messageText = "Clipp couldn’t read its previous settings"
          alert.informativeText = "Your saved settings have been kept. Allow access if macOS asks, then retry.\n\n\(error.localizedDescription)"
          alert.addButton(withTitle: "Retry"); alert.addButton(withTitle: "Quit")
          if alert.runModal() != .alertFirstButtonReturn { exit(EXIT_FAILURE) }
        }
      }
    }
    PreferencesMigration.apply(to: .standard, domainName: Bundle.main.bundleIdentifier ?? "futurialabs.clipp")

    // Bridge FloatingPanel via AppDelegate.
    AppState.shared.appDelegate = self

    Clipboard.shared.onNewCopy { History.shared.add($0) }
    if !CommandLine.arguments.contains("enable-testing") { Clipboard.shared.start() }

    Task {
      for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
        Clipboard.shared.restart()
      }
    }

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, Defaults[.showInStatusBar] != newValue {
        Defaults[.showInStatusBar] = newValue
      }
    }

    Task {
      for await value in Defaults.updates(.showInStatusBar) {
        statusItem.isVisible = value
      }
    }

    Task {
      for await value in Defaults.updates(.menuIcon, initial: false) {
        statusItem.button?.image = value.image
      }
    }

    synchronizeMenuIconText()
    Task {
      for await value in Defaults.updates(.showRecentCopyInMenuBar) {
        if value {
          statusItem.button?.title = AppState.shared.menuIconText
        } else {
          statusItem.button?.title = ""
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.ignoreEvents) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }

    Task {
      for await _ in Defaults.updates(.enabledPasteboardTypes) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    disableUnusedGlobalHotkeys()

    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      ContentView()
    }
    if !CommandLine.arguments.contains("enable-testing") { TextExpansionService.shared.start() }
    #if DEBUG
    if CommandLine.arguments.contains("show-snippets") { AppState.shared.openPreferences(pane: .snippets) }
    #endif
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  @objc
  private func performStatusItemClick() {
    if let event = NSApp.currentEvent {
      let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

      if modifierFlags.contains(.option) {
        if modifierFlags.contains(.shift) {
          Defaults[.ignoreOnlyNextEvent].toggle()
        } else {
          Defaults[.ignoreEvents].toggle()
        }

        return
      }
    }

    panel.toggle(height: AppState.shared.popup.height, at: .statusItem)
  }

  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: {
      DispatchQueue.main.async {
        if Defaults[.showRecentCopyInMenuBar] {
          self.statusItem.button?.title = AppState.shared.menuIconText
        }
        self.synchronizeMenuIconText()
      }
    }
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin]
    KeyboardShortcuts.disable(names)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
}

// Read the persistent domain so registered factory defaults are never mistaken for user choices.
enum PreferencesMigration {
  static func apply(to defaults: UserDefaults, domainName: String) {
    let saved = defaults.persistentDomain(forName: domainName) ?? [:]
    var migrations = saved["migrations"] as? [String: Bool] ?? [:]
    guard migrations["2026-09-07-preserve-preferences"] != true else { return }
    let existingInstallation = !migrations.isEmpty || saved["KeyboardShortcuts_popup"] != nil
    if existingInstallation {
      let previousDefaults: [String: Any] = [
        "pasteByDefault": false, "removeFormattingByDefault": false,
        "showApplicationIcons": false, "showSpecialSymbols": true, "previewDelay": 1500
      ]
      for (key, value) in previousDefaults where saved[key] == nil { defaults.set(value, forKey: key) }
    }
    for (oldKey, newKey) in [("hideFooter", "showFooter"), ("hideSearch", "showSearch"), ("hideTitle", "showTitle")] {
      if let oldValue = saved[oldKey] as? Bool, saved[newKey] == nil { defaults.set(!oldValue, forKey: newKey) }
      defaults.removeObject(forKey: oldKey)
    }
    if let highlight = saved["highlightMatch"] as? String, ["italic", "underline"].contains(highlight) {
      defaults.set("color", forKey: "highlightMatch")
    }
    migrations["2024-07-01-version-2"] = true
    migrations["2026-03-09-clipp-defaults"] = true
    migrations["2026-03-09-highlight-match-options"] = true
    migrations["2026-09-07-preserve-preferences"] = true
    defaults.set(migrations, forKey: "migrations")
  }
}
