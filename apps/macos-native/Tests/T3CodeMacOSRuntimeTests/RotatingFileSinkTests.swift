import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class RotatingFileSinkTests: XCTestCase {
  func testWriteRotatesWhenMaxBytesExceeded() throws {
    let directory = try makeTemporaryDirectory(testCase: self)
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

  func testRotationPrunesBackupsBeyondMaxFiles() throws {
    let directory = try makeTemporaryDirectory(testCase: self)
    let logURL = directory.appendingPathComponent("desktop.log", isDirectory: false)
    let sink = try RotatingFileSink(
      options: RotatingFileSinkOptions(fileURL: logURL, maxBytes: 4, maxFiles: 2)
    )

    try sink.write("1111")
    try sink.write("2222")
    try sink.write("3333")
    try sink.write("4444")

    XCTAssertEqual(try String(contentsOf: logURL, encoding: .utf8), "4444")
    XCTAssertEqual(try String(contentsOf: logURL.appendingPathExtension("1"), encoding: .utf8), "3333")
    XCTAssertEqual(try String(contentsOf: logURL.appendingPathExtension("2"), encoding: .utf8), "2222")
    XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.appendingPathExtension("3").path))
  }
}
