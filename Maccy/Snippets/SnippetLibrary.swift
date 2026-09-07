import AppKit
import SwiftData
import Observation

@MainActor
@Observable
final class SnippetLibrary {
  static let shared = SnippetLibrary(context: Storage.shared.context)
  private(set) var snippets: [Snippet] = []
  var editorSelection: UUID?
  var message: String?
  private let context: ModelContext

  var definitions: [SnippetDefinition] { snippets.map(\.definition) }

  init(context: ModelContext) {
    self.context = context
    reload()
  }

  func reload() {
    do { snippets = try context.fetch(FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\.name)])) }
    catch { message = "Could not load snippets: \(error.localizedDescription)" }
  }

  @discardableResult
  func save(_ definition: SnippetDefinition) -> Bool {
    if let error = definition.validationError(among: definitions) { message = error; return false }
    let existing = snippets.first { $0.id == definition.id }
    let previous = existing?.definition
    let item = existing ?? Snippet(definition)
    if existing == nil { context.insert(item) } else { item.apply(definition) }
    do {
      try context.save()
      reload()
      editorSelection = definition.id
      return true
    } catch {
      if let previous { item.apply(previous) } else { context.delete(item) }
      message = "Could not save snippet: \(error.localizedDescription)"
      return false
    }
  }

  func delete(_ snippet: Snippet) {
    let previous = snippet.definition
    context.delete(snippet)
    do { try context.save(); reload(); editorSelection = snippets.first?.id }
    catch {
      context.insert(Snippet(previous))
      message = "Could not delete snippet: \(error.localizedDescription)"
    }
  }

  func create(from text: String) {
    // The editor opens an unsaved draft; clipboard history is not altered.
    pendingContent = text
    editorSelection = nil
    AppState.shared.openPreferences(pane: .snippets)
  }

  var pendingContent: String?

  struct Archive: Codable {
    var version = 1
    var snippets: [SnippetDefinition]
  }

  func exportData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(Archive(snippets: definitions))
  }

  func importData(_ data: Data) throws {
    guard data.count <= 5_000_000 else { throw ImportError.invalid("This file exceeds the 5 MB import limit.") }
    let archive = try JSONDecoder().decode(Archive.self, from: data)
    guard archive.version == 1, archive.snippets.count <= 1_000 else {
      throw ImportError.invalid("Unsupported snippet file version or too many snippets.")
    }
    var staged = definitions
    var additions: [Snippet] = []
    for var definition in archive.snippets {
      // Imports never activate global typing behavior without the user's choice.
      definition.id = UUID()
      definition.isEnabled = false
      if let error = definition.validationError(among: staged) { throw ImportError.invalid(error) }
      staged.append(definition)
      additions.append(Snippet(definition))
    }
    additions.forEach { context.insert($0) }
    do { try context.save(); reload() }
    catch { additions.forEach { context.delete($0) }; throw error }
  }

  enum ImportError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
  }
}
