#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation

public enum DesktopUpdateStatus: String, Equatable, Sendable {
  case disabled
  case idle
  case checking
  case upToDate = "up-to-date"
  case available
  case downloading
  case downloaded
  case error
}

public enum DesktopUpdateErrorContext: String, Equatable, Sendable {
  case check
  case download
  case install
}

public struct DesktopUpdateEnvironment: Equatable, Sendable {
  public let isDevelopment: Bool
  public let isPackaged: Bool
  public let platformIdentifier: String
  public let appImagePath: String?
  public let disabledByEnvironment: Bool

  public init(
    isDevelopment: Bool,
    isPackaged: Bool,
    platformIdentifier: String,
    appImagePath: String?,
    disabledByEnvironment: Bool
  ) {
    self.isDevelopment = isDevelopment
    self.isPackaged = isPackaged
    self.platformIdentifier = platformIdentifier
    self.appImagePath = appImagePath
    self.disabledByEnvironment = disabledByEnvironment
  }
}

public struct DesktopUpdateState: Equatable, Sendable {
  public let enabled: Bool
  public let status: DesktopUpdateStatus
  public let currentVersion: String
  public let hostArch: DesktopRuntimeArch
  public let appArch: DesktopRuntimeArch
  public let runningUnderArm64Translation: Bool
  public let availableVersion: String?
  public let downloadedVersion: String?
  public let downloadPercent: Double?
  public let checkedAt: String?
  public let message: String?
  public let errorContext: DesktopUpdateErrorContext?
  public let canRetry: Bool

  public init(
    enabled: Bool,
    status: DesktopUpdateStatus,
    currentVersion: String,
    hostArch: DesktopRuntimeArch,
    appArch: DesktopRuntimeArch,
    runningUnderArm64Translation: Bool,
    availableVersion: String?,
    downloadedVersion: String?,
    downloadPercent: Double?,
    checkedAt: String?,
    message: String?,
    errorContext: DesktopUpdateErrorContext?,
    canRetry: Bool
  ) {
    self.enabled = enabled
    self.status = status
    self.currentVersion = currentVersion
    self.hostArch = hostArch
    self.appArch = appArch
    self.runningUnderArm64Translation = runningUnderArm64Translation
    self.availableVersion = availableVersion
    self.downloadedVersion = downloadedVersion
    self.downloadPercent = downloadPercent
    self.checkedAt = checkedAt
    self.message = message
    self.errorContext = errorContext
    self.canRetry = canRetry
  }
}

public struct DesktopUpdateActionResult: Equatable, Sendable {
  public let accepted: Bool
  public let completed: Bool
  public let state: DesktopUpdateState

  public init(accepted: Bool, completed: Bool, state: DesktopUpdateState) {
    self.accepted = accepted
    self.completed = completed
    self.state = state
  }
}

public enum DesktopUpdateCheckResult: Equatable, Sendable {
  case noUpdate
  case updateAvailable(version: String)
}

public struct DesktopUpdateDownloadResult: Equatable, Sendable {
  public let version: String

  public init(version: String) {
    self.version = version
  }
}

public protocol DesktopUpdaterClient: Sendable {
  func checkForUpdates() async throws -> DesktopUpdateCheckResult
  func downloadUpdate(progress: @escaping @Sendable (Double) -> Void) async throws -> DesktopUpdateDownloadResult
  func installUpdate() async throws
}

public struct DesktopUpdateControllerConfiguration: Sendable {
  public let currentVersion: String
  public let runtimeInfo: DesktopRuntimeInfo
  public let environment: DesktopUpdateEnvironment
  public let startupDelay: Duration
  public let pollInterval: Duration
  public let now: @Sendable () -> Date

  public init(
    currentVersion: String,
    runtimeInfo: DesktopRuntimeInfo,
    environment: DesktopUpdateEnvironment,
    startupDelay: Duration = .seconds(15),
    pollInterval: Duration = .seconds(4 * 60 * 60),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.currentVersion = currentVersion
    self.runtimeInfo = runtimeInfo
    self.environment = environment
    self.startupDelay = startupDelay
    self.pollInterval = pollInterval
    self.now = now
  }
}

