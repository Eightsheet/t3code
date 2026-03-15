import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class DesktopStaticAssetResolverTests: XCTestCase {
  func testResolveStaticRootPrefersBundledServerClient() throws {
    let rootURL = try makeTemporaryDirectory(testCase: self)
    let staticRoot = rootURL.appendingPathComponent("apps/server/dist/client", isDirectory: true)
    try FileManager.default.createDirectory(at: staticRoot, withIntermediateDirectories: true)
    try "<html></html>".write(
      to: staticRoot.appendingPathComponent("index.html", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )

    XCTAssertEqual(
      DesktopStaticAssetResolver.resolveStaticRoot(appRoot: rootURL),
      staticRoot
    )
  }

  func testResolvePathFallsBackToIndexForDocumentsAndMissingAssets() throws {
    let rootURL = try makeTemporaryDirectory(testCase: self)
    let staticRoot = rootURL.appendingPathComponent("client", isDirectory: true)
    try FileManager.default.createDirectory(at: staticRoot, withIntermediateDirectories: true)
    try "<html>index</html>".write(
      to: staticRoot.appendingPathComponent("index.html", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )
    let scriptURL = staticRoot.appendingPathComponent("assets/app.js", isDirectory: false)
    try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "console.log('ok')".write(to: scriptURL, atomically: true, encoding: .utf8)

    let documentResolution = DesktopStaticAssetResolver.resolvePath(
      staticRoot: staticRoot,
      requestURL: URL(string: "t3://app/projects/123")!
    )
    XCTAssertEqual(
      documentResolution,
      .document(staticRoot.appendingPathComponent("index.html", isDirectory: false))
    )

    let assetResolution = DesktopStaticAssetResolver.resolvePath(
      staticRoot: staticRoot,
      requestURL: URL(string: "t3://app/assets/app.js")!
    )
    XCTAssertEqual(assetResolution, .asset(scriptURL))
  }
}
