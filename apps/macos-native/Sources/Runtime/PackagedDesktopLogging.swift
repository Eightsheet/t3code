#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Dispatch
import Foundation

public struct PackagedDesktopLoggingOptions: Sendable {
  public let logDirectory: URL
  public let maxBytes: Int
  public let maxFiles: Int

  public init(logDirectory: URL, maxBytes: Int = 10 * 1024 * 1024, maxFiles: Int = 10) {
    self.logDirectory = logDirectory
    self.maxBytes = maxBytes
    self.maxFiles = maxFiles
  }
}

public final class PackagedDesktopLoggingSession: @unchecked Sendable {
  public let desktopLogSink: RotatingFileSink
  public let backendLogSink: RotatingFileSink

  private let stdioCapture: StandardIOCaptureController

  public init(
    options: PackagedDesktopLoggingOptions,
    fileManager: FileManager = .default
  ) throws {
    desktopLogSink = try RotatingFileSink(
      options: RotatingFileSinkOptions(
        fileURL: options.logDirectory.appendingPathComponent("desktop-main.log", isDirectory: false),
        maxBytes: options.maxBytes,
        maxFiles: options.maxFiles
      ),
      fileManager: fileManager
    )
    backendLogSink = try RotatingFileSink(
      options: RotatingFileSinkOptions(
        fileURL: options.logDirectory.appendingPathComponent("server-child.log", isDirectory: false),
        maxBytes: options.maxBytes,
        maxFiles: options.maxFiles
      ),
      fileManager: fileManager
    )
    stdioCapture = StandardIOCaptureController(sink: desktopLogSink)
  }

  public func start() throws {
    try stdioCapture.start()
    try desktopLogSink.write("[\(timestamp())] [desktop] runtime log capture enabled\n")
  }

  public func stop() {
    stdioCapture.stop()
  }

  private func timestamp() -> String {
    Date().ISO8601Format()
  }
}

public final class StandardIOCaptureController: @unchecked Sendable {
  private let sink: RotatingFileSink
  private let lock = NSLock()
  private var originalStdout: Int32 = -1
  private var originalStderr: Int32 = -1
  private var stdoutReadHandle: FileHandle?
  private var stderrReadHandle: FileHandle?
  private var isCapturing = false

  public init(sink: RotatingFileSink) {
    self.sink = sink
  }

  deinit {
    stop()
  }

  public func start() throws {
    try lock.withLock {
      guard isCapturing == false else {
        return
      }
      originalStdout = dup(STDOUT_FILENO)
      originalStderr = dup(STDERR_FILENO)
      guard originalStdout >= 0, originalStderr >= 0 else {
        throw POSIXError(.EBADF)
      }

      stdoutReadHandle = try redirect(stream: STDOUT_FILENO, label: "stdout")
      stderrReadHandle = try redirect(stream: STDERR_FILENO, label: "stderr")
      isCapturing = true
    }
  }

  public func stop() {
    lock.withLock {
      guard isCapturing else {
        return
      }

      fflush(nil)

      if originalStdout >= 0 {
        _ = dup2(originalStdout, STDOUT_FILENO)
        close(originalStdout)
        originalStdout = -1
      }
      if originalStderr >= 0 {
        _ = dup2(originalStderr, STDERR_FILENO)
        close(originalStderr)
        originalStderr = -1
      }

      stdoutReadHandle?.readabilityHandler = nil
      stderrReadHandle?.readabilityHandler = nil
      try? stdoutReadHandle?.close()
      try? stderrReadHandle?.close()
      stdoutReadHandle = nil
      stderrReadHandle = nil
      isCapturing = false
    }
  }

  private func redirect(stream: Int32, label: String) throws -> FileHandle {
    let pipe = Pipe()
    let writeDescriptor = pipe.fileHandleForWriting.fileDescriptor
    guard dup2(writeDescriptor, stream) >= 0 else {
      throw POSIXError(.EBADF)
    }
    try pipe.fileHandleForWriting.close()

    let readHandle = pipe.fileHandleForReading
    readHandle.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard data.isEmpty == false else {
        handle.readabilityHandler = nil
        return
      }
      self?.writeCapturedChunk(label: label, data: data)
    }
    return readHandle
  }

  private func writeCapturedChunk(label: String, data: Data) {
    var payload = Data("[\(Date().ISO8601Format())] [\(label)] ".utf8)
    payload.append(data)
    if data.last != 0x0a {
      payload.append(Data("\n".utf8))
    }
    try? sink.write(payload)
  }
}