public enum DesktopUpdatePolicy {
  public static func disabledReason(for environment: DesktopUpdateEnvironment) -> String? {
    if environment.isDevelopment || environment.isPackaged == false {
      return "Automatic updates are only available in packaged production builds."
    }
    if environment.disabledByEnvironment {
      return "Automatic updates are disabled by the T3CODE_DISABLE_AUTO_UPDATE setting."
    }
    if environment.platformIdentifier == "linux",
      (environment.appImagePath?.isEmpty ?? true)
    {
      return "Automatic updates on Linux require running the AppImage build."
    }
    return nil
  }

  public static func shouldBroadcastDownloadProgress(
    currentState: DesktopUpdateState,
    nextPercent: Double
  ) -> Bool {
    guard currentState.status == .downloading else {
      return true
    }
    guard let currentPercent = currentState.downloadPercent else {
      return true
    }

    let previousStep = Int(currentPercent / 10)
    let nextStep = Int(nextPercent / 10)
    return previousStep != nextStep || nextPercent >= 100
  }
}

public enum DesktopUpdateStateMachine {
  public static func initialState(
    currentVersion: String,
    runtimeInfo: DesktopRuntimeInfo
  ) -> DesktopUpdateState {
    DesktopUpdateState(
      enabled: false,
      status: .disabled,
      currentVersion: currentVersion,
      hostArch: runtimeInfo.hostArch,
      appArch: runtimeInfo.appArch,
      runningUnderArm64Translation: runtimeInfo.runningUnderArm64Translation,
      availableVersion: nil,
      downloadedVersion: nil,
      downloadPercent: nil,
      checkedAt: nil,
      message: nil,
      errorContext: nil,
      canRetry: false
    )
  }

  public static func configuredState(
    currentVersion: String,
    runtimeInfo: DesktopRuntimeInfo,
    enabled: Bool
  ) -> DesktopUpdateState {
    let initial = initialState(currentVersion: currentVersion, runtimeInfo: runtimeInfo)
    return DesktopUpdateState(
      enabled: enabled,
      status: enabled ? .idle : .disabled,
      currentVersion: initial.currentVersion,
      hostArch: initial.hostArch,
      appArch: initial.appArch,
      runningUnderArm64Translation: initial.runningUnderArm64Translation,
      availableVersion: nil,
      downloadedVersion: nil,
      downloadPercent: nil,
      checkedAt: nil,
      message: nil,
      errorContext: nil,
      canRetry: false
    )
  }

  public static func reduceOnCheckStart(_ state: DesktopUpdateState, checkedAt: String) -> DesktopUpdateState {
    copy(
      state,
      status: .checking,
      downloadPercent: nil,
      checkedAt: checkedAt,
      message: nil,
      errorContext: nil,
      canRetry: false
    )
  }

  public static func reduceOnCheckFailure(
    _ state: DesktopUpdateState,
    message: String,
    checkedAt: String
  ) -> DesktopUpdateState {
    copy(
      state,
      status: .error,
      downloadPercent: nil,
      checkedAt: checkedAt,
      message: message,
      errorContext: .check,
      canRetry: true
    )
  }

  public static func reduceOnUpdateAvailable(
    _ state: DesktopUpdateState,
    version: String,
    checkedAt: String
  ) -> DesktopUpdateState {
    copy(
      state,
      status: .available,
      availableVersion: version,
      downloadedVersion: nil,
      downloadPercent: nil,
      checkedAt: checkedAt,
      message: nil,
      errorContext: nil,
      canRetry: false
    )
  }

  public static func reduceOnNoUpdate(_ state: DesktopUpdateState, checkedAt: String) -> DesktopUpdateState {
    copy(
      state,
      status: .upToDate,
      availableVersion: nil,
      downloadedVersion: nil,
      downloadPercent: nil,
      checkedAt: checkedAt,
      message: nil,
      errorContext: nil,
      canRetry: false
    )
  }

