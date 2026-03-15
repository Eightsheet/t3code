#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class PackagedDesktopLoggingTests: XCTestCase {
  func testLoggingSessionCapturesStandardOutputAndStandardError() throws {
    let directory = try makeTemporaryDirectory(testCase: self)
    let session = try PackagedDesktopLoggingSession(
      options: PackagedDesktopLoggingOptions(logDirectory: directory, maxBytes: 8_192, maxFiles: 2)
    )

    try session.start()
    defer { session.stop() }

    writeIgnoringTestHarnessErrors("swift stdout capture\n", to: STDOUT_FILENO)
    writeIgnoringTestHarnessErrors("swift stderr capture\n", to: STDERR_FILENO)
    flushDescriptorIgnoringErrors(STDOUT_FILENO)
    flushDescriptorIgnoringErrors(STDERR_FILENO)

    Thread.sleep(forTimeInterval: 0.2)

    let desktopLog = try String(
      contentsOf: directory.appendingPathComponent("desktop-main.log", isDirectory: false),
      encoding: .utf8
    )
    XCTAssertTrue(desktopLog.contains("runtime log capture enabled"))
    XCTAssertTrue(desktopLog.contains("swift stdout capture"))
    XCTAssertTrue(desktopLog.contains("swift stderr capture"))
  }

  private func writeIgnoringTestHarnessErrors(_ string: String, to descriptor: Int32) {
    _ = string.withCString { pointer in
      write(descriptor, pointer, strlen(pointer))
    }
  }

  private func flushDescriptorIgnoringErrors(_ descriptor: Int32) {
    _ = fsync(descriptor)
  }
}
