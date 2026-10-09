import AppKit
import Carbon
import Foundation

struct ExpansionTapPolicy: Equatable {
  var enabled = false
  var snippets: [SnippetDefinition] = []
  var excludedApps: Set<String> = []
  var ignoredApps: Set<String> = []
  var ignoreAllAppsExceptListed = false
  var applicationPID: pid_t?
  var applicationIdentifier: String?
  var applicationIsActive = false
  var keyboardLayoutIsActive = true
  var generation: UInt64 = 0
  var validUntil = ContinuousClock.now

  func hasSameRules(as other: Self) -> Bool {
    enabled == other.enabled && snippets == other.snippets && excludedApps == other.excludedApps &&
      ignoredApps == other.ignoredApps && ignoreAllAppsExceptListed == other.ignoreAllAppsExceptListed &&
      applicationPID == other.applicationPID && applicationIdentifier == other.applicationIdentifier &&
      applicationIsActive == other.applicationIsActive && keyboardLayoutIsActive == other.keyboardLayoutIsActive
  }
}

final class ExpansionCommitGate: @unchecked Sendable {
  enum Phase: Equatable { case preparing, committed, cancelled, finished }

  private let lock = NSLock()
  private let deadline: ContinuousClock.Instant
  private let generation: UInt64?
  private var currentPhase = Phase.preparing

  init(generation: UInt64?, timeout: Duration) {
    self.generation = generation
    deadline = ContinuousClock.now.advanced(by: timeout)
  }

  func phase() -> Phase {
    lock.lock()
    defer { lock.unlock() }
    if case .preparing = currentPhase, ContinuousClock.now >= deadline { currentPhase = .cancelled }
    return currentPhase
  }

  func beginCommit(currentGeneration: UInt64?) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard case .preparing = currentPhase,
          ContinuousClock.now < deadline,
          generation == nil || generation == currentGeneration else {
      if case .preparing = currentPhase { currentPhase = .cancelled }
      return false
    }
    currentPhase = .committed
    return true
  }

  func expire() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard case .preparing = currentPhase, ContinuousClock.now >= deadline else { return false }
    currentPhase = .cancelled
    return true
  }

  func cancelPreparation() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard case .preparing = currentPhase else { return false }
    currentPhase = .cancelled
    return true
  }

  func finish() {
    lock.lock()
    defer { lock.unlock() }
    currentPhase = .finished
  }
}

struct ExpansionCandidate: Sendable {
  let token: UInt64
  let generation: UInt64
  let applicationPID: pid_t
  let applicationIdentifier: String
  let match: SnippetMatcher.Match
  let gate: ExpansionCommitGate
}

struct ExpansionManualTransaction: Sendable {
  let token: UInt64
  let gate: ExpansionCommitGate
}

final class ExpansionEventTapRuntime: @unchecked Sendable {
  static let eventTag: Int64 = 0x434C495050
  typealias CandidateHandler = @MainActor @Sendable (ExpansionCandidate) async -> Void
  typealias EventPoster = (CGEventTapProxy?, CGEvent) -> Void
  typealias PreparationTimerObserver = (UInt64, ExpansionCommitGate.Phase) -> Void

  private struct ActiveTransaction {
    let token: UInt64
    let generation: UInt64?
    let gate: ExpansionCommitGate
    let delimiter: CGEvent?
  }

  private let preparationTimeout: Duration
  private let candidateHandler: CandidateHandler
  private let eventPoster: EventPoster
  private let preparationTimerObserver: PreparationTimerObserver
  private var policy = ExpansionTapPolicy()
  private var matcher = SnippetMatcher()
  private var queuedEvents = ExpansionEventBuffer()
  private var activeTransaction: ActiveTransaction?
  private var generation: UInt64 = 0
  private var nextToken: UInt64 = 0
  private var candidateDeliveryToken: UInt64?
  private var lastApplicationPID: pid_t?
  private var lastInputAt = Date.distantPast
  private var preparationTimer: CFRunLoopTimer?
  private var stopAfterTransaction = false

  // These fields are read by the caller only to schedule work; transaction state stays on the tap runloop.
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var tapRunLoop: CFRunLoop?
  private var keepAliveSource: CFRunLoopSource?
  private var tapThreadID: pthread_t?
  private let runLoopLock = NSLock()
  private var runLoopStarting = false
  private var runLoopReadyWaiters: [CheckedContinuation<Void, Never>] = []

