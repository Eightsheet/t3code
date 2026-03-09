import Foundation

public enum DesktopRuntimeLifecycle: String, Equatable, Sendable {
  case idle
  case starting
  case running
  case restarting
  case stopping
  case stopped
  case failed
}

public struct DesktopRuntimeSessionSnapshot: Equatable, Sendable {
  public let lifecycle: DesktopRuntimeLifecycle
  public let message: String?
  public let restartAttempt: Int
  public let websocketURL: URL?
  public let backendEntry: URL?
  public let updateState: DesktopUpdateState?

  public init(
    lifecycle: DesktopRuntimeLifecycle,
    message: String?,
    restartAttempt: Int,
    websocketURL: URL?,
    backendEntry: URL?,
    updateState: DesktopUpdateState?
  ) {
    self.lifecycle = lifecycle
    self.message = message
    self.restartAttempt = restartAttempt
    self.websocketURL = websocketURL
    self.backendEntry = backendEntry
    self.updateState = updateState
  }
}

public struct DesktopRuntimeSessionOptions: Sendable {
  public let environment: [String: String]
  public let currentVersion: String
  public let runtimeInfo: DesktopRuntimeInfo
  public let updateEnvironment: DesktopUpdateEnvironment
  public let currentDirectoryURL: URL
  public let shouldEnablePackagedLogging: Bool

  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    currentVersion: String,
    runtimeInfo: DesktopRuntimeInfo,
    updateEnvironment: DesktopUpdateEnvironment,
    currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true),
    shouldEnablePackagedLogging: Bool = false
  ) {
    self.environment = environment
    self.currentVersion = currentVersion
    self.runtimeInfo = runtimeInfo
    self.updateEnvironment = updateEnvironment
    self.currentDirectoryURL = currentDirectoryURL
    self.shouldEnablePackagedLogging = shouldEnablePackagedLogging
  }
}

