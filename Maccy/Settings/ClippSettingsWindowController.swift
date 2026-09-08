import AppKit
import enum Settings.Settings
import SwiftUI

@MainActor
struct ClippSettingsPane {
  let identifier: Settings.PaneIdentifier
  let title: String
  let icon: NSImage
  let controller: NSHostingController<AnyView>
  var toolbarItemIdentifier: NSToolbarItem.Identifier { identifier.toolbarItemIdentifier }

  init<Content: View>(identifier: Settings.PaneIdentifier, title: String, toolbarIcon: NSImage,
                      @ViewBuilder contentView: () -> Content) {
    self.identifier = identifier
    self.title = title
    self.icon = toolbarIcon
    controller = NSHostingController(rootView: AnyView(contentView()))
    // A scroll view's ideal size must never become the window's minimum size.
    controller.sizingOptions = []
  }
}

/// The window owns its geometry; selecting a pane only replaces its content.
@MainActor
final class ClippSettingsWindowController: NSWindowController, NSToolbarDelegate, NSWindowDelegate {
  private let panes: [ClippSettingsPane]
  private let host = NSViewController()
  private let preferences: UserDefaults
  private var selectedPane: ClippSettingsPane?
  private static let selectionKey = "settingsSelectedPane"
  private static let frameKey = "settingsWindowFrame"

  init(panes: [ClippSettingsPane], preferences: UserDefaults = .standard) {
    self.panes = panes
    self.preferences = preferences
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 592),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
    super.init(window: window)
    window.isReleasedWhenClosed = false
    host.view = NSView()
    window.contentViewController = host
    let toolbar = NSToolbar(identifier: "Clipp.Settings.Toolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconAndLabel
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    window.toolbarStyle = .preference
    window.minSize = NSSize(width: 700, height: 520)
    window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 780, height: 680)), display: false)
    window.center()
    let saved = preferences.string(forKey: Self.selectionKey)
    selectPane(self.panes.first { $0.identifier.rawValue == saved }?.identifier ?? .general)
    // Save the outer frame explicitly so toolbar sizing cannot change the restored height.
    if let savedFrame = preferences.string(forKey: Self.frameKey) {
      window.setFrame(NSRectFromString(savedFrame), display: false)
    }
    constrainToScreen()
    window.delegate = self
    NotificationCenter.default.addObserver(self, selector: #selector(constrainToScreen),
                                          name: NSApplication.didChangeScreenParametersNotification, object: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("Use init(panes:)") }

  func show(pane: Settings.PaneIdentifier? = nil) {
    if let pane { selectPane(pane) }
    NSApp.activate()
    showWindow(nil)
    // AppKit finalizes toolbar metrics when shown, so apply the cap afterward.
    constrainToScreen()
  }

  func selectPane(_ identifier: Settings.PaneIdentifier) {
    guard let pane = panes.first(where: { $0.identifier == identifier }), pane.identifier != selectedPane?.identifier else { return }
    selectedPane?.controller.view.removeFromSuperview()
    selectedPane?.controller.removeFromParent()
    host.addChild(pane.controller)
    let view = pane.controller.view
    view.translatesAutoresizingMaskIntoConstraints = false
    host.view.addSubview(view)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
      view.topAnchor.constraint(equalTo: host.view.topAnchor),
      view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
    ])
    selectedPane = pane
    window?.title = pane.title
    window?.toolbar?.selectedItemIdentifier = pane.toolbarItemIdentifier
    preferences.set(identifier.rawValue, forKey: Self.selectionKey)
  }

  @objc private func selectToolbarItem(_ sender: NSToolbarItem) {
    selectPane(Settings.PaneIdentifier(sender.itemIdentifier.rawValue))
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    panes.map(\.toolbarItemIdentifier)
  }

  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarAllowedItemIdentifiers(toolbar)
  }

  func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarAllowedItemIdentifiers(toolbar)
  }

  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
               willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    guard let pane = panes.first(where: { $0.toolbarItemIdentifier == identifier }) else { return nil }
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.label = pane.title
    item.image = pane.icon
    item.target = self
    item.action = #selector(selectToolbarItem)
    return item
  }

  func windowDidChangeScreen(_ notification: Notification) { constrainToScreen() }

  func windowDidMove(_ notification: Notification) { saveFrame() }

  func windowDidResize(_ notification: Notification) { saveFrame() }

  func windowWillClose(_ notification: Notification) { saveFrame() }

  private func saveFrame() {
    if let window { preferences.set(NSStringFromRect(window.frame), forKey: Self.frameKey) }
  }

  @objc private func constrainToScreen() {
    guard let window, let screen = window.screen ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    let minimum = NSRect(origin: .zero, size: NSSize(width: min(700, visible.width), height: min(520, visible.height)))
    window.contentMinSize = window.contentRect(forFrameRect: minimum).size
    window.contentMaxSize = window.contentRect(forFrameRect: visible).size
    window.setFrame(Self.constrainedFrame(window.frame, to: visible), display: true)
  }

  static func constrainedFrame(_ frame: NSRect, to visible: NSRect) -> NSRect {
    let width = min(max(frame.width, 700), visible.width)
    let height = min(max(frame.height, 520), visible.height)
    return NSRect(x: min(max(frame.minX, visible.minX), visible.maxX - width),
                  y: min(max(frame.minY, visible.minY), visible.maxY - height), width: width, height: height)
  }
}
