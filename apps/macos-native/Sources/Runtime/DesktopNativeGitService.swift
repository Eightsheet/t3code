import Foundation

public enum DesktopNativeGitServiceError: Error, Equatable, Sendable {
  case commandFailed(command: String, message: String)
  case invalidUTF8(command: String)
  case notGitRepository
  case detachedHead
}

public struct DesktopNativeGitChangedFile: Equatable, Sendable {
  public let path: String
  public let status: String
  public let insertions: Int
  public let deletions: Int

  public init(path: String, status: String, insertions: Int, deletions: Int) {
    self.path = path
    self.status = status
    self.insertions = insertions
    self.deletions = deletions
  }
}

public struct DesktopNativeGitStatus: Equatable, Sendable {
  public let branch: String?
  public let aheadCount: Int
  public let behindCount: Int
  public let hasWorkingTreeChanges: Bool
  public let changedFiles: [DesktopNativeGitChangedFile]

  public init(
    branch: String?,
    aheadCount: Int,
    behindCount: Int,
    hasWorkingTreeChanges: Bool,
    changedFiles: [DesktopNativeGitChangedFile]
  ) {
    self.branch = branch
    self.aheadCount = aheadCount
    self.behindCount = behindCount
    self.hasWorkingTreeChanges = hasWorkingTreeChanges
    self.changedFiles = changedFiles
  }
}

public struct DesktopNativeGitBranch: Equatable, Identifiable, Sendable {
  public var id: String { name }
  public let name: String
  public let isCurrent: Bool
  public let isDefault: Bool

  public init(name: String, isCurrent: Bool, isDefault: Bool) {
    self.name = name
    self.isCurrent = isCurrent
    self.isDefault = isDefault
  }
}

