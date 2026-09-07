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
          Toggle("Enable text expansion", isOn: $enabled).disabled(service.isSandboxed)
          Spacer()
          Button("Excluded apps…") { excludedAppsShown = true }
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
            Button { requestSelection(nil) } label: { Image(systemName: "plus") }.help("New snippet")
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
                Button(role: .destructive) {
                  if let snippet = library.snippets.first(where: { $0.id == draft.id }) {
                    library.delete(snippet); loadSelection(library.editorSelection)
                  }
                } label: { Image(systemName: "trash") }.help("Delete snippet")
              }
            }
            LabeledContent("Name") { TextField("Email", text: $draft.name) }
            LabeledContent("Typed shortcut") { TextField(";em", text: $draft.abbreviation).font(.body.monospaced()) }
            Picker("Expand", selection: $draft.waitsForSpace) {
              Text("Immediately").tag(false)
              Text("After Space · keep space").tag(true)
            }
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
            DisclosureGroup("Matching") {
              VStack(alignment: .leading) {
                Toggle("Match case", isOn: $draft.caseSensitive)
                Toggle("Only after whitespace or at the start of a field", isOn: $draft.requiresWordBoundary)
              }.padding(.top, 6)
            }
            Toggle("Expand this shortcut automatically", isOn: $draft.isEnabled)
            Text("Disabled snippets remain available from the Snippets list in Clipp.")
              .font(.caption).foregroundStyle(.secondary)
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
          .textFieldStyle(.roundedBorder)
          .padding(18)
        }.frame(minWidth: 430)
      }
      Divider()
      HStack(spacing: 20) {
        Picker("Visual feedback", selection: $feedback) {
          Text("Subtle highlight").tag("highlight")
          Text("Confirmation badge").tag("badge")
          Text("Off").tag("off")
        }.frame(width: 290)
        Toggle("Play a soft pop", isOn: $sound)
        Spacer()
      }.padding(14)
    }
    .frame(width: 780, height: 650)
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
    .alert("Snippets", isPresented: Binding(get: { library.message != nil }, set: { if !$0 { library.message = nil } })) {
      Button("OK") { library.message = nil }
    } message: { Text(library.message ?? "") }
    .sheet(isPresented: $examplesShown) { examplesSheet }
    .sheet(isPresented: $excludedAppsShown) { ExpansionExcludedAppsView() }
  }

  private var dateOptions: some View {
    DisclosureGroup("Date and time options") {
      VStack(spacing: 10) {
        LabeledContent("Date format") {
          TextField("yyyy-MM-dd", text: $draft.dateFormat)
          Menu("Presets") {
            ForEach(["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "d MMMM yyyy", "EEEE, d MMMM yyyy"], id: \.self) { value in
              Button(value) { draft.dateFormat = value }
            }
          }
        }
        LabeledContent("Time format") {
          TextField("HH:mm", text: $draft.timeFormat)
          Menu("Presets") {
            ForEach(["HH:mm", "HH:mm:ss", "h:mm a"], id: \.self) { value in Button(value) { draft.timeFormat = value } }
          }
        }
        LabeledContent("Days from today") { TextField("0", value: $draft.dayOffset, format: .number).frame(width: 90) }
        Text("Use 1 for tomorrow or −1 for yesterday. Time-only fields use the current time.")
          .font(.caption).foregroundStyle(.secondary)
        LabeledContent("Locale") { TextField("System default, or en_GB", text: $draft.localeIdentifier) }
        LabeledContent("Time zone") { TextField("System default, or Europe/Madrid", text: $draft.timeZoneIdentifier) }
      }.padding(.top, 8)
    }
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
      Text("Clipp also respects the application rules in Ignore settings.").foregroundStyle(.secondary)
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
