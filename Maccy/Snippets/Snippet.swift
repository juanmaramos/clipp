import Foundation
import SwiftData

@Model
final class Snippet {
  var id: UUID = UUID()
  var name: String = ""
  var abbreviation: String = ""
  var content: String = ""
  var isEnabled: Bool = false
  var waitsForSpace: Bool = false
  var caseSensitive: Bool = true
  var requiresWordBoundary: Bool = true
  var dateFormat: String = "yyyy-MM-dd"
  var timeFormat: String = "HH:mm"
  var localeIdentifier: String = ""
  var timeZoneIdentifier: String = ""
  var dayOffset: Int = 0

  init(_ definition: SnippetDefinition) {
    apply(definition)
  }

  var definition: SnippetDefinition {
    SnippetDefinition(id: id, name: name, abbreviation: abbreviation, content: content,
                      isEnabled: isEnabled, waitsForSpace: waitsForSpace, caseSensitive: caseSensitive,
                      requiresWordBoundary: requiresWordBoundary, dateFormat: dateFormat, timeFormat: timeFormat,
                      localeIdentifier: localeIdentifier, timeZoneIdentifier: timeZoneIdentifier, dayOffset: dayOffset)
  }

  func apply(_ definition: SnippetDefinition) {
    id = definition.id
    name = definition.name
    abbreviation = definition.abbreviation
    content = definition.content
    isEnabled = definition.isEnabled
    waitsForSpace = definition.waitsForSpace
    caseSensitive = definition.caseSensitive
    requiresWordBoundary = definition.requiresWordBoundary
    dateFormat = definition.dateFormat
    timeFormat = definition.timeFormat
    localeIdentifier = definition.localeIdentifier
    timeZoneIdentifier = definition.timeZoneIdentifier
    dayOffset = definition.dayOffset
  }
}

struct SnippetDefinition: Codable, Equatable, Identifiable {
  var id = UUID()
  var name = ""
  var abbreviation = ""
  var content = ""
  var isEnabled = false
  var waitsForSpace = false
  var caseSensitive = true
  var requiresWordBoundary = true
  var dateFormat = "yyyy-MM-dd"
  var timeFormat = "HH:mm"
  var localeIdentifier = ""
  var timeZoneIdentifier = ""
  var dayOffset = 0

  func validationError(among others: [SnippetDefinition]) -> String? {
    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give this snippet a name." }
    if !(2...32).contains(abbreviation.count) || abbreviation.contains(where: { $0.isWhitespace || $0.isNewline }) {
      return "Use a shortcut of 2–32 characters without spaces."
    }
    if content.isEmpty { return "Add the text to insert." }
    if content.utf16.count > 100_000 { return "Keep a snippet under 100,000 characters." }
    if dateFormat.isEmpty || timeFormat.isEmpty { return "Choose a date and time format." }
    if !timeZoneIdentifier.isEmpty && TimeZone(identifier: timeZoneIdentifier) == nil {
      return "Choose a valid time zone, such as Europe/Madrid."
    }
    if !(-36_500...36_500).contains(dayOffset) { return "Use a date offset between −36,500 and 36,500 days." }
    if let error = SnippetTemplate.validationError(content) { return error }
    for other in others where other.id != id {
      let insensitive = !caseSensitive || !other.caseSensitive
      let lhs = insensitive ? abbreviation.lowercased() : abbreviation
      let rhs = insensitive ? other.abbreviation.lowercased() : other.abbreviation
      if lhs == rhs { return "This shortcut is already used by “\(other.name)”." }
      if (!waitsForSpace && rhs.hasPrefix(lhs)) || (!other.waitsForSpace && lhs.hasPrefix(rhs)) {
        return "This shortcut overlaps “\(other.abbreviation)”. Change it or make the shorter shortcut wait for Space."
      }
    }
    return nil
  }

