import Foundation
import Observation

struct UsageDay: Codable {
  var date: String
  var clipboardReuses = 0
  var expansions = 0
  var charactersAvoided = 0
}

struct UsageSummary {
  var clipboardReuses = 0
  var expansions = 0
  var charactersAvoided = 0
  var activeDays = 0

  func typingSeconds(wordsPerMinute: Int) -> Double {
    Double(charactersAvoided) * 60 / (5 * Double(max(1, wordsPerMinute)))
  }

  func clipboardSeconds(secondsPerReuse: Int) -> Double {
    Double(clipboardReuses) * Double(max(0, secondsPerReuse))
  }
}

@MainActor
@Observable
final class UsageStatistics {
  static let shared = UsageStatistics(recordsUsage: !CommandLine.arguments.contains("enable-testing"))
  static let storageKey = "clippUsageDaysV1"

  var enabled: Bool { didSet { preferences.set(enabled, forKey: "clippUsageEnabled") } }
  var wordsPerMinute: Int { didSet { preferences.set(wordsPerMinute, forKey: "clippUsageWPM") } }
  var secondsPerReuse: Int { didSet { preferences.set(secondsPerReuse, forKey: "clippUsageReuseSeconds") } }
  private(set) var days: [UsageDay] = []
  private(set) var errorMessage: String?
  @ObservationIgnored private let preferences: UserDefaults
  @ObservationIgnored private let recordsUsage: Bool

  init(preferences: UserDefaults = .standard, recordsUsage: Bool = true) {
    self.preferences = preferences
    self.recordsUsage = recordsUsage
    enabled = preferences.object(forKey: "clippUsageEnabled") as? Bool ?? true
    wordsPerMinute = min(200, max(10, preferences.object(forKey: "clippUsageWPM") as? Int ?? 50))
    secondsPerReuse = min(30, max(0, preferences.object(forKey: "clippUsageReuseSeconds") as? Int ?? 5))
    guard let data = preferences.data(forKey: Self.storageKey) else { return }
    do {
      let decoded = try JSONDecoder().decode([UsageDay].self, from: data)
      guard decoded.allSatisfy({ $0.clipboardReuses >= 0 && $0.expansions >= 0 && $0.charactersAvoided >= 0 }),
            Set(decoded.map(\.date)).count == decoded.count else { throw CocoaError(.coderReadCorrupt) }
      days = decoded
    } catch {
      errorMessage = "Saved statistics could not be read. Recording is paused. Reset statistics to start again."
    }
  }

  func recordClipboardReuse(at date: Date = .now) {
    record(at: date) { $0.clipboardReuses += 1 }
  }

  func recordExpansion(expandedCharacters: Int, abbreviationCharacters: Int, at date: Date = .now) {
    guard expandedCharacters >= 0, abbreviationCharacters >= 0 else { return }
    record(at: date) {
      $0.expansions += 1
      $0.charactersAvoided += max(0, expandedCharacters - abbreviationCharacters)
    }
  }

  func summary(lastDays: Int? = nil, now: Date = .now, calendar: Calendar = .current) -> UsageSummary {
    let today = Self.dayKey(now, calendar: calendar)
    let start = lastDays.flatMap { calendar.date(byAdding: .day, value: 1 - max(1, $0), to: now) }
      .map { Self.dayKey($0, calendar: calendar) }
    return days.filter { $0.date <= today && (start == nil || $0.date >= start!) }
      .reduce(into: UsageSummary()) { total, day in
        total.clipboardReuses += day.clipboardReuses
        total.expansions += day.expansions
        total.charactersAvoided += day.charactersAvoided
        if day.clipboardReuses + day.expansions > 0 { total.activeDays += 1 }
      }
  }

  func reset() {
    preferences.removeObject(forKey: Self.storageKey)
    days = []
    errorMessage = nil
  }

  private func record(at date: Date, update: (inout UsageDay) -> Void) {
    guard recordsUsage, enabled, errorMessage == nil else { return }
    let key = Self.dayKey(date)
    var next = days
    if let index = next.firstIndex(where: { $0.date == key }) { update(&next[index]) }
    else {
      var day = UsageDay(date: key)
      update(&day)
      next.append(day)
    }
    do {
      let data = try JSONEncoder().encode(next)
      preferences.set(data, forKey: Self.storageKey)
      days = next
    } catch {
      errorMessage = "Statistics could not be saved. Recording is paused until statistics are reset."
    }
  }

  private static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = calendar.timeZone
    let parts = gregorian.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
  }
}
