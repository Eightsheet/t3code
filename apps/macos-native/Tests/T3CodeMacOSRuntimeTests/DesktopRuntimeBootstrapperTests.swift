import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class DesktopRuntimeBootstrapperTests: XCTestCase {
  func testPrepareBuildsBackendLaunchEnvironment() throws {
    let rootURL = try makeTemporaryDirectory(testCase: self)
    let serverDirectory = rootURL.appendingPathComponent("apps/server/dist", isDirectory: true)
    try FileManager.default.createDirectory(at: serverDirectory, withIntermediateDirectories: true)
    try "{}".write(
      to: rootURL.appendingPathComponent("package.json", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )
    try "console.log('ready');".write(
      to: serverDirectory.appendingPathComponent("index.mjs", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )

    let stateDirectory = rootURL.appendingPathComponent("state", isDirectory: true)
    let configuration = try DesktopRuntimeBootstrapper.prepare(
      environment: [
        "PATH": "/usr/bin:/bin",
        "SHELL": "/bin/sh",
        "T3CODE_APP_ROOT": rootURL.path,
        "T3CODE_STATE_DIR": stateDirectory.path,
        "T3CODE_NODE_PATH": "/usr/bin/node",
      ],
      currentDirectoryURL: rootURL
    )

    XCTAssertEqual(configuration.paths.appRoot.path, rootURL.path)
    XCTAssertEqual(configuration.paths.backendEntry.path, serverDirectory.appendingPathComponent("index.mjs").path)
    XCTAssertEqual(configuration.environment["T3CODE_MODE"], "desktop")
    XCTAssertEqual(configuration.environment["T3CODE_NO_BROWSER"], "1")
    XCTAssertEqual(configuration.environment["T3CODE_STATE_DIR"], stateDirectory.path)
    XCTAssertEqual(configuration.executableURL.path, "/usr/bin/node")
    XCTAssertEqual(configuration.arguments, [configuration.paths.backendEntry.path])
    XCTAssertEqual(configuration.authToken.count, 48)
    XCTAssertTrue(configuration.port > 0)
    XCTAssertEqual(configuration.websocketURL.scheme, "ws")
  }
}
