import SwiftUI

struct SnippetResultsView: View {
  @Environment(AppState.self) private var appState

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          if appState.snippetResults.isEmpty {
            VStack(spacing: 8) {
              Text("No snippets found").foregroundStyle(.secondary)
              Button("Manage snippets…") { appState.popup.close(); appState.openPreferences(pane: .snippets) }
            }.frame(maxWidth: .infinity).padding(25)
          }
          ForEach(Array(appState.snippetResults.enumerated()), id: \.element.id) { index, snippet in
            Button { appState.activateSnippet(snippet) } label: {
              HStack(spacing: 10) {
                Image(systemName: "text.badge.plus").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                  Text(snippet.name).lineLimit(1)
                  Text(snippet.abbreviation).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if index < 9 { Text("⌘\(index + 1)").foregroundStyle(.secondary) }
              }
              .padding(.horizontal, 10).padding(.vertical, 7)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(appState.selectedSnippetID == snippet.id ? Color.accentColor.opacity(0.2) : .clear)
              .clipShape(.rect(cornerRadius: Popup.cornerRadius))
            }
            .buttonStyle(.plain)
            .id(snippet.id)
            .help(SnippetTemplate.render(snippet, clipboard: "Copied text") ?? SnippetTemplate.sizeError)
          }
        }
        .background {
          GeometryReader { geo in
            Color.clear.task(id: geo.size.height) {
              appState.popup.pinnedItemsHeight = 0
              appState.popup.resize(height: geo.size.height)
            }
          }
        }
      }
      .onChange(of: appState.selectedSnippetID) { _, id in if let id { proxy.scrollTo(id) } }
    }
    .onAppear { appState.selectedSnippetID = appState.snippetResults.first?.id }
    .onChange(of: appState.history.searchQuery) { appState.selectedSnippetID = appState.snippetResults.first?.id }
  }
}
