import XCTest

@testable import T3CodeMacOSRuntime

final class DesktopMigrationStatusTests: XCTestCase {
  func testCurrentStatusMakesRewriteStateExplicit() {
    let status = DesktopMigrationStatus.current

    XCTAssertTrue(status.hasStartedSwiftUI)
    XCTAssertFalse(status.nativeComponents.isEmpty)
    XCTAssertFalse(status.missingForFullApp.isEmpty)
    XCTAssertTrue(status.nativeComponents.contains("Backend process launch/supervision in Swift"))
    XCTAssertTrue(
      status.nativeComponents.contains(
        "Native SwiftUI chat UI with sidebar, message timeline, and composer in Swift"
      )
    )
    XCTAssertTrue(
      status.missingForFullApp.contains(
        "Terminal emulator integration (SwiftTerm or equivalent for real xterm I/O)"
      )
    )
  }
}
