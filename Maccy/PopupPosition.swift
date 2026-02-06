import AppKit.NSEvent
import Defaults
import Foundation

enum PopupPosition: String, CaseIterable, Identifiable, CustomStringConvertible, Defaults.Serializable {
  case cursor
  case statusItem
  case window
  case center
  case lastPosition

  var id: Self { self }

  var description: String {
    switch self {
    case .cursor:
      return NSLocalizedString("PopupAtCursor", tableName: "AppearanceSettings", comment: "")
    case .statusItem:
      return NSLocalizedString("PopupAtMenuBarIcon", tableName: "AppearanceSettings", comment: "")
    case .window:
      return NSLocalizedString("PopupAtWindowCenter", tableName: "AppearanceSettings", comment: "")
    case .center:
      return NSLocalizedString("PopupAtScreenCenter", tableName: "AppearanceSettings", comment: "")
    case .lastPosition:
      return NSLocalizedString("PopupAtLastPosition", tableName: "AppearanceSettings", comment: "")
    }
  }

  // swiftlint:disable:next cyclomatic_complexity
  func origin(size: NSSize, statusBarButton: NSStatusBarButton?) -> NSPoint {
    var point: NSPoint

    switch self {
    case .center:
      if let frame = NSScreen.forPopup?.visibleFrame {
        return NSRect.centered(ofSize: size, in: frame).origin
      }
      point = NSEvent.mouseLocation
    case .window:
      if let frame = NSWorkspace.shared.frontmostApplication?.windowFrame {
        return NSRect.centered(ofSize: size, in: frame).origin
      }
      point = NSEvent.mouseLocation
    case .statusItem:
      if let statusBarButton, let screen = NSScreen.main {
        let rectInWindow = statusBarButton.convert(statusBarButton.bounds, to: nil)
        if let screenRect = statusBarButton.window?.convertToScreen(rectInWindow) {
          point = NSPoint(x: screenRect.minX, y: screenRect.minY - size.height)
          return constrainToScreen(point: point, size: size, screen: screen)
        }
      }
      point = NSEvent.mouseLocation
    case .lastPosition:
      if let frame = NSScreen.forPopup?.visibleFrame {
        let relativePos = Defaults[.windowPosition]
        let anchorX = frame.minX + frame.width * relativePos.x
        let anchorY = frame.minY + frame.height * relativePos.y
        // Anchor is top middle of frame
        point = NSPoint(x: anchorX - size.width / 2, y: anchorY - size.height)
        return constrainToScreen(point: point, size: size, screen: NSScreen.forPopup)
      }
      point = NSEvent.mouseLocation
    default:
      point = NSEvent.mouseLocation
    }

    point.y -= size.height
    if let screen = NSScreen.forPopup {
      return constrainToScreen(point: point, size: size, screen: screen)
    }
    return point
  }

  private func constrainToScreen(point: NSPoint, size: NSSize, screen: NSScreen?) -> NSPoint {
    guard let screen = screen else { return point }

    var constrainedPoint = point
    let frame = screen.visibleFrame

    // Keep within horizontal bounds
    if constrainedPoint.x < frame.minX {
      constrainedPoint.x = frame.minX
    } else if (constrainedPoint.x + size.width) > frame.maxX {
      constrainedPoint.x = frame.maxX - size.width
    }

    // Keep within vertical bounds
    if constrainedPoint.y < frame.minY {
      constrainedPoint.y = frame.minY
    } else if (constrainedPoint.y + size.height) > frame.maxY {
      constrainedPoint.y = frame.maxY - size.height
    }

    return constrainedPoint
  }
}
