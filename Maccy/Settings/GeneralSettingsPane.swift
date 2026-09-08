import SwiftUI
import Defaults
import KeyboardShortcuts
import LaunchAtLogin

struct GeneralSettingsPane: View {
  private let notificationsURL = URL(
    string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(Bundle.main.bundleIdentifier ?? "")"
  )

  @Default(.searchMode) private var searchMode
  @Default(.pasteByDefault) private var pasteByDefault
  @Default(.removeFormattingByDefault) private var removeFormatting

  @State private var copyModifier = HistoryItemAction.copy.modifierFlags.description
  @State private var pasteModifier = HistoryItemAction.paste.modifierFlags.description
  @State private var pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description

  @State private var updater = SoftwareUpdater.shared

  var body: some View {
    Form {
      Section {
        LaunchAtLogin.Toggle { Text("LaunchAtLogin", tableName: "GeneralSettings") }
        Toggle(isOn: $updater.automaticallyChecksForUpdates) {
          Text("CheckForUpdates", tableName: "GeneralSettings")
        }.disabled(updater.isDevelopmentBuild)
        Button(action: { updater.checkForUpdates() }) {
          Text("CheckNow", tableName: "GeneralSettings")
        }.disabled(updater.isDevelopmentBuild)
        if updater.isDevelopmentBuild {
          Text("Development builds use separate data and do not install public updates.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      Section {
        LabeledContent {
          KeyboardShortcuts.Recorder(for: .popup, onChange: { shortcut in
            if shortcut == nil { AppState.shared.popup.deinitEventsMonitor() }
            else { AppState.shared.popup.initEventsMonitor() }
          })
        } label: {
          VStack(alignment: .leading) {
            Text("Open", tableName: "GeneralSettings")
            Text("OpenTooltip", tableName: "GeneralSettings").font(.caption).foregroundStyle(.secondary)
          }
        }
        LabeledContent {
          KeyboardShortcuts.Recorder(for: .pin)
        } label: {
          VStack(alignment: .leading) {
            Text("Pin", tableName: "GeneralSettings")
            Text("PinTooltip", tableName: "GeneralSettings").font(.caption).foregroundStyle(.secondary)
          }
        }
        LabeledContent {
          KeyboardShortcuts.Recorder(for: .delete)
        } label: {
          VStack(alignment: .leading) {
            Text("Delete", tableName: "GeneralSettings")
            Text("DeleteTooltip", tableName: "GeneralSettings").font(.caption).foregroundStyle(.secondary)
          }
        }
        Picker(selection: $searchMode) {
          ForEach(Search.Mode.allCases) { mode in Text(mode.description) }
        } label: { Text("Search", tableName: "GeneralSettings") }
      }
      Section {
        Picker("When selecting an item", selection: $pasteByDefault) {
          Text("Paste").tag(true)
          Text("Copy").tag(false)
        }.onChange(of: pasteByDefault) { refreshModifiers(pasteByDefault) }
        Picker("Text formatting", selection: $removeFormatting) {
          Text("Plain text").tag(true)
          Text("Keep formatting").tag(false)
        }.onChange(of: removeFormatting) { refreshModifiers(removeFormatting) }
        if pasteByDefault && !Accessibility.allowed {
          VStack(alignment: .leading, spacing: 8) {
            Button("Set up pasting…") { Accessibility.openSettings() }
            Text("Allow Accessibility to paste automatically. Until then, press ⌘V after selecting an item.")
              .font(.caption).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      } header: {
        Text("Behavior", tableName: "GeneralSettings")
      } footer: {
        Text(String(format: NSLocalizedString("Modifiers", tableName: "GeneralSettings", comment: ""),
                    copyModifier, pasteModifier, pasteWithoutFormatting))
          .fixedSize(horizontal: false, vertical: true)
      }
      if let notificationsURL {
        Section {
          Link(destination: notificationsURL) { Text("NotificationsAndSounds", tableName: "GeneralSettings") }
        }
      }
    }
    .formStyle(.grouped)
  }

  private func refreshModifiers(_ sender: Sendable) {
    copyModifier = HistoryItemAction.copy.modifierFlags.description
    pasteModifier = HistoryItemAction.paste.modifierFlags.description
    pasteWithoutFormatting = HistoryItemAction.pasteWithoutFormatting.modifierFlags.description
  }
}

#Preview {
  GeneralSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
