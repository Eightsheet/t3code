import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class DesktopNativeCheckpointDiffServiceTests: XCTestCase {
  private let gitRunner = DesktopNativeGitCommandRunner()

  func testParsesModifiedFileHunksBetweenCheckpointRefs() async throws {
    let repoURL = try makeTemporaryDirectory(testCase: self)
    try initializeRepository(at: repoURL)

    let threadId = "thread-native-diff"
    let ref0 = desktopCheckpointRefForThreadTurn(threadId, turnCount: 0)
    let ref1 = desktopCheckpointRefForThreadTurn(threadId, turnCount: 1)
    try updateRef(ref0, in: repoURL)

    try "hello\nupdated\n".write(
      to: repoURL.appendingPathComponent("README.md", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )
    try runGit(["add", "README.md"], in: repoURL)
    try runGit(["commit", "-m", "Update readme"], in: repoURL)
    try updateRef(ref1, in: repoURL)

    let service = DesktopNativeCheckpointDiffService()
    let diffs = try await service.diff(cwd: repoURL.path, fromCheckpointRef: ref0, toCheckpointRef: ref1)

    XCTAssertEqual(diffs.count, 1)
    XCTAssertEqual(diffs.first?.path, "README.md")
    XCTAssertEqual(diffs.first?.kind, "modified")
    XCTAssertEqual(diffs.first?.additions, 1)
    XCTAssertEqual(diffs.first?.deletions, 1)
    XCTAssertEqual(diffs.first?.hunks.first?.header, "@@ -1,2 +1,2 @@")
    XCTAssertEqual(diffs.first?.hunks.first?.lines[1].type, "delete")
    XCTAssertEqual(diffs.first?.hunks.first?.lines[1].oldLineNumber, 2)
    XCTAssertEqual(diffs.first?.hunks.first?.lines[2].type, "add")
    XCTAssertEqual(diffs.first?.hunks.first?.lines[2].newLineNumber, 2)
  }

  func testParsesRenameOnlyCheckpointDiffs() async throws {
    let repoURL = try makeTemporaryDirectory(testCase: self)
    try initializeRepository(at: repoURL)

    let ref0 = "refs/t3/checkpoints/rename/turn/0"
    let ref1 = "refs/t3/checkpoints/rename/turn/1"
    try updateRef(ref0, in: repoURL)

    try runGit(["mv", "README.md", "RENAMED.md"], in: repoURL)
    try runGit(["commit", "-m", "Rename file"], in: repoURL)
    try updateRef(ref1, in: repoURL)

    let service = DesktopNativeCheckpointDiffService()
    let diffs = try await service.diff(cwd: repoURL.path, fromCheckpointRef: ref0, toCheckpointRef: ref1)

    XCTAssertEqual(diffs.count, 1)
    XCTAssertEqual(diffs.first?.path, "RENAMED.md")
    XCTAssertEqual(diffs.first?.oldPath, "README.md")
    XCTAssertEqual(diffs.first?.kind, "renamed")
    XCTAssertEqual(diffs.first?.additions, 0)
    XCTAssertEqual(diffs.first?.deletions, 0)
  }

  func testCheckpointRefMatchesServerConvention() {
    XCTAssertEqual(
      desktopCheckpointRefForThreadTurn("thread-1", turnCount: 0),
      "refs/t3/checkpoints/dGhyZWFkLTE/turn/0"
    )
  }

  func testThrowsWhenCheckpointRefIsMissing() async throws {
    let repoURL = try makeTemporaryDirectory(testCase: self)
    try initializeRepository(at: repoURL)

    let service = DesktopNativeCheckpointDiffService()

    do {
      _ = try await service.diff(
        cwd: repoURL.path,
        fromCheckpointRef: "refs/t3/checkpoints/missing/turn/0",
        toCheckpointRef: "refs/t3/checkpoints/missing/turn/1"
      )
      XCTFail("Expected checkpointUnavailable error")
    } catch let error as DesktopNativeCheckpointDiffServiceError {
      XCTAssertEqual(error, .checkpointUnavailable(ref: "refs/t3/checkpoints/missing/turn/0"))
    }
  }

  private func initializeRepository(at url: URL) throws {
    try runGit(["init", "-b", "main"], in: url)
    try runGit(["config", "user.name", "T3 Tests"], in: url)
    try runGit(["config", "user.email", "t3@example.com"], in: url)
    try "hello\nworld\n".write(
      to: url.appendingPathComponent("README.md", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )
    try runGit(["add", "README.md"], in: url)
    try runGit(["commit", "-m", "Initial commit"], in: url)
  }

  private func updateRef(_ ref: String, in url: URL) throws {
    let commit = try runGit(["rev-parse", "HEAD"], in: url).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    _ = try runGit(["update-ref", ref, commit], in: url)
  }

  @discardableResult
  private func runGit(_ arguments: [String], in url: URL) throws -> (stdout: String, stderr: String) {
    try gitRunner.run(
      cwd: url.path,
      arguments: arguments,
      commandName: "git \(arguments.joined(separator: " "))"
    )
  }
}
