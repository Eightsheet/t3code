import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class GitHubReleaseUpdaterClientTests: XCTestCase {
  func testClientChecksDownloadsAndInstallsPreferredArm64Payload() async throws {
    let directory = try makeTemporaryDirectory(testCase: self)
    let transport = FakeDesktopUpdateTransport()
    let verifier = RecordingIntegrityVerifier()
    let installer = RecordingInstaller()
    let manifest = """
    version: 1.2.0
    files:
      - url: T3-Code-1.2.0-arm64.zip
        sha512: arm64-sha
        size: 5
      - url: T3-Code-1.2.0-x64.zip
        sha512: x64-sha
        size: 4
    releaseDate: '2026-03-09T12:00:00.000Z'
    """
    transport.responses = [
      "https://api.github.com/repos/Eightsheet/t3code/releases/latest": releaseJSON().data(using: .utf8)!,
      "https://example.test/latest-mac.yml": manifest.data(using: .utf8)!,
      "https://example.test/T3-Code-1.2.0-arm64.zip": Data("12345".utf8),
    ]

    let client = GitHubReleaseUpdaterClient(
      feed: DesktopUpdateFeedConfiguration(provider: "github", owner: "Eightsheet", repo: "t3code"),
      currentVersion: "1.1.0",
      runtimeInfo: DesktopRuntimeInfo(hostArch: .arm64, appArch: .x64, runningUnderArm64Translation: true),
      environment: [:],
      appRoot: directory,
      transport: transport,
      verifier: verifier,
      installer: installer,
      fileManager: .default,
      downloadDirectory: directory
    )

    let checkResult = try await client.checkForUpdates()
    XCTAssertEqual(checkResult, .updateAvailable(version: "1.2.0"))

    let downloadResult = try await client.downloadUpdate(progress: { _ in })
    XCTAssertEqual(downloadResult.version, "1.2.0")
    XCTAssertEqual(verifier.lastVerifiedFileName, "T3-Code-1.2.0-arm64.zip")
    XCTAssertEqual(verifier.lastExpectedSHA512, "arm64-sha")

    try await client.installUpdate()
    XCTAssertEqual(installer.installedFileName, "T3-Code-1.2.0-arm64.zip")
  }

  private func releaseJSON() -> String {
    """
    {
      "assets": [
        {
          "name": "latest-mac.yml",
          "browser_download_url": "https://example.test/latest-mac.yml",
          "size": 200
        },
        {
          "name": "T3-Code-1.2.0-arm64.zip",
          "browser_download_url": "https://example.test/T3-Code-1.2.0-arm64.zip",
          "size": 5
        }
      ]
    }
    """
  }
}

private final class FakeDesktopUpdateTransport: DesktopUpdateTransport, @unchecked Sendable {
  var responses: [String: Data] = [:]

  func fetchData(from url: URL, headers _: [String: String]) async throws -> Data {
    guard let data = responses[url.absoluteString] else {
      throw GitHubReleaseUpdaterClientError.httpFailure(url.absoluteString)
    }
    return data
  }

  func downloadData(
    from url: URL,
    headers _: [String: String],
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> Data {
    progress(100)
    return try await fetchData(from: url, headers: [:])
  }
}

private final class RecordingIntegrityVerifier: DesktopUpdateIntegrityVerifier, @unchecked Sendable {
  private(set) var lastVerifiedFileName: String?
  private(set) var lastExpectedSHA512: String?

  func verify(fileURL: URL, expectedSHA512: String) throws {
    lastVerifiedFileName = fileURL.lastPathComponent
    lastExpectedSHA512 = expectedSHA512
  }
}

private final class RecordingInstaller: DesktopUpdateInstaller, @unchecked Sendable {
  private(set) var installedFileName: String?

  func install(fileURL: URL) throws {
    installedFileName = fileURL.lastPathComponent
  }
}
