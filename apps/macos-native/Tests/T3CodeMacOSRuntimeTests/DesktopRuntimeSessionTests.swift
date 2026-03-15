import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class DesktopRuntimeSessionTests: XCTestCase {
  func testSessionRestartsBackendAfterUnexpectedExit() async throws {
    let directory = try makeTemporaryDirectory(testCase: self)
    let scriptURL = directory.appendingPathComponent("backend.sh", isDirectory: false)
    try "#!/bin/sh\nexit 0\n".write(to: scriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

    let configuration = DesktopRuntimeConfiguration(
      paths: DesktopRuntimePaths(
        appRoot: directory,
        backendEntry: scriptURL,
        backendWorkingDirectory: directory,
        stateDirectory: directory,
        logDirectory: directory
      ),
      executableURL: URL(fileURLWithPath: "/usr/bin/env", isDirectory: false),
      arguments: ["sh", scriptURL.path],
      environment: [:],
      authToken: "token",
      port: 4321,
      websocketURL: URL(string: "ws://127.0.0.1:4321/?token=token")!,
      inheritedPath: nil
    )

    let session = DesktopRuntimeSession(
      options: DesktopRuntimeSessionOptions(
        currentVersion: "1.0.0",
        runtimeInfo: DesktopRuntimeInfo(hostArch: .x64, appArch: .x64, runningUnderArm64Translation: false),
        updateEnvironment: DesktopUpdateEnvironment(
          isDevelopment: true,
          isPackaged: false,
          platformIdentifier: "darwin",
          appImagePath: nil,
          disabledByEnvironment: false
        )
      ),
      configurationLoader: { configuration },
      restartDelayProvider: { _ in 0.01 }
    )

    let restarted = expectation(description: "session reaches restarted state")
    await session.setOnStateChanged { snapshot in
      if snapshot.lifecycle == .running, snapshot.restartAttempt > 0 {
        restarted.fulfill()
      }
    }

    await session.start()
    await fulfillment(of: [restarted], timeout: 2)
    await session.stop()
  }
}
