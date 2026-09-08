import SwiftUI
import Defaults

struct StorageSettingsPane: View {
  @Default(.size) private var size
  @Default(.sortBy) private var sortBy

  @Default(.enabledPasteboardTypes) private var enabledTypes
  @State private var exclusionsShown = false

  private let sizeFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.minimum = 1
    formatter.maximum = 999
    return formatter
  }()

  var body: some View {
    Form {
      Section {
        Toggle(
          isOn: binding(for: StorageType.files),
          label: { Text("Files", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: binding(for: StorageType.images),
          label: { Text("Images", tableName: "StorageSettings") }
        )
        Toggle(
          isOn: binding(for: StorageType.text),
          label: { Text("Text", tableName: "StorageSettings") }
        )
        Text("SaveDescription", tableName: "StorageSettings")
          .controlSize(.small)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      LabeledContent(String(localized: "Size", table: "StorageSettings")) {
        HStack {
          TextField("", value: $size, formatter: sizeFormatter)
            .frame(width: 80)
            .help(Text("SizeTooltip", tableName: "StorageSettings"))
          Stepper("", value: $size, in: 1...999)
            .labelsHidden()

        }
      }

      LabeledContent(String(localized: "SortBy", table: "StorageSettings")) {
        Picker("", selection: $sortBy) {
          ForEach(Sorter.By.allCases) { mode in
            Text(mode.description)
          }
        }
        .labelsHidden()
        .frame(width: 160, alignment: .leading)
        .help(Text("SortByTooltip", tableName: "StorageSettings"))
      }
      Section("Capture & privacy") {
        AdvancedSettingsPane()
        Button("Excluded apps and rules…") { exclusionsShown = true }
      }

    }
    .formStyle(.grouped)
    .sheet(isPresented: $exclusionsShown) {
      VStack {
        IgnoreSettingsPane()
        Button("Done") { exclusionsShown = false }.keyboardShortcut(.defaultAction)
      }.padding()
    }
  }

  private func binding(for storageType: StorageType) -> Binding<Bool> {
    Binding(get: { enabledTypes.isSuperset(of: storageType.types) }, set: { enabled in
      if enabled { enabledTypes.formUnion(storageType.types) }
      else { enabledTypes.subtract(storageType.types) }
    })
  }
}

#Preview {
  StorageSettingsPane()
    .environment(\.locale, .init(identifier: "en"))
}
