import SwiftUI

struct StatisticsSettingsPane: View {
  @State private var statistics = UsageStatistics.shared
  @State private var period = 30
  @State private var confirmReset = false
  @State private var showCalculation = false

  var body: some View {
    let summary = statistics.summary(lastDays: period == 0 ? nil : period)
    let typing = summary.typingSeconds(wordsPerMinute: statistics.wordsPerMinute)
    let clipboard = summary.clipboardSeconds(secondsPerReuse: statistics.secondsPerReuse)
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          Text("Time saved").font(.title2.bold())
          Spacer()
          Picker("Period", selection: $period) {
            Text("Today").tag(1)
            Text("7 days").tag(7)
            Text("30 days").tag(30)
            Text("All time").tag(0)
          }.labelsHidden().frame(width: 130)
        }
        VStack(alignment: .leading, spacing: 6) {
          Text(Self.duration(typing + clipboard)).font(.system(size: 36, weight: .semibold, design: .rounded))
          Text("Estimated time saved").foregroundStyle(.secondary)
          if summary.activeDays > 0 {
            Text("\(Self.duration((typing + clipboard) / Double(summary.activeDays))) per active day · \(summary.activeDays) active \(summary.activeDays == 1 ? "day" : "days")")
              .font(.caption).foregroundStyle(.secondary)
          } else {
            Text("Reuse something from history or expand a typed shortcut to begin.")
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        Divider()
        HStack(alignment: .top, spacing: 40) {
          metric("Clipboard reuses", count: summary.clipboardReuses, detail: "\(Self.duration(clipboard)) estimated")
          metric("Typed expansions", count: summary.expansions, detail: "\(Self.duration(typing)) estimated")
          metric("Characters avoided", count: summary.charactersAvoided, detail: "From typed expansions")
        }
        Divider()
        DisclosureGroup("How we calculate this", isExpanded: $showCalculation) {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Typing speed")
              Spacer()
              Stepper("\(statistics.wordsPerMinute) words/min", value: $statistics.wordsPerMinute, in: 10...200, step: 5)
                .accessibilityLabel("Typing speed")
                .accessibilityValue("\(statistics.wordsPerMinute) words per minute")
                .fixedSize()
            }
            Text("Typing time in seconds = (expanded characters − shortcut characters) × 60 ÷ (words/min × 5). Only confirmed automatic expansions count; previews and snippets picked from the library do not. This estimates typing effort, without timing editing or corrections.")
            HStack {
              Text("Saved per clipboard reuse")
              Spacer()
              Stepper("\(statistics.secondsPerReuse) seconds", value: $statistics.secondsPerReuse, in: 0...30)
                .accessibilityLabel("Saved per clipboard reuse")
                .accessibilityValue("\(statistics.secondsPerReuse) seconds")
                .fixedSize()
            }
            Text("Clipboard time = reuses × seconds saved. The 5-second default is an illustrative assumption for retrieving an older item instead of finding and copying its source again. It is not a measured average. Set it to 0 to exclude it. Ordinary copies and items already on the clipboard do not count.")
            Text("Changing these assumptions recalculates all periods. An active day has at least one counted reuse or expansion. Estimates are rounded and compare with doing these actions manually, not with other users.")
            HStack {
              Link("TextExpander’s method", destination: URL(string: "https://textexpander.com/learn/accounts/statistics/textexpander-statistics-calculated")!)
              Link("Typing study", destination: URL(string: "https://userinterfaces.aalto.fi/136Mkeystrokes/")!)
              Link("Interaction model", destination: URL(string: "https://doi.org/10.1145/358886.358895")!)
            }
          }.font(.caption).foregroundStyle(.secondary).padding(.top, 10)
        }
        Toggle("Keep usage statistics on this Mac", isOn: $statistics.enabled)
        Text("Only daily counts are saved, starting with this version. No text, clipboard content, app names, or typing history is stored in statistics. Nothing is sent anywhere. Turning this off pauses recording and keeps existing totals.")
          .font(.caption).foregroundStyle(.secondary)
        if let error = statistics.errorMessage { Text(error).foregroundStyle(.red) }
        Button("Reset statistics…", role: .destructive) { confirmReset = true }
      }.padding(24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .confirmationDialog("Reset all usage statistics?", isPresented: $confirmReset) {
      Button("Reset statistics", role: .destructive) { statistics.reset() }
    } message: {
      Text("This deletes your local usage totals for every period. Clipboard history and snippets are kept.")
    }
  }

  private func metric(_ title: String, count: Int, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(count, format: .number).font(.title2.monospacedDigit())
      Text(title)
      Text(detail).font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }

  static func duration(_ seconds: Double) -> String {
    guard seconds > 0 else { return "0 min" }
    guard seconds >= 60 else { return "<1 min" }
    let minutes = Int((seconds / 60).rounded())
    return minutes < 60 ? "≈\(minutes) min" : "≈\(minutes / 60) hr \(minutes % 60) min"
  }
}
