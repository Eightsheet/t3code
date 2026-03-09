import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class DesktopAppMetadataTests: XCTestCase {
  func testResolvePrefersEnvironmentCommitHashAndLegacyUserDataDirectory() throws {
    let rootURL = try makeTemporaryDirectory(testCase: self)
    let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
    let legacyDirectory = homeURL
      .appendingPathComponent("Library", isDirectory: true)
      .appendingPathComponent("Application Support", isDirectory: true)
      .appendingPathComponent("T3 Code (Alpha)", isDirectory: true)
    try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

    let metadata = DesktopAppMetadataResolver.resolve(
      environment: [
        "HOME": homeURL.path,
        "T3CODE_COMMIT_HASH": "ABCDEF1234567890",
      ],
      currentVersion: "1.2.3",
      isDevelopment: false,
      isPackaged: true,
      platformIdentifier: "darwin",
      appRoot: rootURL,
      fileManager: .default
    )

    XCTAssertEqual(metadata.displayName, "T3 Code (Alpha)")
    XCTAssertEqual(metadata.commitHash, "abcdef123456")
    XCTAssertEqual(metadata.userDataDirectory.path, legacyDirectory.path)
  }

  func testResolveEmbeddedCommitHashReadsPackageJson() throws {
    let rootURL = try makeTemporaryDirectory(testCase: self)
    try """
    {"t3codeCommitHash":"1234567890abcdef"}
    """.write(
      to: rootURL.appendingPathComponent("package.json", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )

    XCTAssertEqual(
      DesktopAppMetadataResolver.resolveEmbeddedCommitHash(appRoot: rootURL),
      "1234567890ab"
    )
  }
}
