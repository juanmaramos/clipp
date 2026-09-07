// swiftlint:disable file_length
import AppKit.NSRunningApplication
import Defaults
import Foundation
import Logging
import Observation
import Sauce
import Settings
import SwiftData

@Observable
class History { // swiftlint:disable:this type_body_length
  static let shared = History()
  let logger = Logger(label: "org.p0deje.Maccy")

  var items: [HistoryItemDecorator] = []
  var selectedItem: HistoryItemDecorator? {
    willSet {
      selectedItem?.isSelected = false
      newValue?.isSelected = true
    }
  }

  var pinnedItems: [HistoryItemDecorator] { items.filter(\.isPinned) }
  var unpinnedItems: [HistoryItemDecorator] { items.filter(\.isUnpinned) }

  var searchQuery: String = "" {
    didSet {
      throttler.throttle { [self] in
        MainActor.assumeIsolated { applySearch() }
      }
    }
  }

  @ObservationIgnored private var appliedSearchQuery = ""

  @MainActor
  func flushPendingSearch() {
    guard appliedSearchQuery != searchQuery else { return }
    throttler.cancel()
    applySearch()
  }

  @MainActor
  private func applySearch() {
    updateItems(search.search(string: searchQuery, within: all))
    appliedSearchQuery = searchQuery
    if searchQuery.isEmpty { AppState.shared.selection = unpinnedItems.first?.id }
    else {
      AppState.shared.selection = nil
      AppState.shared.highlightFirst()
    }
    AppState.shared.popup.needsResize = true
  }

  var pressedShortcutItem: HistoryItemDecorator? {
    guard let event = NSApp.currentEvent else {
      return nil
    }

    return shortcutItem(for: event)
  }

