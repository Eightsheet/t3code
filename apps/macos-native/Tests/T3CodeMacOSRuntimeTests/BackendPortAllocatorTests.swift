import XCTest

@testable import T3CodeMacOSRuntime

final class BackendPortAllocatorTests: XCTestCase {
  func testReserveLoopbackPortReturnsPositivePort() throws {
    let port = try BackendPortAllocator.reserveLoopbackPort()
    XCTAssertGreaterThan(port, 0)
  }
}
