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
      status.missingForFullApp.contains(
        "Native renderer UI for sessions, conversations, and event streaming"
      )
    )
  }
}
