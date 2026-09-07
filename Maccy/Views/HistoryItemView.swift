import Defaults
import SwiftUI

struct HistoryItemView: View {
  @Bindable var item: HistoryItemDecorator

  @Environment(AppState.self) private var appState

  var body: some View {
    ListItemView(
      id: item.id,
      appIcon: item.applicationImage,
      image: item.thumbnailImage,
      accessoryImage: item.thumbnailImage != nil ? nil : ColorImage.from(item.title),
      attributedTitle: item.attributedTitle,
      shortcuts: item.shortcuts,
      isSelected: item.isSelected
    ) {
      HStack(spacing: 7) {
        if item.title.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<svg") {
          Text("SVG").font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        Text(verbatim: item.title)
      }
    }
    .onAppear {
      item.ensureThumbnailImage()
    }
    .onTapGesture {
      appState.history.select(item)
    }
    .contextMenu {
      Button("Paste") { appState.popup.close(); Clipboard.shared.copy(item.item); Clipboard.shared.paste() }
      Button("Paste as plain text") { appState.popup.close(); Clipboard.shared.copy(item.item, removeFormatting: true); Clipboard.shared.paste() }
      Button("Copy") { Clipboard.shared.copy(item.item); appState.popup.close() }
      if let text = item.item.text {
        Divider()
        Button("Create snippet…") { appState.popup.close(); SnippetLibrary.shared.create(from: text) }
      }
      Divider()
      Button("Show full preview") { item.showPreview = true; item.ensurePreviewImage() }
      Button(item.isPinned ? "Unpin" : "Pin") { appState.history.togglePin(item) }
    }
    .popover(isPresented: $item.showPreview, arrowEdge: .trailing) {
      PreviewItemView(item: item)
        .onAppear {
          item.ensurePreviewImage()
        }
    }
  }
}
