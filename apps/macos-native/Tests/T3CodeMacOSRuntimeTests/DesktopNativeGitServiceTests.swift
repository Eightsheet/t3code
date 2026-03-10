import Foundation
import XCTest

@testable import T3CodeMacOSRuntime

final class DesktopNativeGitServiceTests: XCTestCase {
  func testStatusTracksBranchAheadCountAndWorkingTreeChanges() async throws {
    let repoURL = try makeTemporaryDirectory(testCase: self)
    try initializeRepository(at: repoURL)

    let service = DesktopNativeGitService()
    try runGit(["checkout", "-b", "feature/native-status"], in: repoURL)
    try "updated\nline\n".write(
      to: repoURL.appendingPathComponent("README.md", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )
    try runGit(["add", "README.md"], in: repoURL)
    try runGit(["commit", "-m", "Update readme"], in: repoURL)
    try "updated\nline\nwith working tree change\n".write(
      to: repoURL.appendingPathComponent("README.md", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )

    let status = try await service.status(cwd: repoURL.path)

    XCTAssertEqual(status.branch, "feature/native-status")
    XCTAssertEqual(status.aheadCount, 1)
    XCTAssertEqual(status.behindCount, 0)
    XCTAssertTrue(status.hasWorkingTreeChanges)
    XCTAssertEqual(status.changedFiles.first?.path, "README.md")
    XCTAssertEqual(status.changedFiles.first?.status, "modified")
    XCTAssertEqual(status.changedFiles.first?.insertions, 1)
  }

  func testBranchesAndCheckoutReflectCurrentAndDefaultBranch() async throws {
    let repoURL = try makeTemporaryDirectory(testCase: self)
    try initializeRepository(at: repoURL)
    try runGit(["checkout", "-b", "feature/native-branches"], in: repoURL)

    let service = DesktopNativeGitService()
    let featureBranches = try await service.branches(cwd: repoURL.path)
    XCTAssertEqual(featureBranches.first?.name, "feature/native-branches")
    XCTAssertEqual(featureBranches.first?.isCurrent, true)
    XCTAssertTrue(featureBranches.contains(where: { $0.name == "main" && $0.isDefault }))

    try await service.checkoutBranch(cwd: repoURL.path, branch: "main")
    let mainBranches = try await service.branches(cwd: repoURL.path)
    XCTAssertEqual(mainBranches.first?.name, "main")
    XCTAssertEqual(mainBranches.first?.isCurrent, true)
    XCTAssertTrue(mainBranches.first?.isDefault == true)
  }

  func testCommitAllChangesStagesAndCommitsTrackedChanges() async throws {
    let repoURL = try makeTemporaryDirectory(testCase: self)
    try initializeRepository(at: repoURL)

    let service = DesktopNativeGitService()
    try "committed through native service\n".write(
      to: repoURL.appendingPathComponent("README.md", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )

    try await service.commitAllChanges(cwd: repoURL.path, message: "Native git commit")

    let log = try runGit(["log", "-1", "--pretty=%s"], in: repoURL)
    XCTAssertEqual(log.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "Native git commit")

    let status = try await service.status(cwd: repoURL.path)
    XCTAssertFalse(status.hasWorkingTreeChanges)
  }

  private func initializeRepository(at url: URL) throws {
    try runGit(["init", "-b", "main"], in: url)
    try runGit(["config", "user.name", "T3 Tests"], in: url)
    try runGit(["config", "user.email", "t3@example.com"], in: url)
    try "hello\n".write(
      to: url.appendingPathComponent("README.md", isDirectory: false),
      atomically: true,
      encoding: .utf8
    )
    try runGit(["add", "README.md"], in: url)
    try runGit(["commit", "-m", "Initial commit"], in: url)
  }

  @discardableResult
  private func runGit(_ arguments: [String], in url: URL) throws -> (stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = url

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    try process.run()
    process.waitUntilExit()

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    XCTAssertEqual(process.terminationStatus, 0, "git \(arguments.joined(separator: " ")) failed: \(stderr)")
    return (stdout, stderr)
  }
}
