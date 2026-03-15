import XCTest

@testable import T3CodeMacOSRuntime

final class DesktopUpdateManifestTests: XCTestCase {
  func testParseReadsMergedMacManifest() throws {
    let manifest = try DesktopUpdateManifestParser.parse(
      """
      version: 1.2.3
      files:
        - url: T3-Code-1.2.3-arm64.zip
          sha512: arm64
          size: 10
        - url: T3-Code-1.2.3-x64.zip
          sha512: x64
          size: 12
      releaseDate: '2026-03-09T12:00:00.000Z'
      """
    )

    XCTAssertEqual(manifest.version, "1.2.3")
    XCTAssertEqual(manifest.files.count, 2)
    XCTAssertEqual(manifest.releaseDate, "2026-03-09T12:00:00.000Z")
  }
}