  init(
    preparationTimeout: Duration = .milliseconds(500),
    eventPoster: @escaping EventPoster = { proxy, event in
      if let proxy { event.tapPostEvent(proxy) }
      else { event.post(tap: .cgSessionEventTap) }
    },
    preparationTimerObserver: @escaping PreparationTimerObserver = { _, _ in },
    candidateHandler: @escaping CandidateHandler
  ) {
    self.preparationTimeout = preparationTimeout
    self.eventPoster = eventPoster
    self.preparationTimerObserver = preparationTimerObserver
    self.candidateHandler = candidateHandler
  }

  func startListening(expectedGeneration: UInt64? = nil) async -> Bool {
    await ensureTapRunLoop()
    if await runOnTapRunLoop({
      guard expectedGeneration == nil || expectedGeneration == self.generation,
            self.policy.enabled else { return false }
      guard let tap = self.tap, self.source != nil else {
        self.detachTap()
        return false
      }
      guard Self.resumeTap(tap) else {
        self.detachTap()
        return false
      }
      return true
    }) { return true }

    let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
                               .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
    let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                      options: .defaultTap, eventsOfInterest: mask,
                                      callback: Self.eventTapCallback,
                                      userInfo: Unmanaged.passUnretained(self).toOpaque()),
          let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
      return false
    }
    let attached = await runOnTapRunLoop {
      guard expectedGeneration == nil || expectedGeneration == self.generation,
            self.policy.enabled else {
        CFMachPortInvalidate(tap)
        return false
      }
      self.attach(source: source, tap: tap)
      CGEvent.tapEnable(tap: tap, enable: true)
      guard CFMachPortIsValid(tap), CGEvent.tapIsEnabled(tap: tap) else {
        self.detachTap()
        return false
      }
      return true
    }
    return attached
  }

  static func resumeTap(
    _ tap: CFMachPort,
    isEnabled: (CFMachPort) -> Bool = { CGEvent.tapIsEnabled(tap: $0) },
    enable: (CFMachPort) -> Void = { CGEvent.tapEnable(tap: $0, enable: true) }
  ) -> Bool {
    guard CFMachPortIsValid(tap) else { return false }
    if !isEnabled(tap) { enable(tap) }
    return CFMachPortIsValid(tap) && isEnabled(tap)
  }

  // The test source is installed by the same runloop registration path as the production tap source.
  func startForTesting(source: CFRunLoopSource) async {
    await ensureTapRunLoop()
    await runOnTapRunLoop { self.attach(source: source, tap: nil) }
  }

  func signalForTesting(_ source: CFRunLoopSource) {
    CFRunLoopSourceSignal(source)
    if let runLoop = currentTapRunLoop { CFRunLoopWakeUp(runLoop) }
  }

  func stopListening(expectedGeneration: UInt64? = nil) async {
    await runOnTapRunLoop {
      guard expectedGeneration == nil || expectedGeneration == self.generation else { return }
      guard let active = self.activeTransaction else { self.detachTap(); return }
      if active.gate.phase() == .committed {
        self.stopAfterTransaction = true
      } else {
        self.stopAfterTransaction = true
        if active.gate.cancelPreparation() || active.gate.phase() == .cancelled {
          self.abortPreparing(active, proxy: nil, replayDelimiter: true)
        }
      }
    }
  }

  @discardableResult
  func updatePolicy(_ newPolicy: ExpansionTapPolicy) async -> UInt64 {
    await ensureTapRunLoop()
    return await runOnTapRunLoop {
      guard newPolicy.generation >= self.generation else { return self.generation }
      guard !self.policy.hasSameRules(as: newPolicy) else {
        self.policy.validUntil = newPolicy.validUntil
        self.policy.generation = newPolicy.generation
        self.generation = newPolicy.generation
        return self.generation
      }
      self.policy = newPolicy
      self.generation = newPolicy.generation
      self.matcher.reset()
      self.lastApplicationPID = newPolicy.applicationPID
      if let active = self.activeTransaction, active.generation != nil,
         active.gate.cancelPreparation() || active.gate.phase() == .cancelled {
        self.abortPreparing(active, proxy: nil, replayDelimiter: true)
      }
      if newPolicy.enabled { self.stopAfterTransaction = false }
      return self.generation
    }
  }

  func isCurrent(_ candidate: ExpansionCandidate) async -> Bool {
    await runOnTapRunLoop {
      guard candidate.generation == self.generation,
            self.candidateDeliveryToken == candidate.token,
            let active = self.activeTransaction,
            active.token == candidate.token,
            active.gate.phase() == .preparing else { return false }
      return true
    }
  }

  func finishCandidate(_ candidate: ExpansionCandidate, replayDelimiter: Bool) async {
    await runOnTapRunLoop {
      guard let active = self.activeTransaction, active.token == candidate.token else {
        if self.candidateDeliveryToken == candidate.token { self.candidateDeliveryToken = nil }
        return
      }
      guard active.gate.cancelPreparation() || active.gate.phase() == .cancelled else { return }
      self.abortPreparing(active, proxy: nil, replayDelimiter: replayDelimiter)
      if self.candidateDeliveryToken == candidate.token { self.candidateDeliveryToken = nil }
    }
  }

  func finishCommitted(_ token: UInt64, replayDelimiter: Bool) async {
    await runOnTapRunLoop {
      guard let active = self.activeTransaction, active.token == token,
            active.gate.phase() == .committed else { return }
      self.cancelPreparationTimer()
      active.gate.finish()
      if replayDelimiter, let delimiter = active.delimiter { self.post(delimiter, proxy: nil) }
      self.flushQueuedEvents(proxy: nil)
      self.activeTransaction = nil
      if self.candidateDeliveryToken == token { self.candidateDeliveryToken = nil }
      if self.stopAfterTransaction { self.detachTap(); self.stopAfterTransaction = false }
    }
  }

  func beginManualTransaction() async -> ExpansionManualTransaction? {
    await ensureTapRunLoop()
    return await runOnTapRunLoop {
      guard self.activeTransaction == nil, self.candidateDeliveryToken == nil else { return nil }
      self.nextToken &+= 1
      let gate = ExpansionCommitGate(generation: nil, timeout: self.preparationTimeout)
      self.activeTransaction = ActiveTransaction(token: self.nextToken, generation: nil, gate: gate, delimiter: nil)
      self.schedulePreparationTimeout(self.nextToken, gate: gate)
      return ExpansionManualTransaction(token: self.nextToken, gate: gate)
    }
  }

  func finishManualTransaction(_ transaction: ExpansionManualTransaction) async {
    await finishCommitted(transaction.token, replayDelimiter: false)
  }

  func cancelManualTransaction(_ transaction: ExpansionManualTransaction) async {
    await runOnTapRunLoop {
      guard let active = self.activeTransaction, active.token == transaction.token else { return }
      guard active.gate.cancelPreparation() || active.gate.phase() == .cancelled else { return }
      self.abortPreparing(active, proxy: nil, replayDelimiter: false)
    }
  }

  func shutdown() async {
    await runOnTapRunLoop {
      if let active = self.activeTransaction, active.gate.phase() != .committed {
        _ = active.gate.cancelPreparation()
        self.abortPreparing(active, proxy: nil, replayDelimiter: true)
      }
      self.detachTap()
      self.cancelPreparationTimer()
      if let runLoop = self.tapRunLoop {
        CFRunLoopStop(runLoop)
        CFRunLoopWakeUp(runLoop)
      }
    }
  }

  func process(_ proxy: CGEventTapProxy?, _ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    let unchanged = Unmanaged.passUnretained(event)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      matcher.reset()
      lastApplicationPID = nil
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return unchanged
    }
    if event.getIntegerValueField(.eventSourceUserData) == Self.eventTag { return unchanged }

    guard let active = activeTransaction else { return processIdle(type, event) }
    switch active.gate.phase() {
    case .committed:
      return queuedEvents.append(event) ? nil : unchanged
    case .cancelled, .finished:
      abortPreparing(active, proxy: proxy, replayDelimiter: true)
      return processIdle(type, event)
    case .preparing:
      if (type == .flagsChanged || type == .keyDown), ExpansionEventBuffer.hasShortcutModifier(event),
         active.gate.cancelPreparation() {
        abortPreparing(active, proxy: proxy, replayDelimiter: true)
        return unchanged
      }
      if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown || type == .scrollWheel {
        if active.gate.cancelPreparation() {
          abortPreparing(active, proxy: proxy, replayDelimiter: true)
          matcher.reset()
          return unchanged
        }
      }
      return queuedEvents.append(event) ? nil : unchanged
    }
  }

  private func processIdle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    let unchanged = Unmanaged.passUnretained(event)
    guard policy.enabled, ContinuousClock.now < policy.validUntil,
          policy.keyboardLayoutIsActive,
          !policy.applicationIsActive,
          let identifier = policy.applicationIdentifier,
          let pid = policy.applicationPID,
          !policy.excludedApps.contains(identifier), allowsApplication(identifier) else {
      matcher.reset()
      return unchanged
    }
    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown || type == .scrollWheel {
      matcher.reset()
      lastApplicationPID = nil
      return unchanged
    }
    guard type == .keyDown else { return unchanged }
    if ExpansionEventBuffer.hasShortcutModifier(event) {
      matcher.reset()
      return unchanged
    }
    if lastApplicationPID != pid || Date.now.timeIntervalSince(lastInputAt) > 10 { matcher.reset() }
    lastApplicationPID = pid
    lastInputAt = .now
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    if code == 51 { matcher.backspace(); return unchanged }
    if [36, 48, 53, 76, 117, 123, 124, 125, 126].contains(code) { matcher.reset(); return unchanged }
    guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
      matcher.reset()
      return unchanged
    }
    var characters = [UniChar](repeating: 0, count: 32)
    var length = 0
    event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &length,
                                   unicodeString: &characters)
    guard length > 0 else { matcher.reset(); return unchanged }
    let text = String(utf16CodeUnits: characters, count: length)
    guard let match = matcher.append(text, snippets: policy.snippets) else { return unchanged }
    guard candidateDeliveryToken == nil else { matcher.reset(); return unchanged }

    let delimiter = match.snippet.waitsForSpace ? event.copy() : nil
    if match.snippet.waitsForSpace, delimiter == nil { return unchanged }
    nextToken &+= 1
    let candidate = ExpansionCandidate(token: nextToken, generation: generation, applicationPID: pid,
                                       applicationIdentifier: identifier, match: match,
                                       gate: ExpansionCommitGate(generation: generation, timeout: preparationTimeout))
    candidateDeliveryToken = candidate.token
    if match.snippet.waitsForSpace {
      queuedEvents.holdKeyDown(code)
    }
    activeTransaction = ActiveTransaction(token: candidate.token, generation: candidate.generation,
                                          gate: candidate.gate, delimiter: delimiter)
    schedulePreparationTimeout(candidate.token, gate: candidate.gate)
    Task { @MainActor [candidateHandler] in await candidateHandler(candidate) }
    return delimiter == nil ? unchanged : nil
  }

  private func allowsApplication(_ identifier: String) -> Bool {
    let listed = policy.ignoredApps.contains(identifier)
    return policy.ignoreAllAppsExceptListed ? listed : !listed
  }

  private func schedulePreparationTimeout(_ token: UInt64, gate: ExpansionCommitGate) {
    cancelPreparationTimer()
    guard let runLoop = tapRunLoop else { return }
    let components = preparationTimeout.components
    let seconds = Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
    let fireDate = CFAbsoluteTimeGetCurrent() + seconds
    let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, fireDate, 0, 0, 0) { [weak self] timer in
      autoreleasepool {
        guard let self,
              let active = self.activeTransaction,
              active.token == token else { return }
        if gate.expire() {
          self.abortPreparing(active, proxy: nil, replayDelimiter: true)
          self.preparationTimerObserver(token, .cancelled)
        } else {
          switch gate.phase() {
          case .preparing:
            CFRunLoopTimerSetNextFireDate(timer, CFAbsoluteTimeGetCurrent() + 0.01)
          case .cancelled:
            self.abortPreparing(active, proxy: nil, replayDelimiter: true)
            self.preparationTimerObserver(token, .cancelled)
          case .committed, .finished:
            self.cancelPreparationTimer()
            self.preparationTimerObserver(token, gate.phase())
          }
        }
      }
    }
    preparationTimer = timer
    CFRunLoopAddTimer(runLoop, timer, .commonModes)
  }

  private func abortPreparing(_ active: ActiveTransaction, proxy: CGEventTapProxy?, replayDelimiter: Bool) {
    guard activeTransaction?.token == active.token,
          active.gate.phase() != .committed else { return }
    cancelPreparationTimer()
    if replayDelimiter, let delimiter = active.delimiter { post(delimiter, proxy: proxy) }
    flushQueuedEvents(proxy: proxy)
    activeTransaction = nil
    matcher.reset()
    if stopAfterTransaction { detachTap(); stopAfterTransaction = false }
  }

  private func cancelPreparationTimer() {
    if let preparationTimer {
      CFRunLoopTimerInvalidate(preparationTimer)
      self.preparationTimer = nil
    }
  }

  private func flushQueuedEvents(proxy: CGEventTapProxy?) {
    queuedEvents.drain().forEach { post($0, proxy: proxy) }
  }

  private func post(_ event: CGEvent, proxy: CGEventTapProxy?) {
    guard let copy = event.copy() else { return }
    copy.setIntegerValueField(.eventSourceUserData, value: Self.eventTag)
    eventPoster(proxy, copy)
  }

  private func attach(source: CFRunLoopSource, tap: CFMachPort?) {
    guard let runLoop = tapRunLoop else { return }
    if let current = self.source { CFRunLoopRemoveSource(runLoop, current, .commonModes) }
    if let currentTap = self.tap, currentTap !== tap { CFMachPortInvalidate(currentTap) }
    self.tap = tap
    self.source = source
    CFRunLoopAddSource(runLoop, source, .commonModes)
    stopAfterTransaction = false
  }

  private func detachTap() {
    guard let runLoop = tapRunLoop else { return }
    if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
    if let tap { CFMachPortInvalidate(tap) }
    source = nil
    tap = nil
  }

  private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, context in
    guard let context else { return Unmanaged.passUnretained(event) }
    return autoreleasepool {
      Unmanaged<ExpansionEventTapRuntime>.fromOpaque(context).takeUnretainedValue().process(proxy, type, event)
    }
  }

  private func ensureTapRunLoop() async {
    if currentTapRunLoop != nil { return }
    await withCheckedContinuation { continuation in
      runLoopLock.lock()
      if tapRunLoop != nil {
        runLoopLock.unlock()
        continuation.resume()
        return
      }
      runLoopReadyWaiters.append(continuation)
      guard !runLoopStarting else { runLoopLock.unlock(); return }
      runLoopStarting = true
      runLoopLock.unlock()

      let thread = Thread { [weak self] in self?.runTapRunLoop() }
      thread.name = "Clipp expansion event tap"
      thread.qualityOfService = .userInteractive
      thread.start()
    }
  }

  private func runTapRunLoop() {
    let runLoop = CFRunLoopGetCurrent()
    var context = CFRunLoopSourceContext(version: 0, info: nil, retain: nil, release: nil,
                                         copyDescription: nil, equal: nil, hash: nil, schedule: nil,
                                         cancel: nil, perform: { _ in })
    guard let keepAlive = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context) else {
      runLoopLock.lock()
      let waiters = runLoopReadyWaiters
      runLoopReadyWaiters.removeAll()
      runLoopStarting = false
      runLoopLock.unlock()
      waiters.forEach { $0.resume() }
      return
    }
    CFRunLoopAddSource(runLoop, keepAlive, .commonModes)

    runLoopLock.lock()
    tapRunLoop = runLoop
    keepAliveSource = keepAlive
    tapThreadID = pthread_self()
    runLoopStarting = false
    let waiters = runLoopReadyWaiters
    runLoopReadyWaiters.removeAll()
    runLoopLock.unlock()
    waiters.forEach { $0.resume() }
    CFRunLoopRun()
  }

  private var currentTapRunLoop: CFRunLoop? {
    runLoopLock.lock()
    defer { runLoopLock.unlock() }
    return tapRunLoop
  }

  private var isTapThread: Bool {
    runLoopLock.lock()
    let threadID = tapThreadID
    runLoopLock.unlock()
    guard let threadID else { return false }
    return pthread_equal(threadID, pthread_self()) != 0
  }

  private func runOnTapRunLoop<T>(_ action: @escaping () -> T) async -> T {
    if isTapThread { return action() }
    guard let runLoop = currentTapRunLoop else { return action() }
    return await withCheckedContinuation { continuation in
      CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
        autoreleasepool { continuation.resume(returning: action()) }
      }
      CFRunLoopWakeUp(runLoop)
    }
  }
}

