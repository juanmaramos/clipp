import Sparkle

@Observable
@MainActor
class SoftwareUpdater: NSObject, SPUUpdaterDelegate {
  static let shared = SoftwareUpdater()
  let isDevelopmentBuild = Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true

  var automaticallyChecksForUpdates = false {
    didSet {
      updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
  }

  private var updater: SPUUpdater { updaterController.updater }
  @ObservationIgnored
  private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?

  @ObservationIgnored
  private lazy var updaterController = SPUStandardUpdaterController(
    startingUpdater: !isDevelopmentBuild && !CommandLine.arguments.contains("enable-testing"),
    updaterDelegate: self,
    userDriverDelegate: nil
  )

  override init() {
    super.init()
    automaticallyChecksForUpdatesObservation = updater.observe(
      \.automaticallyChecksForUpdates,
      options: [.initial, .new, .old]
    ) { [weak self] updater, change in
      guard change.newValue != change.oldValue else {
        return
      }

      let enabled = updater.automaticallyChecksForUpdates
      Task { @MainActor [weak self] in
        self?.automaticallyChecksForUpdates = enabled
      }
    }
  }

  func checkForUpdates() {
    guard !isDevelopmentBuild else { return }
    updater.checkForUpdates()
  }

  nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
    let nsError = error as NSError
    NSLog("Sparkle update aborted [domain=%@ code=%ld]: %@", nsError.domain, nsError.code, nsError.localizedDescription)
    if let failureReason = nsError.localizedFailureReason {
      NSLog("Sparkle failure reason: %@", failureReason)
    }
    if let recoverySuggestion = nsError.localizedRecoverySuggestion {
      NSLog("Sparkle recovery suggestion: %@", recoverySuggestion)
    }
  }

  nonisolated func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
    guard let error else {
      NSLog("Sparkle update cycle finished successfully for check type %ld", updateCheck.rawValue)
      return
    }

    let nsError = error as NSError
    NSLog("Sparkle update cycle finished with error [domain=%@ code=%ld]: %@", nsError.domain, nsError.code, nsError.localizedDescription)
  }
}
