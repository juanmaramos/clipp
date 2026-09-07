import SwiftUI
import Defaults

// Embedded in History settings so capture and privacy choices stay together.
struct AdvancedSettingsPane: View {
  @Default(.ignoreOnlyNextEvent) private var skipNext

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Defaults.Toggle(key: .ignoreEvents) { Text("Pause clipboard history") }
      Toggle("Skip the next copy", isOn: $skipNext)
      Text("Pausing stops new items from being saved. Existing history stays available.")
        .font(.caption).foregroundStyle(.secondary)
      Divider()
      Defaults.Toggle(key: .clearOnQuit) { Text("Clear unpinned history on quit") }
      Defaults.Toggle(key: .clearSystemClipboard) { Text("Also clear the system clipboard when clearing history") }
    }
  }
}