  public static func reduceOnDownloadStart(_ state: DesktopUpdateState) -> DesktopUpdateState {
    copy(
      state,
      status: .downloading,
      downloadPercent: 0,
      message: nil,
      errorContext: nil,
      canRetry: false
    )
  }

  public static func reduceOnDownloadProgress(
    _ state: DesktopUpdateState,
    percent: Double
  ) -> DesktopUpdateState {
    copy(
      state,
      status: .downloading,
      downloadPercent: percent,
      message: nil,
      errorContext: nil,
      canRetry: false
    )
  }

  public static func reduceOnDownloadFailure(
    _ state: DesktopUpdateState,
    message: String
  ) -> DesktopUpdateState {
    copy(
      state,
      status: state.availableVersion == nil ? .error : .available,
      downloadPercent: nil,
      message: message,
      errorContext: .download,
      canRetry: state.availableVersion != nil
    )
  }

  public static func reduceOnDownloadComplete(
    _ state: DesktopUpdateState,
    version: String
  ) -> DesktopUpdateState {
    copy(
      state,
      status: .downloaded,
      availableVersion: version,
      downloadedVersion: version,
      downloadPercent: 100,
      message: nil,
      errorContext: nil,
      canRetry: true
    )
  }

  public static func reduceOnInstallFailure(
    _ state: DesktopUpdateState,
    message: String
  ) -> DesktopUpdateState {
    copy(
      state,
      status: .downloaded,
      message: message,
      errorContext: .install,
      canRetry: true
    )
  }

  private static func copy(
    _ state: DesktopUpdateState,
    enabled: Bool? = nil,
    status: DesktopUpdateStatus? = nil,
    availableVersion: String?? = nil,
    downloadedVersion: String?? = nil,
    downloadPercent: Double?? = nil,
    checkedAt: String?? = nil,
    message: String?? = nil,
    errorContext: DesktopUpdateErrorContext?? = nil,
    canRetry: Bool? = nil
  ) -> DesktopUpdateState {
    DesktopUpdateState(
      enabled: enabled ?? state.enabled,
      status: status ?? state.status,
      currentVersion: state.currentVersion,
      hostArch: state.hostArch,
      appArch: state.appArch,
      runningUnderArm64Translation: state.runningUnderArm64Translation,
      availableVersion: availableVersion ?? state.availableVersion,
      downloadedVersion: downloadedVersion ?? state.downloadedVersion,
      downloadPercent: downloadPercent ?? state.downloadPercent,
      checkedAt: checkedAt ?? state.checkedAt,
      message: message ?? state.message,
      errorContext: errorContext ?? state.errorContext,
      canRetry: canRetry ?? state.canRetry
    )
  }
}

