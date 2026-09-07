import SwiftUI
import Defaults

struct IgnoreRegexpsSettingsView: View {
  @Default(.ignoreRegexp) private var ignoredRegexps
  @State private var selection: String?
  @State private var draft = ""

  private var validation: String? {
    guard !draft.isEmpty else { return "Enter a regular expression." }
    do { _ = try NSRegularExpression(pattern: draft); return nil }
    catch { return "Invalid expression: \(error.localizedDescription)" }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      List(Array(Set(ignoredRegexps)).sorted(), id: \.self, selection: $selection) { expression in
        HStack {
          Text(expression).font(.body.monospaced())
          if (try? NSRegularExpression(pattern: expression)) == nil {
            Image(systemName: "exclamationmark.triangle").help("Invalid rule. Other valid rules still apply.")
          }
        }
      }
      .onChange(of: selection) { _, value in draft = value ?? "" }
      TextField("Regular expression", text: $draft).textFieldStyle(.roundedBorder)
        .onSubmit { save() }
      if let validation, !draft.isEmpty { Text(validation).font(.caption).foregroundStyle(.red) }
      HStack {
        Button("New rule") { selection = nil; draft = "" }
        Button("Remove", role: .destructive) {
          ignoredRegexps.removeAll { $0 == selection }; selection = nil; draft = ""
        }.disabled(selection == nil)
        Spacer()
        Button(selection == nil ? "Add rule" : "Save rule") { save() }
          .disabled(validation != nil)
      }
      Text("Matching text is excluded from clipboard history. Rules are checked independently.")
        .font(.caption).foregroundStyle(.secondary)
    }.padding()
  }

  private func save() {
    guard validation == nil else { return }
    var rules = ignoredRegexps.filter { $0 != selection }
    if !rules.contains(draft) { rules.append(draft) }
    ignoredRegexps = rules
    selection = draft
  }
}
