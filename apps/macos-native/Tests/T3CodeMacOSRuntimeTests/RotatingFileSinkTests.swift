import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class RotatingFileSinkTests: XCTestCase {
  func testWriteRotatesWhenMaxBytesExceeded() throws {
    let directory = makeTemporaryDirectory()
    let logURL = directory.appendingPathComponent("desktop.log", isDirectory: false)
    let sink = try RotatingFileSink(
      options: RotatingFileSinkOptions(fileURL: logURL, maxBytes: 8, maxFiles: 2)
    )

    try sink.write("1234")
    try sink.write("5678")
    try sink.write("90")

    XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "90")
    XCTAssertEqual(
      try String(contentsOf: logURL.appendingPathExtension("1"), encoding: .utf8),
      "12345678"
    )
  }

  private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
