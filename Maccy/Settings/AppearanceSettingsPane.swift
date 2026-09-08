import AppKit
import SwiftUI
import Defaults

struct AppearanceSettingsPane: View {
  private static let availableHighlightMatches: [HighlightMatch] = [.color, .bold]

  @Default(.popupPosition) private var popupAt
  @Default(.popupScreen) private var popupScreen
  @Default(.pinTo) private var pinTo
  @Default(.imageMaxHeight) private var imageHeight
  @Default(.previewDelay) private var previewDelay
  @Default(.highlightMatch) private var highlightMatch
  @Default(.menuIcon) private var menuIcon
  @Default(.showInStatusBar) private var showInStatusBar
  @Default(.showSearch) private var showSearch
  @Default(.searchVisibility) private var searchVisibility
  @Default(.showFooter) private var showFooter
  @Default(.windowPosition) private var windowPosition
  @Default(.showApplicationIcons) private var showApplicationIcons

  @State private var screens = NSScreen.screens

  private let imageHeightFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 200
    return formatter
  }()

  private let previewDelayFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 200
    formatter.maximum = 3000
    return formatter
  }()

  var body: some View {
    Form {
      LabeledContent(String(localized: "PopupAt", table: "AppearanceSettings")) {
        HStack {
          Picker("", selection: $popupAt) {
            ForEach(PopupPosition.allCases) { position in
              if position == .center || position == .lastPosition, screens.count > 1 {
                screenPicker(for: position)
              } else {
                Text(position.description)
              }
            }
          }
          .labelsHidden()
          .frame(width: 141, alignment: .leading)
          .help(Text("PopupAtTooltip", tableName: "AppearanceSettings"))

          if popupAt == .lastPosition {
            Button {
              _windowPosition.reset()
            } label: {
              Image(systemName: "arrow.uturn.backward.circle.fill")
                .imageScale(.large)
            }
            .buttonStyle(.borderless)
            .help(Text("PopupAtLastLocationReset", tableName: "AppearanceSettings"))
            .disabled(windowPosition == _windowPosition.defaultValue)
          }
        }
      }

      LabeledContent(String(localized: "PinTo", table: "AppearanceSettings")) {
        Picker("", selection: $pinTo) {
          ForEach(PinsPosition.allCases) { position in
            Text(position.description)
          }
        }
        .labelsHidden()
        .frame(width: 141, alignment: .leading)
        .help(Text("PinToTooltip", tableName: "AppearanceSettings"))
      }

      LabeledContent(String(localized: "ImageHeight", table: "AppearanceSettings")) {
        HStack {
          TextField("", value: $imageHeight, formatter: imageHeightFormatter)
            .frame(width: 120)
            .help(Text("ImageHeightTooltip", tableName: "AppearanceSettings"))
          Stepper("", value: $imageHeight, in: 1...200)
            .labelsHidden()
        }
      }

      LabeledContent(String(localized: "PreviewDelay", table: "AppearanceSettings")) {
        HStack {
          TextField("", value: $previewDelay, formatter: previewDelayFormatter)
            .frame(width: 120)
            .help(Text("PreviewDelayTooltip", tableName: "AppearanceSettings"))
          Stepper("", value: $previewDelay, in: 200...3000)
            .labelsHidden()
        }
      }

      LabeledContent(String(localized: "HighlightMatches", table: "AppearanceSettings")) {
        Picker("", selection: highlightMatchBinding) {
          ForEach(Self.availableHighlightMatches) { match in
            Text(match.description)
          }
        }
        .labelsHidden()
        .frame(width: 141, alignment: .leading)
        .help(Text("HighlightMatchesTooltip", tableName: "AppearanceSettings"))
      }

      Section {
        Defaults.Toggle(key: .showSpecialSymbols) {
          Text("ShowSpecialSymbols", tableName: "AppearanceSettings")
        }
        .help(Text("ShowSpecialSymbolsTooltip", tableName: "AppearanceSettings"))

        HStack {
          Defaults.Toggle(key: .showInStatusBar) {
            Text("ShowMenuIcon", tableName: "AppearanceSettings")
          }

          Picker("", selection: $menuIcon) {
            ForEach(MenuIcon.allCases) { icon in
              Image(nsImage: icon.image)
            }
          }
          .labelsHidden()
          .scaledToFit()
          .disabled(!showInStatusBar)
          .controlSize(.small)
        }

        Defaults.Toggle(key: .notifyOnCopy) {
          Text("NotifyOnCopy", tableName: "AppearanceSettings")
        }

        HStack {
          Defaults.Toggle(key: .showSearch) {
            Text("ShowSearchField", tableName: "AppearanceSettings")
          }

          Picker("", selection: $searchVisibility) {
            ForEach(SearchVisibility.allCases) { type in
              Text(type.description)
            }
          }
          .labelsHidden()
          .scaledToFit()
          .disabled(!showSearch)
          .controlSize(.small)
        }
        Defaults.Toggle(key: .showTitle) {
          Text("ShowTitleBeforeSearchField", tableName: "AppearanceSettings")
        }
        Defaults.Toggle(key: .showApplicationIcons) {
          Text("ShowApplicationIcons", tableName: "AppearanceSettings")
        }

        Defaults.Toggle(key: .showFooter) {
          Text("ShowFooter", tableName: "AppearanceSettings")
        }
        Text("OpenPreferencesWarning", tableName: "AppearanceSettings")
          .opacity(showFooter ? 0 : 1)
          .fixedSize(horizontal: false, vertical: true)
          .controlSize(.small)
          .foregroundStyle(.gray)
      }
    }
    .formStyle(.grouped)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
      screens = NSScreen.screens
    }
  }

  @ViewBuilder
  private func screenPicker(for position: PopupPosition) -> some View {
    let screenBinding: Binding<Int> = Binding {
      return popupScreen
    } set: {
      popupScreen = $0
      popupAt = position
    }

    Picker(selection: screenBinding) {
      Text(labelForScreen(index: 0))
        .tag(0)

      ForEach(screens.indices, id: \.self) { index in
        Text(labelForScreen(index: index + 1))
          .tag(index + 1)
      }
    } label: {
      if popupAt == position {
        Text("\(position.description) (\(labelForScreen(index: popupScreen)))")
      } else {
        Text(position.description)
      }
    }
  }

  private func labelForScreen(index screenIndex: Int) -> String {
    switch screenIndex {
    case 0:
      return String(localized: "ActiveScreen", table: "AppearanceSettings")
    case _:
      return screens[screenIndex - 1].localizedName
    }
  }

  private var highlightMatchBinding: Binding<HighlightMatch> {
    Binding {
      Self.availableHighlightMatches.contains(highlightMatch) ? highlightMatch : .color
    } set: {
      highlightMatch = $0
    }
  }
}

#Preview {
  AppearanceSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
