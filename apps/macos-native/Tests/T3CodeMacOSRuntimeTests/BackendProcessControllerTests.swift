import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class BackendProcessControllerTests: XCTestCase {
  func testStartLaunchesProcessAndWritesLaunchLogs() throws {
    let directory = makeTemporaryDirectory()
    let scriptURL = directory.appendingPathComponent("backend.sh", isDirectory: false)
    try "#!/bin/sh\nprintf 'ready from swift runtime\\n'\n".write(
      to: scriptURL,
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: scriptURL.path
    )

    let backendLogURL = directory.appendingPathComponent("backend.log", isDirectory: false)
    let desktopLogURL = directory.appendingPathComponent("desktop.log", isDirectory: false)
    let controller = BackendProcessController(
      desktopLogSink: try RotatingFileSink(
        options: RotatingFileSinkOptions(fileURL: desktopLogURL, maxBytes: 1_024, maxFiles: 2)
      ),
      backendLogSink: try RotatingFileSink(
        options: RotatingFileSinkOptions(fileURL: backendLogURL, maxBytes: 1_024, maxFiles: 2)
      )
    )

    let exitExpectation = expectation(description: "process exits")
    controller.onExit = { _ in
      exitExpectation.fulfill()
    }

    let configuration = DesktopRuntimeConfiguration(
      paths: DesktopRuntimePaths(
        appRoot: directory,
        backendEntry: scriptURL,
        backendWorkingDirectory: directory,
        stateDirectory: directory,
        logDirectory: directory
      ),
      executableURL: URL(fileURLWithPath: "/bin/sh", isDirectory: false),
      arguments: [scriptURL.path],
      environment: [:],
      authToken: "token",
      port: 4321,
      websocketURL: URL(string: "ws://127.0.0.1:4321/?token=token")!,
      inheritedPath: nil
    )

    try controller.start(configuration: configuration)
    wait(for: [exitExpectation], timeout: 2)

    let desktopLog = try String(contentsOf: desktopLogURL, encoding: .utf8)
    let backendLog = try String(contentsOf: backendLogURL, encoding: .utf8)
    XCTAssertTrue(desktopLog.contains("backend launch requested"))
    XCTAssertTrue(backendLog.contains("APP SESSION START"))
    XCTAssertTrue(backendLog.contains("port=4321"))
  }

  private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
