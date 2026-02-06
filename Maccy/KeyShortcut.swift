import AppKit.NSEvent
import Defaults
import Sauce

struct KeyShortcut: Identifiable {
  static func create(character: String) -> [KeyShortcut] {
    let key = Key(character: character, virtualKeyCode: nil)
    return [
      KeyShortcut(key: key, modifierFlags: []),  // Bare number for instant paste
      KeyShortcut(key: key, modifierFlags: [.command]),  // Cmd+number as alternate
      KeyShortcut(key: key, modifierFlags: [.option]),
      KeyShortcut(key: key, modifierFlags: [Defaults[.pasteByDefault] ? .command : .option, .shift])
    ]
  }

  let id = UUID()

  var key: Key?
  var modifierFlags: NSEvent.ModifierFlags = []

  var description: String {
    guard let key, let character = Sauce.shared.currentASCIICapableCharacter(
      for: Int(Sauce.shared.keyCode(for: key)),
      cocoaModifiers: []
    ) else {
      return ""
    }

    // For bare keys (no modifiers), just show the character
    if modifierFlags.isEmpty {
      return character.capitalized
    }

    return "\(modifierFlags.description)\(character.capitalized)"
  }

  func isVisible(_ all: [KeyShortcut], _ pressedModifierFlags: NSEvent.ModifierFlags) -> Bool {
    // If only one shortcut exists, always show it
    if all.count == 1 {
      return true
    }

    // For history items with multiple shortcuts, always show the primary one (bare number/first)
    // This matches standard macOS behavior where shortcuts are static, not dynamic
    return self.id == all.first?.id
  }
}