struct ExpansionEventBuffer {
  private var events: [CGEvent] = []
  private var heldKeys: Set<Int64> = []
  private var hasQueuedShortcut = false

  static func hasShortcutModifier(_ event: CGEvent) -> Bool {
    !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty
  }

  mutating func holdKeyDown(_ code: Int64) { heldKeys.insert(code) }

  mutating func append(_ event: CGEvent) -> Bool {
    let code = event.getIntegerValueField(.keyboardEventKeycode)
    switch event.type {
    case .flagsChanged:
      guard hasQueuedShortcut else { return false }
    case .keyUp:
      guard heldKeys.contains(code) else { return false }
    case .keyDown:
      if event.getIntegerValueField(.keyboardEventAutorepeat) != 0, !heldKeys.contains(code) { return false }
    default:
      break
    }
    guard let copy = event.copy() else { return false }
    if event.type == .keyDown { heldKeys.insert(code) }
    if event.type == .keyUp { heldKeys.remove(code) }
    if event.type == .keyDown, Self.hasShortcutModifier(event) { hasQueuedShortcut = true }
    events.append(copy)
    return true
  }

  mutating func drain() -> [CGEvent] {
    defer { events.removeAll(); heldKeys.removeAll(); hasQueuedShortcut = false }
    return events
  }
}