public actor DesktopNativeGitService {
  private let environment: [String: String]

  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    var resolvedEnvironment = environment
    if let inheritedPath = LoginShellPathResolver.resolve(environment: environment) {
      resolvedEnvironment["PATH"] = inheritedPath
    }
    self.environment = resolvedEnvironment
  }

  public func status(cwd: String) throws -> DesktopNativeGitStatus {
    let statusResult = try runGit(
      cwd: cwd,
      arguments: ["status", "--porcelain=2", "--branch"],
      commandName: "git status --porcelain=2 --branch"
    )
    let unstagedNumstat = try runGit(
      cwd: cwd,
      arguments: ["diff", "--numstat"],
      commandName: "git diff --numstat"
    )
    let stagedNumstat = try runGit(
      cwd: cwd,
      arguments: ["diff", "--cached", "--numstat"],
      commandName: "git diff --cached --numstat"
    )

    let parsedStatus = Self.parseStatusPorcelain(statusResult.stdout)
    var aheadCount = parsedStatus.aheadCount
    let behindCount = parsedStatus.behindCount
    if parsedStatus.upstreamRef == nil, let branch = parsedStatus.branch {
      aheadCount = (try? computeAheadCountAgainstDefaultBranch(cwd: cwd, branch: branch)) ?? 0
    }

    let stagedEntries = Self.parseNumstatEntries(stagedNumstat.stdout)
    let unstagedEntries = Self.parseNumstatEntries(unstagedNumstat.stdout)
    var fileStats = [String: (insertions: Int, deletions: Int)]()
    for entry in stagedEntries + unstagedEntries {
      let existing = fileStats[entry.path] ?? (0, 0)
      fileStats[entry.path] = (
        insertions: existing.insertions + entry.insertions,
        deletions: existing.deletions + entry.deletions
      )
    }

    var files = [DesktopNativeGitChangedFile]()
    for (path, status) in parsedStatus.changedPaths.sorted(by: { $0.key < $1.key }) {
      let stats = fileStats[path] ?? (0, 0)
      files.append(
        DesktopNativeGitChangedFile(
          path: path,
          status: status,
          insertions: stats.insertions,
          deletions: stats.deletions
        )
      )
    }

    for (path, stats) in fileStats where parsedStatus.changedPaths[path] == nil {
      files.append(
        DesktopNativeGitChangedFile(
          path: path,
          status: "modified",
          insertions: stats.insertions,
          deletions: stats.deletions
        )
      )
    }
    files.sort { $0.path < $1.path }

    return DesktopNativeGitStatus(
      branch: parsedStatus.branch,
      aheadCount: aheadCount,
      behindCount: behindCount,
      hasWorkingTreeChanges: parsedStatus.hasWorkingTreeChanges,
      changedFiles: files
    )
  }

  public func branches(cwd: String) throws -> [DesktopNativeGitBranch] {
    let localBranchResult = try runGit(
      cwd: cwd,
      arguments: ["branch", "--no-color"],
      commandName: "git branch --no-color"
    )
    let defaultBranch = try? resolveDefaultBranch(cwd: cwd)

    let branches = localBranchResult.stdout
      .split(whereSeparator: \.isNewline)
      .compactMap(Self.parseBranchLine)
      .map {
        DesktopNativeGitBranch(
          name: $0.name,
          isCurrent: $0.isCurrent,
          isDefault: $0.name == defaultBranch
        )
      }
      .sorted { lhs, rhs in
        let lhsPriority = lhs.isCurrent ? 0 : (lhs.isDefault ? 1 : 2)
        let rhsPriority = rhs.isCurrent ? 0 : (rhs.isDefault ? 1 : 2)
        if lhsPriority != rhsPriority {
          return lhsPriority < rhsPriority
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
      }

    return branches
  }

  public func commitAllChanges(cwd: String, message: String) throws {
    let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedMessage.isEmpty == false else {
      throw DesktopNativeGitServiceError.commandFailed(command: "git commit", message: "Commit message is required.")
    }

    _ = try runGit(cwd: cwd, arguments: ["add", "-A"], commandName: "git add -A")
    _ = try runGit(cwd: cwd, arguments: ["commit", "-m", trimmedMessage], commandName: "git commit -m")
  }

  public func pushCurrentBranch(cwd: String) throws {
    let parsedStatus = try currentBranchStatus(cwd: cwd)
    guard let branch = parsedStatus.branch else {
      throw DesktopNativeGitServiceError.detachedHead
    }

    if parsedStatus.upstreamRef == nil {
      _ = try runGit(
        cwd: cwd,
        arguments: ["push", "-u", "origin", branch],
        commandName: "git push -u origin"
      )
      return
    }

    _ = try runGit(cwd: cwd, arguments: ["push"], commandName: "git push")
  }

  public func pullCurrentBranch(cwd: String) throws {
    _ = try runGit(cwd: cwd, arguments: ["pull", "--ff-only"], commandName: "git pull --ff-only")
  }

  public func checkoutBranch(cwd: String, branch: String) throws {
    _ = try runGit(cwd: cwd, arguments: ["checkout", branch], commandName: "git checkout")
  }

  private func currentBranchStatus(cwd: String) throws -> ParsedStatusPorcelain {
    let result = try runGit(
      cwd: cwd,
      arguments: ["status", "--porcelain=2", "--branch"],
      commandName: "git status --porcelain=2 --branch"
    )
    return Self.parseStatusPorcelain(result.stdout)
  }

  private func computeAheadCountAgainstDefaultBranch(cwd: String, branch: String) throws -> Int {
    guard let defaultBranch = try? resolveDefaultBranch(cwd: cwd), defaultBranch != branch else {
      return 0
    }

    let result = try runGit(
      cwd: cwd,
      arguments: ["rev-list", "--count", "\(defaultBranch)..HEAD"],
      commandName: "git rev-list --count"
    )
    return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
  }

  private func resolveDefaultBranch(cwd: String) throws -> String {
    if let remoteHead = try? runGit(
      cwd: cwd,
      arguments: ["symbolic-ref", "refs/remotes/origin/HEAD"],
      commandName: "git symbolic-ref refs/remotes/origin/HEAD"
    ).stdout.trimmingCharacters(in: .whitespacesAndNewlines),
      remoteHead.isEmpty == false
    {
      return remoteHead.replacingOccurrences(of: "refs/remotes/origin/", with: "")
    }

    if let localMainline = try? runGit(
      cwd: cwd,
      arguments: ["branch", "--format=%(refname:short)"],
      commandName: "git branch --format"
    ).stdout
      .split(whereSeparator: \.isNewline)
      .map(String.init)
      .first(where: { ["main", "master", "trunk"].contains($0) })
    {
      return localMainline
    }

    if let headBranch = try currentBranchStatus(cwd: cwd).branch {
      return headBranch
    }

    return "main"
  }

  private func runGit(
    cwd: String,
    arguments: [String],
    commandName: String
  ) throws -> (stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
    process.arguments = ["git"] + arguments
    process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
    process.environment = environment

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      throw DesktopNativeGitServiceError.commandFailed(
        command: commandName,
        message: error.localizedDescription
      )
    }
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
    guard let stdout = String(data: stdoutData, encoding: .utf8),
      let stderr = String(data: stderrData, encoding: .utf8)
    else {
      throw DesktopNativeGitServiceError.invalidUTF8(command: commandName)
    }

    guard process.terminationStatus == 0 else {
      let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      if message.localizedCaseInsensitiveContains("not a git repository") {
        throw DesktopNativeGitServiceError.notGitRepository
      }
      throw DesktopNativeGitServiceError.commandFailed(
        command: commandName,
        message: message.isEmpty ? "Command failed with status \(process.terminationStatus)." : message
      )
    }

    return (stdout, stderr)
  }

  private static func parseBranchLine(_ line: Substring) -> (name: String, isCurrent: Bool)? {
    let value = String(line)
    guard value.isEmpty == false else { return nil }
    let isCurrent = value.first == "*"
    let trimmed = value.dropFirst().trimmingCharacters(in: .whitespaces)
    guard trimmed.isEmpty == false else { return nil }
    return (trimmed, isCurrent)
  }

  private static func parseStatusPorcelain(_ output: String) -> ParsedStatusPorcelain {
    var branch: String?
    var upstreamRef: String?
    var aheadCount = 0
    var behindCount = 0
    var hasWorkingTreeChanges = false
    var changedPaths = [String: String]()

    for line in output.split(whereSeparator: \.isNewline) {
      let value = String(line)
      if value.hasPrefix("# branch.head ") {
        let head = String(value.dropFirst("# branch.head ".count))
        branch = head.hasPrefix("(") ? nil : head
        continue
      }
      if value.hasPrefix("# branch.upstream ") {
        let upstream = String(value.dropFirst("# branch.upstream ".count))
        upstreamRef = upstream.isEmpty ? nil : upstream
        continue
      }
      if value.hasPrefix("# branch.ab ") {
        let counts = String(value.dropFirst("# branch.ab ".count))
        let parts = counts.split(separator: " ")
        for part in parts {
          if part.hasPrefix("+") {
            aheadCount = Int(part.dropFirst()) ?? 0
          } else if part.hasPrefix("-") {
            behindCount = Int(part.dropFirst()) ?? 0
          }
        }
        continue
      }

      guard value.isEmpty == false, value.hasPrefix("#") == false else { continue }
      hasWorkingTreeChanges = true
      if let path = parsePorcelainPath(value) {
        changedPaths[path] = statusName(for: value)
      }
    }

    return ParsedStatusPorcelain(
      branch: branch,
      upstreamRef: upstreamRef,
      aheadCount: aheadCount,
      behindCount: behindCount,
      hasWorkingTreeChanges: hasWorkingTreeChanges,
      changedPaths: changedPaths
    )
  }

  private static func parsePorcelainPath(_ line: String) -> String? {
    if line.hasPrefix("? ") || line.hasPrefix("! ") {
      return String(line.dropFirst(2))
    }

    if line.hasPrefix("1 ") || line.hasPrefix("u ") {
      let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
      return parts.count == 9 ? String(parts[8]) : nil
    }

    if line.hasPrefix("2 ") {
      let tabSplit = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
      guard let firstSegment = tabSplit.first else { return nil }
      let parts = firstSegment.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: true)
      return parts.count >= 10 ? String(parts[9]) : nil
    }

    return nil
  }

  private static func parseNumstatEntries(_ output: String) -> [(path: String, insertions: Int, deletions: Int)] {
    output
      .split(whereSeparator: \.isNewline)
      .compactMap { line in
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        return (
          path: String(parts[2]),
          insertions: Int(parts[0]) ?? 0,
          deletions: Int(parts[1]) ?? 0
        )
      }
  }

  private static func statusName(for line: String) -> String {
    if line.hasPrefix("2 ") {
      return "renamed"
    }
    if line.hasPrefix("? ") {
      return "added"
    }

    let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
    guard parts.count > 1 else { return "modified" }
    let xy = String(parts[1])
    if xy.contains("R") {
      return "renamed"
    }
    if xy.contains("D") {
      return "deleted"
    }
    if xy.contains("A") {
      return "added"
    }
    return "modified"
  }
}

private struct ParsedStatusPorcelain {
  let branch: String?
  let upstreamRef: String?
  let aheadCount: Int
  let behindCount: Int
  let hasWorkingTreeChanges: Bool
  let changedPaths: [String: String]
}
