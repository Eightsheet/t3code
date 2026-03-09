#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation

public enum BackendProcessControllerError: Error, Equatable {
  case alreadyRunning
  case missingBackendEntry(String)
}

public final class BackendProcessController: @unchecked Sendable {
  public var onExit: (@Sendable (Int32) -> Void)? {
    get { stateLock.withLock { exitHandler } }
    set { stateLock.withLock { exitHandler = newValue } }
  }
  public var process: Process? {
    stateLock.withLock { currentProcess }
  }
  public var restartAttempt: Int {
    stateLock.withLock { currentRestartAttempt }
  }

  private let fileManager: FileManager
  private let desktopLogSink: RotatingFileSink?
  private let backendLogSink: RotatingFileSink?
  private let stateLock = NSLock()
  private var exitHandler: (@Sendable (Int32) -> Void)?
  private var currentProcess: Process?
  private var currentRestartAttempt = 0

  public init(
    fileManager: FileManager = .default,
    desktopLogSink: RotatingFileSink? = nil,
    backendLogSink: RotatingFileSink? = nil
  ) {
    self.fileManager = fileManager
    self.desktopLogSink = desktopLogSink
    self.backendLogSink = backendLogSink
  }

  public func start(configuration: DesktopRuntimeConfiguration) throws {
    if stateLock.withLock({ currentProcess?.isRunning == true }) {
      throw BackendProcessControllerError.alreadyRunning
    }

    guard fileManager.fileExists(atPath: configuration.paths.backendEntry.path) else {
      throw BackendProcessControllerError.missingBackendEntry(configuration.paths.backendEntry.path)
    }

    let process = Process()
    process.executableURL = configuration.executableURL
    process.arguments = configuration.arguments
    process.currentDirectoryURL = configuration.paths.backendWorkingDirectory
    process.environment = configuration.environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    installOutputCapture(for: stdoutPipe, streamName: "stdout")
    installOutputCapture(for: stderrPipe, streamName: "stderr")

    process.terminationHandler = { [weak self] process in
      self?.logBackendBoundary(
        phase: "END",
        details: "pid=\(process.processIdentifier) status=\(process.terminationStatus)"
      )
      let onExit = self?.stateLock.withLock { () -> ((Int32) -> Void)? in
        self?.currentProcess = nil
        self?.currentRestartAttempt += 1
        return self?.exitHandler
      }
      onExit?(process.terminationStatus)
    }

    try process.run()
    stateLock.withLock {
      currentProcess = process
      currentRestartAttempt = 0
    }

    logDesktop("backend launch requested path=\(configuration.paths.backendEntry.path)")
    logBackendBoundary(
      phase: "START",
      details:
        "pid=\(process.processIdentifier) port=\(configuration.port) cwd=\(configuration.paths.backendWorkingDirectory.path)"
    )
  }

  public func stop(gracePeriod: TimeInterval = 2.0) {
    guard let process = stateLock.withLock({ currentProcess }) else {
      return
    }

    if process.isRunning {
      process.terminate()
    }

    let deadline = Date().addingTimeInterval(gracePeriod)
    while process.isRunning && Date() < deadline {
      _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }

    if process.isRunning {
      forceKill(pid: process.processIdentifier)
    }
  }

  public static func restartDelay(forAttempt attempt: Int) -> TimeInterval {
    guard attempt > 0 else {
      return 0
    }
    return min(pow(2, Double(attempt - 1)) * 0.5, 10)
  }

  private func installOutputCapture(for pipe: Pipe, streamName: String) {
    pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard data.isEmpty == false else {
        handle.readabilityHandler = nil
        return
      }
      self?.logBackendStream(streamName: streamName, data: data)
    }
  }

  private func logDesktop(_ message: String) {
    let line = "[\(timestamp())] [desktop] \(message)\n"
    try? desktopLogSink?.write(line)
  }

  private func logBackendBoundary(phase: String, details: String) {
    let line = "[\(timestamp())] ---- APP SESSION \(phase) \(details) ----\n"
    try? backendLogSink?.write(line)
  }

  private func logBackendStream(streamName: String, data: Data) {
    var chunk = Data("[\(timestamp())] [\(streamName)] ".utf8)
    chunk.append(data)
    if data.last != 0x0a {
      chunk.append(Data("\n".utf8))
    }
    try? backendLogSink?.write(chunk)
  }

  private func timestamp() -> String {
    Date().ISO8601Format()
  }

  private func forceKill(pid: Int32) {
#if canImport(Darwin)
    _ = Darwin.kill(pid, SIGKILL)
#else
    _ = Glibc.kill(pid, SIGKILL)
#endif
  }
}