public actor DesktopUpdateController {
  public var onStateChanged: (@Sendable (DesktopUpdateState) -> Void)?

  private let configuration: DesktopUpdateControllerConfiguration
  private let updaterClient: DesktopUpdaterClient
  private var state: DesktopUpdateState
  private var pollTask: Task<Void, Never>?
  private var isChecking = false
  private var isDownloading = false
  private var isQuitting = false

  public init(
    configuration: DesktopUpdateControllerConfiguration,
    updaterClient: DesktopUpdaterClient
  ) {
    self.configuration = configuration
    self.updaterClient = updaterClient
    let enabled = DesktopUpdatePolicy.disabledReason(for: configuration.environment) == nil
    self.state = DesktopUpdateStateMachine.configuredState(
      currentVersion: configuration.currentVersion,
      runtimeInfo: configuration.runtimeInfo,
      enabled: enabled
    )
  }

  public func currentState() -> DesktopUpdateState {
    state
  }

  public func setOnStateChanged(_ handler: @escaping @Sendable (DesktopUpdateState) -> Void) {
    onStateChanged = handler
  }

  public func startPolling() {
    guard state.enabled else {
      emitStateChange()
      return
    }
    stopPolling()
    emitStateChange()
    pollTask = Task { [startupDelay = configuration.startupDelay, pollInterval = configuration.pollInterval] in
      try? await Task.sleep(for: startupDelay)
      guard Task.isCancelled == false else {
        return
      }
      await self.checkForUpdates(reason: "startup")

      while Task.isCancelled == false {
        try? await Task.sleep(for: pollInterval)
        guard Task.isCancelled == false else {
          return
        }
        await self.checkForUpdates(reason: "poll")
      }
    }
  }

  public func stopPolling() {
    pollTask?.cancel()
    pollTask = nil
  }

  public func checkForUpdates(reason _: String) async {
    guard state.enabled, isQuitting == false, isChecking == false else {
      return
    }
    guard state.status != .downloading, state.status != .downloaded else {
      return
    }

    isChecking = true
    state = DesktopUpdateStateMachine.reduceOnCheckStart(state, checkedAt: timestamp())
    emitStateChange()

    do {
      switch try await updaterClient.checkForUpdates() {
      case .noUpdate:
        state = DesktopUpdateStateMachine.reduceOnNoUpdate(state, checkedAt: timestamp())
      case .updateAvailable(let version):
        state = DesktopUpdateStateMachine.reduceOnUpdateAvailable(
          state,
          version: version,
          checkedAt: timestamp()
        )
      }
    } catch {
      state = DesktopUpdateStateMachine.reduceOnCheckFailure(
        state,
        message: error.localizedDescription,
        checkedAt: timestamp()
      )
    }

    isChecking = false
    emitStateChange()
  }

  public func downloadAvailableUpdate() async -> DesktopUpdateActionResult {
    guard state.enabled, isDownloading == false, state.status == .available else {
      return DesktopUpdateActionResult(accepted: false, completed: false, state: state)
    }

    isDownloading = true
    state = DesktopUpdateStateMachine.reduceOnDownloadStart(state)
    emitStateChange()

    do {
      let result = try await updaterClient.downloadUpdate { percent in
        Task {
          await self.recordDownloadProgress(percent)
        }
      }
      state = DesktopUpdateStateMachine.reduceOnDownloadComplete(state, version: result.version)
      isDownloading = false
      emitStateChange()
      return DesktopUpdateActionResult(accepted: true, completed: true, state: state)
    } catch {
      state = DesktopUpdateStateMachine.reduceOnDownloadFailure(state, message: error.localizedDescription)
      isDownloading = false
      emitStateChange()
      return DesktopUpdateActionResult(accepted: true, completed: false, state: state)
    }
  }

  public func installDownloadedUpdate(
    beforeInstall: (@Sendable () async throws -> Void)? = nil
  ) async -> DesktopUpdateActionResult {
    guard state.enabled, isQuitting == false, state.status == .downloaded else {
      return DesktopUpdateActionResult(accepted: false, completed: false, state: state)
    }

    isQuitting = true
    stopPolling()

    do {
      try await beforeInstall?()
      try await updaterClient.installUpdate()
      return DesktopUpdateActionResult(accepted: true, completed: true, state: state)
    } catch {
      isQuitting = false
      state = DesktopUpdateStateMachine.reduceOnInstallFailure(state, message: error.localizedDescription)
      emitStateChange()
      return DesktopUpdateActionResult(accepted: true, completed: false, state: state)
    }
  }

  private func recordDownloadProgress(_ percent: Double) {
    guard state.status == .downloading else {
      return
    }
    // Progress updates also clear any transient download error message once a retried
    // download starts making forward progress again, even if we have not crossed a
    // new 10% milestone yet.
    if DesktopUpdatePolicy.shouldBroadcastDownloadProgress(currentState: state, nextPercent: percent) || state.message != nil {
      state = DesktopUpdateStateMachine.reduceOnDownloadProgress(state, percent: percent)
      emitStateChange()
    }
  }

  private func emitStateChange() {
    onStateChanged?(state)
  }

  private func timestamp() -> String {
    configuration.now().ISO8601Format()
  }
}
