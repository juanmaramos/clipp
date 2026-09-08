import AppKit
import enum Settings.Settings
import SwiftUI
import XCTest
@testable import Clipp

@MainActor
final class SettingsWindowTests: XCTestCase {
  private var domain: String!
  private var preferences: UserDefaults!

  override func setUpWithError() throws {
    domain = "ClippSettingsTests.\(UUID().uuidString)"
    preferences = UserDefaults(suiteName: domain)!
  }

  override func tearDownWithError() throws {
    preferences.removePersistentDomain(forName: domain)
  }

  private func controller() -> ClippSettingsWindowController {
    ClippSettingsWindowController(panes: [
      ClippSettingsPane(identifier: .general, title: "General", toolbarIcon: NSImage()) {
        Text("A short setting").frame(maxWidth: .infinity, maxHeight: .infinity)
      },
      ClippSettingsPane(identifier: .snippets, title: "Snippets", toolbarIcon: NSImage()) {
        ScrollView { Text(String(repeating: "A long translated description with multiple lines. ", count: 100)) }
      }
    ], preferences: preferences)
  }

  func testSwitchingBetweenDifferentContentsKeepsUserFrameAndSingleVisiblePane() throws {
    let controller = controller()
    let window = try XCTUnwrap(controller.window)
    defer { controller.close() }
    XCTAssertTrue(window.styleMask.contains(.resizable))
    window.setFrame(NSRect(x: window.frame.minX, y: window.frame.minY, width: 820, height: 600), display: false)
    let resized = window.frame
    for identifier in [Settings.PaneIdentifier.snippets, .general, .snippets] {
      controller.selectPane(identifier)
      window.contentView?.layoutSubtreeIfNeeded()
      XCTAssertEqual(window.frame, resized)
      XCTAssertEqual(window.contentViewController?.children.count, 1)
      XCTAssertEqual(window.toolbar?.selectedItemIdentifier?.rawValue, identifier.rawValue)
    }
  }

  func testReopeningRestoresCategoryAndUserSize() throws {
    let first = controller()
    let window = try XCTUnwrap(first.window)
    window.setFrame(NSRect(origin: window.frame.origin, size: NSSize(width: 760, height: 560)), display: false)
    first.selectPane(.snippets)
    first.close()
    let reopened = controller()
    defer { reopened.close() }
    XCTAssertEqual(reopened.window?.frame.size, window.frame.size)
    XCTAssertEqual(reopened.window?.title, "Snippets")
  }

  func testRealPanesKeepWindowHeightAfterTheyAreDisplayed() throws {
    let panes: [ClippSettingsPane] = [
      ClippSettingsPane(identifier: .general, title: "General", toolbarIcon: NSImage()) { GeneralSettingsPane() },
      ClippSettingsPane(identifier: .appearance, title: "Appearance", toolbarIcon: NSImage()) { AppearanceSettingsPane() },
      ClippSettingsPane(identifier: .pins, title: "Pins", toolbarIcon: NSImage()) {
        PinsSettingsPane().environment(AppState.shared).modelContainer(Storage.shared.container)
      },
      ClippSettingsPane(identifier: .snippets, title: "Snippets", toolbarIcon: NSImage()) { SnippetsSettingsPane() },
      ClippSettingsPane(identifier: .storage, title: "History", toolbarIcon: NSImage()) { StorageSettingsPane() },
      ClippSettingsPane(identifier: .statistics, title: "Time saved", toolbarIcon: NSImage()) { StatisticsSettingsPane() }
    ]
    let controller = ClippSettingsWindowController(panes: panes, preferences: preferences)
    let window = try XCTUnwrap(controller.window)
    defer { controller.close() }
    window.orderFront(nil)
    for size in [NSSize(width: 780, height: 680), NSSize(width: 700, height: 520)] {
      window.setFrame(NSRect(origin: window.frame.origin, size: size), display: true)
      for pane in panes {
        controller.selectPane(pane.identifier)
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(window.frame.size, size, pane.title)
      }
    }
  }

  func testWindowFromDisconnectedDisplayFitsCurrentVisibleArea() {
    let visible = NSRect(x: 0, y: 80, width: 1280, height: 720)
    let offscreen = NSRect(x: 2100, y: -500, width: 1500, height: 1100)
    let restored = ClippSettingsWindowController.constrainedFrame(offscreen, to: visible)
    XCTAssertTrue(visible.contains(restored))
    XCTAssertEqual(restored.size, visible.size)
  }

  func testClampingPreservesValidUserFrameOnAnotherDisplay() {
    let visible = NSRect(x: -1440, y: -100, width: 1440, height: 900)
    let userFrame = NSRect(x: -1200, y: 0, width: 900, height: 650)
    XCTAssertEqual(ClippSettingsWindowController.constrainedFrame(userFrame, to: visible), userFrame)
  }

  func testSmallDisplayCapsThePreferredMinimumFrame() {
    let visible = NSRect(x: 0, y: 0, width: 640, height: 480)
    let restored = ClippSettingsWindowController.constrainedFrame(.zero, to: visible)
    XCTAssertTrue(visible.contains(restored))
    XCTAssertEqual(restored.size, visible.size)
  }
}
