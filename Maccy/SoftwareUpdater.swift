import Sparkle

@Observable
@MainActor
class SoftwareUpdater: NSObject, SPUUpdaterDelegate {
  static let shared = SoftwareUpdater()

  var automaticallyChecksForUpdates = false {
    didSet {
      updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }
  }

  private var updater: SPUUpdater
  private var automaticallyChecksForUpdatesObservation: NSKeyValueObservation?

  private lazy var updaterController = SPUStandardUpdaterController(
    startingUpdater: true,
    updaterDelegate: self,
    userDriverDelegate: nil
  )

  init() {
    super.init()
    updater = updaterController.updater
    automaticallyChecksForUpdatesObservation = updater.observe(
      \.automaticallyChecksForUpdates,
      options: [.initial, .new, .old]
    ) { [unowned self] updater, change in
      guard change.newValue != change.oldValue else {
        return
      }

      self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }
  }

  func checkForUpdates() {
    updater.checkForUpdates()
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
    let nsError = error as NSError
    NSLog("Sparkle update aborted [domain=%@ code=%ld]: %@", nsError.domain, nsError.code, nsError.localizedDescription)
    if let failureReason = nsError.localizedFailureReason {
      NSLog("Sparkle failure reason: %@", failureReason)
    }
    if let recoverySuggestion = nsError.localizedRecoverySuggestion {
      NSLog("Sparkle recovery suggestion: %@", recoverySuggestion)
    }
  }

  func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
    guard let error else {
      NSLog("Sparkle update cycle finished successfully for check type %ld", updateCheck.rawValue)
      return
    }

    let nsError = error as NSError
    NSLog("Sparkle update cycle finished with error [domain=%@ code=%ld]: %@", nsError.domain, nsError.code, nsError.localizedDescription)
  }
}
