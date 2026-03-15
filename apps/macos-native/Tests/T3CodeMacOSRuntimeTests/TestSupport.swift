import Foundation
import XCTest

func makeTemporaryDirectory(testCase: XCTestCase) throws -> URL {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  testCase.addTeardownBlock {
    try? FileManager.default.removeItem(at: url)
  }
  return url
}