public actor DesktopRuntimeSession {
  public var onStateChanged: (@Sendable (DesktopRuntimeSessionSnapshot) -> Void)?

  private let options: DesktopRuntimeSessionOptions
  private let configurationLoader: @Sendable () throws -> DesktopRuntimeConfiguration
  private let backendController: BackendProcessController
  private let updateController: DesktopUpdateController?
  private let loggingSessionFactory: @Sendable (DesktopRuntimeConfiguration) throws -> PackagedDesktopLoggingSession?
  private let restartDelayProvider: @Sendable (Int) -> TimeInterval

  private var snapshot: DesktopRuntimeSessionSnapshot
  private var configuration: DesktopRuntimeConfiguration?
  private var loggingSession: PackagedDesktopLoggingSession?
  private var restartTask: Task<Void, Never>?
  private var isStopping = false
  private var lastRestartAttempt = 0

  public init(
    options: DesktopRuntimeSessionOptions,
    configurationLoader: @escaping @Sendable () throws -> DesktopRuntimeConfiguration,
    backendController: BackendProcessController = BackendProcessController(),
    updateController: DesktopUpdateController? = nil,
    loggingSessionFactory: @escaping @Sendable (DesktopRuntimeConfiguration) throws -> PackagedDesktopLoggingSession? = { _ in nil },
    restartDelayProvider: @escaping @Sendable (Int) -> TimeInterval = BackendProcessController.restartDelay(forAttempt:)
  ) {
    self.options = options
    self.configurationLoader = configurationLoader
    self.backendController = backendController
    self.updateController = updateController
    self.loggingSessionFactory = loggingSessionFactory
    self.restartDelayProvider = restartDelayProvider
    self.snapshot = DesktopRuntimeSessionSnapshot(
      lifecycle: .idle,
      message: nil,
      restartAttempt: 0,
      websocketURL: nil,
      backendEntry: nil,
      updateState: nil
    )
  }

  public init(options: DesktopRuntimeSessionOptions) {
    let updateController = GitHubReleaseUpdaterClient(
      currentVersion: options.currentVersion,
      runtimeInfo: options.runtimeInfo,
      environment: options.environment,
      appRoot: DesktopRuntimePathResolver.resolve(
        environment: options.environment,
        currentDirectoryURL: options.currentDirectoryURL
      ).appRoot
    ).map {
      DesktopUpdateController(
        configuration: DesktopUpdateControllerConfiguration(
          currentVersion: options.currentVersion,
          runtimeInfo: options.runtimeInfo,
          environment: options.updateEnvironment
        ),
        updaterClient: $0
      )
    }

    self.options = options
    self.configurationLoader = {
      try DesktopRuntimeBootstrapper.prepare(
        environment: options.environment,
        currentDirectoryURL: options.currentDirectoryURL
      )
    }
    self.backendController = BackendProcessController()
    self.updateController = updateController
    self.loggingSessionFactory = { configuration in
      guard options.shouldEnablePackagedLogging else {
        return nil
      }
      return try PackagedDesktopLoggingSession(
        options: PackagedDesktopLoggingOptions(logDirectory: configuration.paths.logDirectory)
      )
    }
    self.restartDelayProvider = BackendProcessController.restartDelay(forAttempt:)
    self.snapshot = DesktopRuntimeSessionSnapshot(
      lifecycle: .idle,
      message: nil,
      restartAttempt: 0,
      websocketURL: nil,
      backendEntry: nil,
      updateState: nil
    )
  }

  public func currentSnapshot() -> DesktopRuntimeSessionSnapshot {
    snapshot
  }

  public func setOnStateChanged(_ handler: @escaping @Sendable (DesktopRuntimeSessionSnapshot) -> Void) {
    onStateChanged = handler
  }

  public func start() async {
    guard snapshot.lifecycle != .running, snapshot.lifecycle != .starting else {
      return
    }
    isStopping = false
    if snapshot.lifecycle != .restarting {
      lastRestartAttempt = 0
    }
    transition(to: .starting, message: nil)

    do {
      let configuration = try configurationLoader()
      self.configuration = configuration
      loggingSession = try loggingSessionFactory(configuration)
      try loggingSession?.start()

      backendController.onExit = { [weak self] status in
        Task {
          await self?.handleBackendExit(status)
        }
      }
      try backendController.start(configuration: configuration)

      if let updateController {
        await updateController.setOnStateChanged { [weak self] state in
          Task {
            await self?.updateSnapshot(updateState: state)
          }
        }
        await updateController.startPolling()
        let state = await updateController.currentState()
        snapshot = DesktopRuntimeSessionSnapshot(
          lifecycle: .running,
          message: nil,
          restartAttempt: lastRestartAttempt,
          websocketURL: configuration.websocketURL,
          backendEntry: configuration.paths.backendEntry,
          updateState: state
        )
      } else {
        snapshot = DesktopRuntimeSessionSnapshot(
          lifecycle: .running,
          message: nil,
          restartAttempt: lastRestartAttempt,
          websocketURL: configuration.websocketURL,
          backendEntry: configuration.paths.backendEntry,
          updateState: nil
        )
      }
      emitStateChange()
    } catch {
      transition(to: .failed, message: error.localizedDescription)
    }
  }

  public func stop() async {
    isStopping = true
    restartTask?.cancel()
    restartTask = nil
    transition(to: .stopping, message: nil)
    if let updateController {
      await updateController.stopPolling()
    }
    backendController.stop()
    loggingSession?.stop()
    transition(to: .stopped, message: nil)
  }

  private func handleBackendExit(_ status: Int32) async {
    guard isStopping == false, let configuration else {
      return
    }
    let attempt = backendController.restartAttempt
    lastRestartAttempt = attempt
    let delay = restartDelayProvider(attempt)
    snapshot = DesktopRuntimeSessionSnapshot(
      lifecycle: .restarting,
      message: "Backend exited with status \(status). Restarting in \(String(format: "%.1f", delay))s.",
      restartAttempt: attempt,
      websocketURL: configuration.websocketURL,
      backendEntry: configuration.paths.backendEntry,
      updateState: snapshot.updateState
    )
    emitStateChange()

    restartTask?.cancel()
    restartTask = Task { [weak self] in
      guard delay > 0 else {
        await self?.restartBackendIfNeeded()
        return
      }
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      await self?.restartBackendIfNeeded()
    }
  }

  private func restartBackendIfNeeded() async {
    guard isStopping == false, let configuration else {
      return
    }
    do {
      try backendController.start(configuration: configuration)
      snapshot = DesktopRuntimeSessionSnapshot(
        lifecycle: .running,
        message: "Backend restarted successfully.",
        restartAttempt: lastRestartAttempt,
        websocketURL: configuration.websocketURL,
        backendEntry: configuration.paths.backendEntry,
        updateState: snapshot.updateState
      )
      emitStateChange()
    } catch {
      transition(to: .failed, message: error.localizedDescription)
    }
  }

  private func updateSnapshot(updateState: DesktopUpdateState) {
    snapshot = DesktopRuntimeSessionSnapshot(
      lifecycle: snapshot.lifecycle,
      message: snapshot.message,
      restartAttempt: snapshot.restartAttempt,
      websocketURL: snapshot.websocketURL,
      backendEntry: snapshot.backendEntry,
      updateState: updateState
    )
    emitStateChange()
  }

  private func transition(to lifecycle: DesktopRuntimeLifecycle, message: String?) {
    snapshot = DesktopRuntimeSessionSnapshot(
      lifecycle: lifecycle,
      message: message,
      restartAttempt: snapshot.restartAttempt,
      websocketURL: configuration?.websocketURL,
      backendEntry: configuration?.paths.backendEntry,
      updateState: snapshot.updateState
    )
    emitStateChange()
  }

  private func emitStateChange() {
    onStateChanged?(snapshot)
  }
}