  static var examples: [SnippetDefinition] {
    [
      .init(name: "Today’s date", abbreviation: "ddate", content: "{{date}}", isEnabled: true, waitsForSpace: true),
      .init(name: "Current time", abbreviation: "ttime", content: "{{time}}", isEnabled: true, waitsForSpace: true),
      .init(name: "Timestamp", abbreviation: ";stamp", content: "{{datetime}}", isEnabled: true),
      .init(name: "Email", abbreviation: ";em", content: "username@domain.com"),
      .init(name: "Phone", abbreviation: ";phone", content: "+country code phone number"),
      .init(name: "Full name", abbreviation: ";name", content: "Your name"),
      .init(name: "Address", abbreviation: ";addr", content: "Street and number\nCity, postal code\nCountry"),
      .init(name: "Signature", abbreviation: ";sig", content: "Best,\nYour name"),
      .init(name: "Personal link", abbreviation: ";link", content: "https://example.com"),
      .init(name: "Tomorrow", abbreviation: ";tomorrow", content: "{{date}}", isEnabled: true, dayOffset: 1),
      .init(name: "Quote clipboard", abbreviation: ";quote", content: "“{{clipboard}}”", isEnabled: true)
    ]
  }
}

enum SnippetTemplate {
  static let sizeError = "Expansion exceeds the 100,000-character limit."
  private static let tokenPattern = try! NSRegularExpression(pattern: #"\{\{([^{}]+)\}\}"#)
  private static let supportedTokens: Set<String> = ["date", "time", "datetime", "clipboard"]

  static func validationError(_ content: String) -> String? {
    for match in tokenPattern.matches(in: content, range: NSRange(content.startIndex..., in: content)) {
      let token = (content as NSString).substring(with: match.range(at: 1))
      if !supportedTokens.contains(token) { return "Unknown field {{\(token)}}. Use Date, Time, Date & Time, or Clipboard." }
    }
    return nil
  }

  static func render(_ snippet: SnippetDefinition, now: Date = .now, clipboard: String = "",
                     locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
    guard snippet.content.utf16.count <= 100_000 else { return nil }
    let formatter = DateFormatter()
    formatter.locale = snippet.localeIdentifier.isEmpty ? locale : Locale(identifier: snippet.localeIdentifier)
    formatter.timeZone = TimeZone(identifier: snippet.timeZoneIdentifier) ?? timeZone
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = formatter.timeZone
    formatter.calendar = calendar
    let date = calendar.date(byAdding: .day, value: snippet.dayOffset, to: now) ?? now
    var result = snippet.content
    var resultLength = result.utf16.count
    // Replace from the end; clipboard contents are literal and never evaluated as another template.
    for match in tokenPattern.matches(in: snippet.content, range: NSRange(snippet.content.startIndex..., in: snippet.content)).reversed() {
      let token = (snippet.content as NSString).substring(with: match.range(at: 1))
      let replacement: String
      switch token {
      case "clipboard": replacement = clipboard
      case "date": formatter.dateFormat = snippet.dateFormat; replacement = formatter.string(from: date)
      case "time": formatter.dateFormat = snippet.timeFormat; replacement = formatter.string(from: now)
      case "datetime": formatter.dateFormat = "\(snippet.dateFormat) \(snippet.timeFormat)"; replacement = formatter.string(from: date)
      default: continue
      }
      resultLength += replacement.utf16.count - match.range.length
      guard resultLength <= 100_000 else { return nil }
      if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: replacement) }
    }
    return result
  }
}

struct SnippetMatcher {
  struct Match {
    var snippet: SnippetDefinition
    var typedText: String
    var suffix: String
  }
  private(set) var buffer = ""

  mutating func reset() { buffer = "" }
  mutating func backspace() { if !buffer.isEmpty { buffer.removeLast() } }

  mutating func append(_ text: String, snippets: [SnippetDefinition]) -> Match? {
    buffer += text
    let limit = (snippets.map { $0.abbreviation.count }.max() ?? 0) + 2
    buffer = String(buffer.suffix(limit))
    for snippet in snippets where snippet.isEnabled {
      let suffix = snippet.waitsForSpace ? " " : ""
      let trigger = snippet.abbreviation + suffix
      let candidate = String(buffer.suffix(trigger.count))
      let matches = snippet.caseSensitive ? candidate == trigger : candidate.lowercased() == trigger.lowercased()
      guard matches else { continue }
      let preceding = buffer.dropLast(trigger.count).last
      guard !snippet.requiresWordBoundary || preceding == nil || preceding!.isWhitespace else { continue }
      reset()
      return Match(snippet: snippet, typedText: candidate, suffix: suffix)
    }
    return nil
  }
}
