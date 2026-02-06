import Sauce
import SwiftUI

struct KeyHandlingView<Content: View>: View {
  @Binding var searchQuery: String
  @FocusState.Binding var searchFocused: Bool
  @ViewBuilder let content: () -> Content

  @Environment(AppState.self) private var appState

  var body: some View {
    content()
      .onKeyPress { _ in
        // Unfortunately, key presses don't allow access to
        // key code and don't properly work with multiple inputs,
        // so pressing ⌘, on non-English layout doesn't open
        // preferences. Stick to NSEvent to fix this behavior.

        let keyChord = KeyChord(NSApp.currentEvent)

        // Handle app shortcuts FIRST, even when search is focused
        // This prevents text field from capturing Cmd+, and similar shortcuts
        switch keyChord {
        case .openPreferences, .clearHistory, .clearHistoryAll,
             .deleteCurrentItem, .pinOrUnpin, .close:
          // These shortcuts should work regardless of search focus
          break
        default:
          // For other keys, check search field state
          if searchFocused {
            // Ignore input when candidate window is open
            // https://stackoverflow.com/questions/73677444/how-to-detect-the-candidate-window-when-using-japanese-keyboard
            if let inputClient = NSApp.keyWindow?.firstResponder as? NSTextInputClient,
               inputClient.hasMarkedText() {
              return .ignored
            }
            // Let search field handle regular typing
            if keyChord == .unknown {
              return .ignored
            }
          }
        }

        switch keyChord {
        case .clearHistory:
          if let item = appState.footer.items.first(where: { $0.title == "clear" }),
             item.confirmation != nil,
             let suppressConfirmation = item.suppressConfirmation {
            if suppressConfirmation.wrappedValue {
              item.action()
            } else {
              item.showConfirmation = true
            }
            return .handled
          } else {
            return .ignored
          }
        case .clearHistoryAll:
          if let item = appState.footer.items.first(where: { $0.title == "clear_all" }),
             item.confirmation != nil,
             let suppressConfirmation = item.suppressConfirmation {
            if suppressConfirmation.wrappedValue {
              item.action()
            } else {
              item.showConfirmation = true
            }
            return .handled
          } else {
            return .ignored
          }
        case .clearSearch:
          searchQuery = ""
          return .handled
        case .deleteCurrentItem:
          if let item = appState.history.selectedItem {
            appState.highlightNext()
            appState.history.delete(item)
          }
          return .handled
        case .deleteOneCharFromSearch:
          searchFocused = true
          _ = searchQuery.popLast()
          return .handled
        case .deleteLastWordFromSearch:
          searchFocused = true
          let newQuery = searchQuery.split(separator: " ").dropLast().joined(separator: " ")
          if newQuery.isEmpty {
            searchQuery = ""
          } else {
            searchQuery = "\(newQuery) "
          }

          return .handled
        case .moveToNext:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.highlightNext()
          return .handled
        case .moveToLast:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.highlightLast()
          return .handled
        case .moveToPrevious:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.highlightPrevious()
          return .handled
        case .moveToFirst:
          guard NSApp.characterPickerWindow == nil else {
            return .ignored
          }

          appState.highlightFirst()
          return .handled
        case .openPreferences:
          appState.openPreferences()
          return .handled
        case .pinOrUnpin:
          appState.history.togglePin(appState.history.selectedItem)
          return .handled
        case .selectCurrentItem:
          appState.select()
          return .handled
        case .close:
          appState.popup.close()
          return .handled
        default:
          ()
        }

        // Handle bare number presses (1-9, 0) for instant paste (Clipy-style)
        // Only when search field is not focused
        if !searchFocused, let item = appState.history.bareNumberPressedItem {
          appState.selection = item.id
          Task {
            try? await Task.sleep(for: .milliseconds(50))
            appState.history.select(item)
          }
          return .handled
        }

        if let item = appState.history.pressedShortcutItem {
          appState.selection = item.id
          Task {
            try? await Task.sleep(for: .milliseconds(50))
            appState.history.select(item)
          }
          return .handled
        }

        // Auto-focus search when typing regular text (not shortcuts)
        if keyChord == .unknown && !searchFocused {
          searchFocused = true
          return .ignored  // Let the text field handle the character
        }

        return .ignored
      }
  }
}
