import Defaults
import SwiftUI

struct HeaderView: View {
  @FocusState.Binding var searchFocused: Bool
  @Binding var searchQuery: String

  @Environment(AppState.self) private var appState
  @Environment(\.scenePhase) private var scenePhase

  @Default(.showTitle) private var showTitle

  var body: some View {
    HStack {
      if showTitle {
        Text("Clipp")
          .foregroundStyle(.secondary)
      }

      Menu {
        Button("Clipboard history") { appState.showingSnippets = false; appState.popup.needsResize = true }
        Button("Snippets") { appState.showingSnippets = true; appState.popup.needsResize = true }
        Divider()
        Button(Defaults[.ignoreEvents] ? "Resume clipboard history" : "Pause clipboard history") { Defaults[.ignoreEvents].toggle() }
        Button(Defaults[.ignoreOnlyNextEvent] ? "Cancel skip next copy" : "Skip next copy") { Defaults[.ignoreOnlyNextEvent].toggle() }
        Divider()
        Button("Manage snippets…") { appState.popup.close(); appState.openPreferences(pane: .snippets) }
        Button(Defaults[.textExpansionEnabled] ? "Pause text expansion" : "Enable text expansion") {
          Defaults[.textExpansionEnabled].toggle()
        }
        .disabled(TextExpansionService.shared.isSandboxed)
      } label: {
        Text(appState.showingSnippets ? "Snippets" : "History")
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
      .help(appState.showingSnippets ? "Showing snippets" : "Showing clipboard history")

      SearchFieldView(placeholder: "search_placeholder", query: $searchQuery)
        .focused($searchFocused)
        .frame(maxWidth: .infinity)
        .opacity(appState.searchVisible ? 1 : 0)
        .accessibilityHidden(!appState.searchVisible)
        .onChange(of: scenePhase) {
          if scenePhase == .background && !searchQuery.isEmpty {
            searchQuery = ""
          }
        }
        // Only reliable way to disable the cursor. allowsHitTesting() does not work
        .offset(y: appState.searchVisible ? 0 : -Popup.itemHeight)
    }
    .frame(height: Popup.itemHeight + 3)
    .padding(.horizontal, 10)
    // 2px is needed to prevent items from showing behind top pinned items during scrolling
    // https://github.com/p0deje/Maccy/issues/832
    .padding(.bottom, appState.searchVisible ? 5 : 2)
    .background {
      GeometryReader { geo in
        Color.clear
          .task(id: geo.size.height) {
            appState.popup.headerHeight = geo.size.height
          }
      }
    }
  }
}
