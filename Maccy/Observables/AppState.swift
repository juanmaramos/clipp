import AppKit
import Defaults
import Foundation
import Settings

@Observable
class AppState: Sendable {
  static let shared = AppState()

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var footer: Footer
  var showingSnippets = false {
    didSet {
      selection = nil
      selectedSnippetID = nil
      popup.needsResize = true
    }
  }
  var selectedSnippetID: UUID?

  @MainActor var snippetResults: [SnippetDefinition] {
    let query = history.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    return SnippetLibrary.shared.definitions.filter { snippet in
      query.isEmpty || [snippet.name, snippet.abbreviation, snippet.content].contains {
        $0.localizedStandardContains(query)
      }
    }
  }

  @MainActor
  func handleQuickSelection(_ event: NSEvent) -> Bool {
    guard !popup.isClosed() else { return false }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])
    if showingSnippets {
      guard flags == .command, let number = Int(event.charactersIgnoringModifiers ?? ""),
            (1...9).contains(number), snippetResults.indices.contains(number - 1) else { return false }
      activateSnippet(snippetResults[number - 1])
      return true
    }
    guard !flags.isEmpty else { return false }
    history.flushPendingSearch()
    guard let item = history.shortcutItem(for: event) else { return false }
    selection = item.id
    history.select(item, modifiers: flags)
    return true
  }

  @MainActor
  func activateSnippet(_ snippet: SnippetDefinition) {
    guard snippet.validationError(among: []) == nil else { return }
    guard let text = SnippetTemplate.render(snippet, clipboard: NSPasteboard.general.string(forType: .string) ?? "") else {
      SnippetLibrary.shared.message = SnippetTemplate.sizeError
      popup.close()
      openPreferences(pane: .snippets)
      return
    }
    popup.close()
    if Defaults[.pasteByDefault] {
      TextExpansionService.shared.pasteSnippet(text, name: snippet.name)
    } else {
      Clipboard.shared.copy(text)
    }
  }

  var scrollTarget: UUID?
  var selection: UUID? {
    didSet {
      selectWithoutScrolling(selection)
      scrollTarget = selection
    }
  }

  func selectWithoutScrolling(_ item: UUID?) {
    history.selectedItem = nil
    footer.selectedItem = nil

    if let item = history.items.first(where: { $0.id == item }) {
      history.selectedItem = item
    } else if let item = footer.items.first(where: { $0.id == item }) {
      footer.selectedItem = item
    }
  }

  var hoverSelectionWhileKeyboardNavigating: UUID?
  var isKeyboardNavigating: Bool = true {
    didSet {
      if let hoverSelection = hoverSelectionWhileKeyboardNavigating {
        hoverSelectionWhileKeyboardNavigating = nil
        selection = hoverSelection
      }
    }
  }

  var searchVisible: Bool {
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !history.searchQuery.isEmpty
    }
  }

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?

  init() {
    history = History.shared
    footer = Footer()
    popup = Popup()
  }

  @MainActor
  func select() {
    if showingSnippets {
      if let snippet = snippetResults.first(where: { $0.id == selectedSnippetID }) ?? snippetResults.first {
        activateSnippet(snippet)
      }
      return
    }
    history.flushPendingSearch()
    if let item = history.selectedItem, history.items.contains(item) {
      history.select(item)
    } else if let item = footer.selectedItem {
      // TODO: Use item.suppressConfirmation, but it's not updated!
      if item.confirmation != nil, Defaults[.suppressClearAlert] == false {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      Clipboard.shared.copy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  private func selectFromKeyboardNavigation(_ id: UUID?) {
    isKeyboardNavigating = true
    selection = id
  }

  @MainActor func highlightFirst() {
    if showingSnippets { selectedSnippetID = snippetResults.first?.id; return }
    if let item = history.items.first(where: \.isVisible) {
      selectFromKeyboardNavigation(item.id)
    }
  }

  @MainActor func highlightPrevious() {
    if showingSnippets { moveSnippetSelection(-1); return }
    isKeyboardNavigating = true
    if let selectedItem = history.selectedItem {
      if let nextItem = history.items.filter(\.isVisible).item(before: selectedItem) {
        selectFromKeyboardNavigation(nextItem.id)
      }
    } else if let selectedItem = footer.selectedItem {
      if let nextItem = footer.items.filter(\.isVisible).item(before: selectedItem) {
        selectFromKeyboardNavigation(nextItem.id)
      } else if selectedItem == footer.items.first(where: \.isVisible),
                let nextItem = history.items.last(where: \.isVisible) {
        selectFromKeyboardNavigation(nextItem.id)
      }
    }
  }

  @MainActor func highlightNext(allowCycle: Bool = false) {
    if showingSnippets { moveSnippetSelection(1); return }
    if let selectedItem = history.selectedItem {
      if let nextItem = history.items.filter(\.isVisible).item(after: selectedItem) {
        selectFromKeyboardNavigation(nextItem.id)
      } else if selectedItem == history.items.filter(\.isVisible).last,
                let nextItem = footer.items.first(where: \.isVisible) {
        selectFromKeyboardNavigation(nextItem.id)
      }
    } else if let selectedItem = footer.selectedItem {
      if let nextItem = footer.items.filter(\.isVisible).item(after: selectedItem) {
        selectFromKeyboardNavigation(nextItem.id)
      } else if allowCycle {
        // End of footer; cycle to the beginning
        highlightFirst()
      }
    } else {
      selectFromKeyboardNavigation(footer.items.first(where: \.isVisible)?.id)
    }
  }

  @MainActor func highlightLast() {
    if showingSnippets { selectedSnippetID = snippetResults.last?.id; return }
    if let selectedItem = history.selectedItem {
      if selectedItem == history.items.filter(\.isVisible).last,
         let nextItem = footer.items.first(where: \.isVisible) {
        selectFromKeyboardNavigation(nextItem.id)
      } else {
        selectFromKeyboardNavigation(history.items.last(where: \.isVisible)?.id)
      }
    } else if footer.selectedItem != nil {
      selectFromKeyboardNavigation(footer.items.last(where: \.isVisible)?.id)
    } else {
      selectFromKeyboardNavigation(footer.items.first(where: \.isVisible)?.id)
    }
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func openPreferences(pane: Settings.PaneIdentifier? = nil) { // swiftlint:disable:this function_body_length
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        panes: [
          Settings.Pane(
            identifier: Settings.PaneIdentifier.general,
            title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
            toolbarIcon: NSImage.gearshape!
          ) {
            GeneralSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.appearance,
            title: NSLocalizedString("Title", tableName: "AppearanceSettings", comment: ""),
            toolbarIcon: NSImage.paintpalette!
          ) {
            AppearanceSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.pins,
            title: NSLocalizedString("Title", tableName: "PinsSettings", comment: ""),
            toolbarIcon: NSImage.pincircle!
          ) {
            PinsSettingsPane()
              .environment(self)
              .modelContainer(Storage.shared.container)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.snippets,
            title: "Snippets",
            toolbarIcon: NSImage(systemSymbolName: "text.badge.plus", accessibilityDescription: "Snippets")!
          ) {
            SnippetsSettingsPane()
          },
          Settings.Pane(
            identifier: .storage,
            title: "History",
            toolbarIcon: NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "History")!
          ) { StorageSettingsPane() },
          Settings.Pane(
            identifier: .statistics,
            title: "Time saved",
            toolbarIcon: NSImage(systemSymbolName: "chart.bar", accessibilityDescription: "Time saved")!
          ) { StatisticsSettingsPane() }

        ]
      )
    }
    settingsWindowController?.show(pane: pane)
    settingsWindowController?.window?.orderFrontRegardless()
  }

  func quit() {
    NSApp.terminate(self)
  }

  @MainActor private func moveSnippetSelection(_ offset: Int) {
    let items = snippetResults
    guard !items.isEmpty else { return }
    let current = items.firstIndex { $0.id == selectedSnippetID } ?? (offset > 0 ? -1 : 1)
    selectedSnippetID = items[min(max(current + offset, 0), items.count - 1)].id
  }
}