  func shortcutItem(for event: NSEvent) -> HistoryItemDecorator? {
    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function])

    guard HistoryItemAction(modifierFlags) != .unknown else {
      return nil
    }

    let key = Sauce.shared.key(for: Int(event.keyCode))
    return items.first { $0.isVisible && $0.shortcuts.contains(where: { $0.key == key && $0.modifierFlags == modifierFlags }) }
  }

  private let search = Search()
  private let sorter = Sorter()
  private let throttler = Throttler(minimumDelay: 0.2)

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]

  // The distinction between `all` and `items` is the following:
  // - `all` stores all history items, even the ones that are currently hidden by a search
  // - `items` stores only visible history items, updated during a search
  @ObservationIgnored
  var all: [HistoryItemDecorator] = []

  init() {
    Task {
      for await _ in Defaults.updates(.pasteByDefault, initial: false) {
        updateShortcuts()
      }
    }

    Task {
      for await _ in Defaults.updates(.sortBy, initial: false) {
        do { try await load() } catch { await reportLoadError(error) }
      }
    }

    Task {
      for await _ in Defaults.updates(.pinTo, initial: false) {
        do { try await load() } catch { await reportLoadError(error) }
      }
    }

    Task {
      for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
        for item in items {
          await updateTitle(item: item, title: item.item.generateTitle())
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.imageMaxHeight, initial: false) {
        for item in items {
          await item.cleanupImages()
        }
      }
    }
  }

  @MainActor
  func load() async throws {
    let descriptor = FetchDescriptor<HistoryItem>()
    let results = try Storage.shared.context.fetch(descriptor)
    all = sorter.sort(results).map { HistoryItemDecorator($0) }
    items = all

    limitHistorySize(to: Defaults[.size])

    updateShortcuts()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  private func reportLoadError(_ error: Error) {
    Storage.shared.errorMessage = "Could not load history: \(error.localizedDescription)"
  }

  @MainActor
  private func limitHistorySize(to maxSize: Int) {
    let unpinned = all.filter(\.isUnpinned)
    if unpinned.count >= maxSize {
      unpinned[maxSize...].forEach(delete)
    }
  }

  @MainActor
  func insertIntoStorage(_ item: HistoryItem) throws {
    logger.info("Inserting history item \(item.id)")
    Storage.shared.context.insert(item)
    Storage.shared.context.processPendingChanges()
    try Storage.shared.context.save()
  }

  @discardableResult
  @MainActor
  func add(_ item: HistoryItem) -> HistoryItemDecorator {
    if #available(macOS 15.0, *) {
      Storage.shared.context.insert(item)
    } else {
      // On macOS 14 the history item needs to be inserted into storage directly after creating it.
      // It was already inserted after creation in Clipboard.swift
    }

    var removedItemIndex: Int?
    if let existingHistoryItem = findSimilarItem(item) {
      if isModified(item) == nil {
        item.contents = existingHistoryItem.contents
      }
      item.firstCopiedAt = existingHistoryItem.firstCopiedAt
      item.numberOfCopies += existingHistoryItem.numberOfCopies
      item.pin = existingHistoryItem.pin
      if isModified(item) == nil || existingHistoryItem.title != existingHistoryItem.generateTitle() {
        item.title = existingHistoryItem.title
      }
      item.application = existingHistoryItem.application
      logger.info("Removing duplicate history item \(existingHistoryItem.id)")
      Storage.shared.context.delete(existingHistoryItem)
      removedItemIndex = all.firstIndex(where: { $0.item == existingHistoryItem })
    }
    guard Storage.shared.commit({}) else { return HistoryItemDecorator(item) }
    if let removedItemIndex { all.remove(at: removedItemIndex) }
    else { Task { Notifier.notify(body: item.title, sound: .write) } }

    // Remove exceeding items. Do this after the item is added to avoid removing something
    // if a duplicate was found as then the size already stayed the same.
    limitHistorySize(to: Defaults[.size] - 1)

    sessionLog[Clipboard.shared.changeCount] = item

    let itemDecorator = HistoryItemDecorator(item, shortcuts: item.pin.map { KeyShortcut.create(character: $0) } ?? [])
    if item.pin != nil, let removedItemIndex {
      all.insert(itemDecorator, at: min(removedItemIndex, all.count))
    } else {
      let sortedItems = sorter.sort(all.map(\.item) + [item])
      if let index = sortedItems.firstIndex(of: item) { all.insert(itemDecorator, at: index) }
    }
    items = all
    updateUnpinnedShortcuts()
    AppState.shared.popup.needsResize = true

    return itemDecorator
  }

  @MainActor
  func clear() { clearHistory(includingPins: false) }

  @MainActor
  func clearAll() { clearHistory(includingPins: true) }

  @MainActor
  private func clearHistory(includingPins: Bool) {
    let removed = all.filter { includingPins || $0.isUnpinned }
    guard Storage.shared.commit({
      let stored = try Storage.shared.context.fetch(FetchDescriptor<HistoryItem>())
      for item in stored where includingPins || item.pin == nil { Storage.shared.context.delete(item) }
    }) else { return }
    for item in removed { cleanup(item) }
    let ids = Set(removed.map(\.id))
    all.removeAll { ids.contains($0.id) }
    items = all
    if includingPins { sessionLog.removeAll() }
    else { sessionLog.removeValues { $0.pin == nil } }
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    AppState.shared.popup.needsResize = true
  }

  @MainActor
  func delete(_ item: HistoryItemDecorator?) {
    guard let item else { return }
    guard Storage.shared.commit({ Storage.shared.context.delete(item.item) }) else { return }
    cleanup(item)
    all.removeAll { $0 == item }
    items.removeAll { $0 == item }
    sessionLog.removeValues { $0 == item.item }
    updateUnpinnedShortcuts()
    AppState.shared.popup.needsResize = true
  }

  @MainActor
  private func cleanup(_ item: HistoryItemDecorator) {
    item.cleanupImages()
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?, modifiers: NSEvent.ModifierFlags? = nil) {
    guard let item else {
      return
    }

    let modifierFlags = (modifiers ?? NSApp.currentEvent?.modifierFlags)?
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function]) ?? []
    let isReuse = !Clipboard.shared.contains(item.item)

    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      if Defaults[.pasteByDefault] {
        Clipboard.shared.paste()
      }
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .paste:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
        Clipboard.shared.paste()
      case .pasteWithoutFormatting:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    if isReuse { UsageStatistics.shared.recordClipboardReuse() }
    Task {
      searchQuery = ""
    }
  }

  @MainActor
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    item.togglePin()

    let sortedItems = sorter.sort(all.map(\.item))
    if let currentIndex = all.firstIndex(of: item),
       let newIndex = sortedItems.firstIndex(of: item.item) {
      all.remove(at: currentIndex)
      all.insert(item, at: newIndex)
    }

    items = all

    searchQuery = ""
    updateUnpinnedShortcuts()
    if item.isUnpinned {
      AppState.shared.scrollTarget = item.id
    }
  }

  @MainActor
  private func findSimilarItem(_ item: HistoryItem) -> HistoryItem? {
    let descriptor = FetchDescriptor<HistoryItem>()
    if let all = try? Storage.shared.context.fetch(descriptor) {
      let duplicates = all.filter({ $0 == item || $0.supersedes(item) })
      if duplicates.count > 1 {
        return duplicates.first(where: { $0 != item })
      } else {
        return isModified(item)
      }
    }

    return item
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func updateItems(_ newItems: [Search.SearchResult]) {
    items = newItems.map { result in
      let item = result.object
      item.highlight(searchQuery, result.ranges)

      return item
    }

    updateUnpinnedShortcuts()
  }

  private func updateShortcuts() {
    for item in pinnedItems {
      if let pin = item.item.pin {
        item.shortcuts = KeyShortcut.create(character: pin)
      }
    }

    updateUnpinnedShortcuts()
  }

  @MainActor
  private func updateTitle(item: HistoryItemDecorator, title: String) {
    item.title = title
    item.item.title = title
  }

  private func updateUnpinnedShortcuts() {
    let visibleUnpinnedItems = unpinnedItems.filter(\.isVisible)
    for item in visibleUnpinnedItems {
      item.shortcuts = []
    }

    var index = 1
    for item in visibleUnpinnedItems.prefix(9) {
      item.shortcuts = KeyShortcut.create(character: String(index))
      index += 1
    }
  }
}
