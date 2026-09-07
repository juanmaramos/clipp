import AppKit
import Defaults

struct Accessibility {
  static var allowed: Bool { AXIsProcessTrusted() }

  @MainActor
  static func check() -> Bool {
    guard !allowed else { return true }
    let alert = NSAlert()
    alert.messageText = "Copied. Allow Clipp to paste?"
    alert.informativeText = "The item is on your clipboard. To insert it automatically, allow Clipp in System Settings → Privacy & Security → Accessibility. You can also paste it yourself with ⌘V."
    alert.addButton(withTitle: "Open Accessibility Settings")
    alert.addButton(withTitle: "Use Copy Mode")
    alert.addButton(withTitle: "Not Now")
    NSApp.activate(ignoringOtherApps: true)
    switch alert.runModal() {
    case .alertFirstButtonReturn:
      openSettings()
    case .alertSecondButtonReturn:
      Defaults[.pasteByDefault] = false
    default: break
    }
    return false
  }

  static func openSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }
}
