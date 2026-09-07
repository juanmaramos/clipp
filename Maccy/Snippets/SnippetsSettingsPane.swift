import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct SnippetsSettingsPane: View {
  @State private var library = SnippetLibrary.shared
  @State private var service = TextExpansionService.shared
  @State private var draft = SnippetDefinition()
  @State private var savedDraft = SnippetDefinition()
  @State private var query = ""
  @State private var testText = ""
  @State private var testResult = ""
  @State private var examplesShown = false
  @State private var confirmDelete = false
  @State private var customFormats = false
  @State private var excludedAppsShown = false
  @State private var exampleSelection: Set<String> = ["ddate", "ttime", ";stamp"]
  @State private var pendingSelection: UUID?
  @State private var confirmDiscard = false
  @State private var incomingContent: String?
  @State private var editorLoaded = false
  @State private var isNew = true
  @State private var replacingTest = false
  @State private var testHighlighted = false

  @Default(.textExpansionEnabled) private var enabled
  @Default(.expansionSound) private var sound
  @Default(.expansionFeedback) private var feedback

  private var hasChanges: Bool { draft != savedDraft }
  private var validation: String? { draft.validationError(among: library.definitions) }
  private var visibleSnippets: [Snippet] {
    library.snippets.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.abbreviation.localizedStandardContains(query) }
  }
  private var hasDate: Bool { draft.content.contains("{{date") || draft.content.contains("{{time}}") }

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Toggle("Expand typed shortcuts", isOn: $enabled).disabled(service.isSandboxed)
          Spacer()
          if enabled { Button("Excluded apps…") { excludedAppsShown = true } }
        }
        if enabled || service.isSandboxed {
          HStack {
            Text(service.status).font(.caption).foregroundStyle(.secondary)
            Spacer()
            if !service.isListening && !service.isSandboxed {
              Menu("Permissions") {
                Button("Open Accessibility Settings…") { service.openPermissionSettings(accessibility: true) }
                Button("Open Input Monitoring Settings…") { service.openPermissionSettings(accessibility: false) }
              }
              Button("Check again") { service.refresh() }
            }
          }
          Text("Clipp checks typed shortcuts locally. Password fields and unsupported text fields are skipped.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(16)
      Divider()
      HSplitView {
        VStack(spacing: 8) {
          TextField("Search snippets", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 8)
          List(selection: Binding<UUID?>(get: { isNew ? nil : draft.id }, set: { requestSelection($0) })) {
            ForEach(visibleSnippets) { snippet in
              HStack {
                VStack(alignment: .leading, spacing: 3) {
                  Text(snippet.name).lineLimit(1)
                  Text(snippet.abbreviation).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if !snippet.isEnabled { Image(systemName: "pause.circle").foregroundStyle(.secondary).help("Automatic expansion is disabled") }
              }
              .padding(5)
              .tag(snippet.id)
            }
          }
          .listStyle(.plain)
          HStack {
            Button("New snippet", systemImage: "plus") { requestSelection(nil) }
            if library.snippets.isEmpty { Button("Examples…") { examplesShown = true } }
            Menu {
              Button("Add examples…") { examplesShown = true }
              Button("Import snippets…") { importSnippets() }
              Button("Export snippets…") { exportSnippets() }.disabled(library.snippets.isEmpty)
            } label: { Image(systemName: "ellipsis.circle") }
            Spacer()
          }.padding(.horizontal, 10)
        }
        .padding(.vertical, 12)
        .frame(minWidth: 170, idealWidth: 190, maxWidth: 230)
        ScrollView {
          VStack(alignment: .leading, spacing: 14) {
            HStack {
              Text(isNew ? "New snippet" : "Edit snippet").font(.headline)
              Spacer()
              if !isNew {
                Button("Duplicate") {
                  draft.id = UUID(); draft.name += " copy"; draft.abbreviation = ""; draft.isEnabled = false; isNew = true
                }
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                  .help("Delete snippet").accessibilityLabel("Delete snippet")
              }
            }
            LabeledContent("Name") { TextField("Email", text: $draft.name) }
            LabeledContent("Typed shortcut") { TextField(";em", text: $draft.abbreviation).font(.body.monospaced()) }
            VStack(alignment: .leading, spacing: 7) {
              HStack {
                Text("Expansion")
                Spacer()
                Menu("Insert field") {
                  Button("Date") { draft.content += "{{date}}" }
                  Button("Time") { draft.content += "{{time}}" }
                  Button("Date & Time") { draft.content += "{{datetime}}" }
                  Button("Clipboard") { draft.content += "{{clipboard}}" }
                }
              }
              TextEditor(text: $draft.content)
                .font(.body.monospaced())
                .frame(minHeight: 95)
                .padding(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
            }
            if hasDate { dateOptions }
            DisclosureGroup("Automatic expansion") {
              VStack(alignment: .leading, spacing: 8) {
                Toggle("Enable this typed shortcut", isOn: $draft.isEnabled)
                Picker("Expand", selection: $draft.waitsForSpace) {
                  Text("Immediately").tag(false)
                  Text("After Space · keep space").tag(true)
                }
                Toggle("Match case", isOn: $draft.caseSensitive)
                Toggle("Only after whitespace or at the start of a field", isOn: $draft.requiresWordBoundary)
                Text("Snippets are always available from the Clipp picker, even when automatic expansion is off.")
                  .font(.caption).foregroundStyle(.secondary)
              }.padding(.top, 6)
            }
            if let validation, hasChanges {
              Text(validation).font(.caption).foregroundStyle(.red)
            }
            HStack {
              Text(hasChanges ? "Unsaved changes" : (isNew ? "" : "Saved"))
                .font(.caption).foregroundStyle(.secondary)
              Spacer()
              Button("Revert") { draft = savedDraft }.disabled(!hasChanges)
              Button("Save snippet") {
                if library.save(draft) { savedDraft = draft; isNew = false }
              }
              .disabled(validation != nil || !hasChanges)
              .keyboardShortcut("s", modifiers: .command)
            }
            Divider()
            TimelineView(.periodic(from: .now, by: 1)) { context in
              VStack(alignment: .leading, spacing: 5) {
                Text("Preview").font(.headline)
                Text(SnippetTemplate.render(draft, now: context.date, clipboard: "Copied text") ?? SnippetTemplate.sizeError)
                  .textSelection(.enabled).foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            DisclosureGroup("Try this shortcut") {
            HStack {
              Text("Try it here").font(.headline)
              Spacer()
              Button("Preview expansion") {
                if let text = SnippetTemplate.render(draft, clipboard: "Copied text") { testText = text; testFeedback() }
                else { testResult = SnippetTemplate.sizeError }
              }
                .disabled(validation != nil)
            }
            TextField("Type \(draft.abbreviation)\(draft.waitsForSpace ? " then Space" : "")", text: $testText, axis: .vertical)
              .lineLimit(2...5)
              .textFieldStyle(.roundedBorder)
              .background(testHighlighted ? Color.accentColor.opacity(0.15) : .clear)
              .onChange(of: testText) { old, new in
                guard !replacingTest, new.count > old.count, validation == nil else { return }
                var matcher = SnippetMatcher()
                var sample = draft; sample.isEnabled = true
                if let match = matcher.append(new, snippets: [sample]),
                   let expansion = SnippetTemplate.render(draft, clipboard: "Copied text") {
                  replacingTest = true
                  testText = String(new.dropLast(match.typedText.count)) + expansion + match.suffix
                  testFeedback()
                  DispatchQueue.main.async { replacingTest = false }
                }
              }
            Text(testResult.isEmpty ? "This test works even when global expansion is off." : testResult)
              .font(.caption).foregroundStyle(.secondary)
            }

          }
          .textFieldStyle(.roundedBorder)
          .padding(18)
        }.frame(minWidth: 430)
      }
      Divider()
      DisclosureGroup("Expansion feedback") {
        HStack(spacing: 20) {
        Picker("Visual feedback", selection: $feedback) {
          Text("Subtle highlight").tag("highlight")
          Text("Confirmation badge").tag("badge")
          Text("Off").tag("off")
        }.frame(width: 290)
        Toggle("Play a soft pop", isOn: $sound)
        Spacer()
        }
      }.padding(14)
    }
    .frame(width: 740, height: min(620, (NSScreen.main?.visibleFrame.height ?? 760) - 140))
    .onAppear {
      library.reload()
      if !editorLoaded {
        loadSelection(library.editorSelection ?? library.snippets.first?.id)
        editorLoaded = true
      }
      receivePendingContent()
    }
    .onChange(of: library.pendingContent) { receivePendingContent() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      service.refresh()
      receivePendingContent()
    }
    .alert("Discard unsaved changes?", isPresented: $confirmDiscard) {
      Button("Keep editing", role: .cancel) { incomingContent = nil }
      Button("Discard", role: .destructive) {
        if let incomingContent { loadContent(incomingContent); self.incomingContent = nil }
        else { loadSelection(pendingSelection) }
      }
    }
    .alert("Delete “\(savedDraft.name)”?", isPresented: $confirmDelete) {
      Button("Cancel", role: .cancel) {}
      Button("Delete snippet", role: .destructive) {
        if let snippet = library.snippets.first(where: { $0.id == draft.id }), library.delete(snippet) {
          loadSelection(library.editorSelection)
        }
      }
    } message: { Text("This removes the saved snippet and its typed shortcut. This action cannot be undone.") }
    .alert("Snippets", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
      Button("OK") { library.message = nil }
    } message: { Text(library.message ?? "") }
    .sheet(isPresented: $examplesShown) { examplesSheet }
    .sheet(isPresented: $excludedAppsShown) { ExpansionExcludedAppsView() }
  }

  private var dateOptions: some View {
    DisclosureGroup("Date and time") {
      VStack(spacing: 10) {
        LabeledContent("Date") {
          Menu(formatExample(draft.dateFormat)) {
            ForEach(["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "d MMMM yyyy", "EEEE, d MMMM yyyy"], id: \.self) { value in
              Button(formatExample(value)) { draft.dateFormat = value }
            }
          }
        }
        LabeledContent("Time") {
          Menu(formatExample(draft.timeFormat)) {
            ForEach(["HH:mm", "HH:mm:ss", "h:mm a"], id: \.self) { value in
              Button(formatExample(value)) { draft.timeFormat = value }
            }
          }
        }
        Picker("Day", selection: $draft.dayOffset) {
          Text("Today").tag(0)
          Text("Tomorrow").tag(1)
          Text("Yesterday").tag(-1)
          if ![-1, 0, 1].contains(draft.dayOffset) { Text("\(draft.dayOffset) days from today").tag(draft.dayOffset) }
        }
        DisclosureGroup("Custom formats", isExpanded: $customFormats) {
          VStack(spacing: 8) {
            LabeledContent("Date pattern") { TextField("yyyy-MM-dd", text: $draft.dateFormat) }
            LabeledContent("Time pattern") { TextField("HH:mm", text: $draft.timeFormat) }
            LabeledContent("Days from today") { TextField("0", value: $draft.dayOffset, format: .number) }
            LabeledContent("Locale") { TextField("System default, or en_GB", text: $draft.localeIdentifier) }
            LabeledContent("Time zone") { TextField("System default, or Europe/Madrid", text: $draft.timeZoneIdentifier) }
          }.padding(.top, 8)
        }
      }.padding(.top, 8)
    }
  }

  private func formatExample(_ pattern: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = draft.localeIdentifier.isEmpty ? .current : Locale(identifier: draft.localeIdentifier)
    formatter.timeZone = draft.timeZoneIdentifier.isEmpty ? .current : TimeZone(identifier: draft.timeZoneIdentifier)
    formatter.dateFormat = pattern
    return formatter.string(from: .now)
  }

  private var examplesSheet: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Choose starter snippets").font(.headline)
      Text("Personal examples stay disabled until you edit and enable them.").foregroundStyle(.secondary)
      ForEach(SnippetDefinition.examples, id: \.abbreviation) { example in
        Toggle(isOn: Binding(get: { exampleSelection.contains(example.abbreviation) }, set: {
          if $0 { exampleSelection.insert(example.abbreviation) } else { exampleSelection.remove(example.abbreviation) }
        })) {
          HStack { Text(example.name); Spacer(); Text(example.abbreviation).font(.body.monospaced()).foregroundStyle(.secondary) }
        }
        .disabled(library.snippets.contains { $0.abbreviation == example.abbreviation })
      }
      HStack {
        Spacer()
        Button("Cancel") { examplesShown = false }
        Button("Add selected") {
          for example in SnippetDefinition.examples where exampleSelection.contains(example.abbreviation) {
            if !library.snippets.contains(where: { $0.abbreviation == example.abbreviation }) { library.save(example) }
          }
          if !hasChanges { loadSelection(library.editorSelection) }
          examplesShown = false
        }.keyboardShortcut(.defaultAction)
      }
    }.padding(22).frame(width: 460)
  }

  private func requestSelection(_ id: UUID?) {
    if !isNew && id == draft.id { return }
    if hasChanges { pendingSelection = id; confirmDiscard = true } else { loadSelection(id) }
  }

  private func loadSelection(_ id: UUID?) {
    if let snippet = library.snippets.first(where: { $0.id == id }) {
      draft = snippet.definition; isNew = false
    } else { draft = SnippetDefinition(); isNew = true }
    savedDraft = draft
    library.editorSelection = id
    testText = ""; testResult = ""
  }

  private func receivePendingContent() {
    guard let content = library.pendingContent else { return }
    library.pendingContent = nil
    if hasChanges { incomingContent = content; confirmDiscard = true }
    else { loadContent(content) }
  }

  private func loadContent(_ content: String) {
    draft = .init(name: String(content.prefix(40)), content: content)
    savedDraft = .init(id: draft.id)
    isNew = true
    testText = ""; testResult = ""
  }

  private func testFeedback() {
    testResult = "Expanded · \(draft.name)"
    if sound { service.playExpansionSound() }
    if feedback == "highlight" {
      testHighlighted = true
      Task { try? await Task.sleep(for: .milliseconds(400)); testHighlighted = false }
    }
  }

  private func exportSnippets() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Clipp snippets.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try library.exportData().write(to: url, options: .atomic) }
    catch { library.message = "Could not export snippets: \(error.localizedDescription)" }
  }

  private func importSnippets() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try library.importData(Data(contentsOf: url)); library.message = "Imported snippets are disabled. Review and enable the ones you want." }
    catch { library.message = "Could not import snippets: \(error.localizedDescription)" }
  }
}

private struct ExpansionExcludedAppsView: View {
  @Environment(\.dismiss) private var dismiss
  @Default(.expansionExcludedApps) private var excluded

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Don’t expand in these apps").font(.headline)
      Text("Clipp also respects excluded apps in History settings.").foregroundStyle(.secondary)
      List(excluded, id: \.self) { identifier in
        HStack {
          Text(identifier)
          Spacer()
          Button { excluded.removeAll { $0 == identifier } } label: { Image(systemName: "minus.circle") }
        }
      }.frame(height: 190)
      HStack {
        Button("Add application…") {
          let panel = NSOpenPanel()
          panel.allowedContentTypes = [.application]
          panel.directoryURL = URL(fileURLWithPath: "/Applications")
          guard panel.runModal() == .OK, let url = panel.url,
                let identifier = Bundle(url: url)?.bundleIdentifier, !excluded.contains(identifier) else { return }
          excluded.append(identifier)
        }
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }.padding(22).frame(width: 460)
  }
}
