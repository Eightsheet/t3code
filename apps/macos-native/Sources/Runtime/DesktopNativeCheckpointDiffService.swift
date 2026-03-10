import Foundation

public enum DesktopNativeCheckpointDiffServiceError: Error, Equatable, Sendable {
  case commandFailed(command: String, message: String)
  case invalidUTF8(command: String)
  case notGitRepository
  case checkpointUnavailable(ref: String)

  init(runnerError: DesktopNativeGitCommandRunnerError) {
    switch runnerError {
    case let .commandFailed(command, message):
      self = .commandFailed(command: command, message: message)
    case let .invalidUTF8(command):
      self = .invalidUTF8(command: command)
    case .notGitRepository:
      self = .notGitRepository
    }
  }
}

public struct DesktopNativeDiffLine: Equatable, Sendable {
  public let type: String
  public let content: String
  public let oldLineNumber: Int?
  public let newLineNumber: Int?

  public init(type: String, content: String, oldLineNumber: Int?, newLineNumber: Int?) {
    self.type = type
    self.content = content
    self.oldLineNumber = oldLineNumber
    self.newLineNumber = newLineNumber
  }
}

public struct DesktopNativeDiffHunk: Equatable, Sendable {
  public let header: String
  public let lines: [DesktopNativeDiffLine]

  public init(header: String, lines: [DesktopNativeDiffLine]) {
    self.header = header
    self.lines = lines
  }
}

public struct DesktopNativeFileDiff: Equatable, Sendable {
  public let path: String
  public let oldPath: String?
  public let kind: String
  public let additions: Int
  public let deletions: Int
  public let hunks: [DesktopNativeDiffHunk]

  public init(
    path: String,
    oldPath: String?,
    kind: String,
    additions: Int,
    deletions: Int,
    hunks: [DesktopNativeDiffHunk]
  ) {
    self.path = path
    self.oldPath = oldPath
    self.kind = kind
    self.additions = additions
    self.deletions = deletions
    self.hunks = hunks
  }
}

public func desktopCheckpointRefForThreadTurn(_ threadId: String, turnCount: Int) -> String {
  let encoded = Data(threadId.utf8)
    .base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
  return "refs/t3/checkpoints/\(encoded)/turn/\(turnCount)"
}

public actor DesktopNativeCheckpointDiffService {
  private let commandRunner: DesktopNativeGitCommandRunner

  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    self.commandRunner = DesktopNativeGitCommandRunner(environment: environment)
  }

  public func diff(cwd: String, fromCheckpointRef: String, toCheckpointRef: String) throws -> [DesktopNativeFileDiff] {
    let fromCommit = try resolveCommit(cwd: cwd, ref: fromCheckpointRef)
    let toCommit = try resolveCommit(cwd: cwd, ref: toCheckpointRef)
    let patch = try runGit(
      cwd: cwd,
      arguments: ["diff", "--patch", "--minimal", "--no-color", fromCommit, toCommit],
      commandName: "git diff --patch --minimal --no-color"
    ).stdout
    return Self.parseUnifiedDiff(patch)
  }

  private func resolveCommit(cwd: String, ref: String) throws -> String {
    let result: (stdout: String, stderr: String)
    do {
      result = try runGit(
        cwd: cwd,
        arguments: ["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"],
        commandName: "git rev-parse --verify --quiet"
      )
    } catch let error as DesktopNativeCheckpointDiffServiceError {
      if case .commandFailed("git rev-parse --verify --quiet", _) = error {
        throw DesktopNativeCheckpointDiffServiceError.checkpointUnavailable(ref: ref)
      }
      throw error
    }
    let commit = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !commit.isEmpty else {
      throw DesktopNativeCheckpointDiffServiceError.checkpointUnavailable(ref: ref)
    }
    return commit
  }

  private func runGit(
    cwd: String,
    arguments: [String],
    commandName: String
  ) throws -> (stdout: String, stderr: String) {
    do {
      return try commandRunner.run(cwd: cwd, arguments: arguments, commandName: commandName)
    } catch let error as DesktopNativeGitCommandRunnerError {
      throw DesktopNativeCheckpointDiffServiceError(runnerError: error)
    }
  }

  private static func parseUnifiedDiff(_ patch: String) -> [DesktopNativeFileDiff] {
    let normalized = patch.replacingOccurrences(of: "\r\n", with: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      return []
    }

    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var files = [ParsedFileDiff]()
    var currentFile: ParsedFileDiff?
    var currentHunk: ParsedHunk?

    func flushHunk() {
      guard let hunk = currentHunk else { return }
      currentFile?.hunks.append(
        DesktopNativeDiffHunk(
          header: hunk.header,
          lines: hunk.lines
        )
      )
      currentHunk = nil
    }

    func flushFile() {
      flushHunk()
      guard let file = currentFile else { return }
      files.append(file)
      currentFile = nil
    }

    for line in lines {
      if line.hasPrefix("diff --git ") {
        flushFile()
        currentFile = parseDiffHeader(line)
        continue
      }

      guard currentFile != nil else {
        continue
      }

      if line.hasPrefix("@@ ") {
        flushHunk()
        if let parsedHeader = parseHunkHeader(line) {
          currentHunk = ParsedHunk(header: line, oldLine: parsedHeader.oldStart, newLine: parsedHeader.newStart)
        }
        continue
      }

      if line.hasPrefix("new file mode ") {
        currentFile?.kind = "added"
        continue
      }
      if line.hasPrefix("deleted file mode ") {
        currentFile?.kind = "deleted"
        continue
      }
      if line.hasPrefix("rename from ") {
        currentFile?.kind = "renamed"
        currentFile?.oldPath = String(line.dropFirst("rename from ".count))
        continue
      }
      if line.hasPrefix("rename to ") {
        currentFile?.kind = "renamed"
        currentFile?.path = String(line.dropFirst("rename to ".count))
        continue
      }
      if line.hasPrefix("--- ") {
        let oldPath = normalizedPatchPath(String(line.dropFirst(4)))
        if oldPath != "/dev/null" {
          currentFile?.oldPath = oldPath
        }
        continue
      }
      if line.hasPrefix("+++ ") {
        let newPath = normalizedPatchPath(String(line.dropFirst(4)))
        if newPath == "/dev/null" {
          currentFile?.kind = "deleted"
        } else {
          currentFile?.path = newPath
        }
        continue
      }

      guard var hunk = currentHunk else {
        continue
      }

      if line == "\\ No newline at end of file" {
        currentHunk = hunk
        continue
      }

      switch line.first {
      case " ":
        hunk.lines.append(
          DesktopNativeDiffLine(
            type: "context",
            content: String(line.dropFirst()),
            oldLineNumber: hunk.oldLine,
            newLineNumber: hunk.newLine
          )
        )
        hunk.oldLine += 1
        hunk.newLine += 1
      case "+":
        hunk.lines.append(
          DesktopNativeDiffLine(
            type: "add",
            content: String(line.dropFirst()),
            oldLineNumber: nil,
            newLineNumber: hunk.newLine
          )
        )
        hunk.newLine += 1
        currentFile?.additions += 1
      case "-":
        hunk.lines.append(
          DesktopNativeDiffLine(
            type: "delete",
            content: String(line.dropFirst()),
            oldLineNumber: hunk.oldLine,
            newLineNumber: nil
          )
        )
        hunk.oldLine += 1
        currentFile?.deletions += 1
      default:
        break
      }

      currentHunk = hunk
    }

    flushFile()
    return files.map {
      DesktopNativeFileDiff(
        path: $0.path,
        oldPath: $0.oldPath,
        kind: $0.kind,
        additions: $0.additions,
        deletions: $0.deletions,
        hunks: $0.hunks
      )
    }
    .sorted { $0.path < $1.path }
  }

  private static func parseDiffHeader(_ line: String) -> ParsedFileDiff {
    let parts = line.split(separator: " ")
    let oldPathIndex = 2
    let newPathIndex = 3
    let oldPath = parts.count > oldPathIndex ? normalizedPatchPath(String(parts[oldPathIndex])) : ""
    let newPath = parts.count > newPathIndex ? normalizedPatchPath(String(parts[newPathIndex])) : oldPath
    return ParsedFileDiff(
      path: newPath,
      oldPath: oldPath == newPath ? nil : oldPath,
      kind: "modified",
      additions: 0,
      deletions: 0,
      hunks: []
    )
  }

  private static func normalizedPatchPath(_ path: String) -> String {
    if path == "/dev/null" {
      return path
    }
    if path.hasPrefix("a/") || path.hasPrefix("b/") {
      return String(path.dropFirst(2))
    }
    return path
  }

  private static func parseHunkHeader(_ header: String) -> (oldStart: Int, newStart: Int)? {
    let pattern = #"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
      match.numberOfRanges == 3,
      let oldRange = Range(match.range(at: 1), in: header),
      let newRange = Range(match.range(at: 2), in: header),
      let oldStart = Int(header[oldRange]),
      let newStart = Int(header[newRange])
    else {
      return nil
    }
    return (oldStart, newStart)
  }
}

private struct ParsedFileDiff {
  var path: String
  var oldPath: String?
  var kind: String
  var additions: Int
  var deletions: Int
  var hunks: [DesktopNativeDiffHunk]
}

private struct ParsedHunk {
  let header: String
  var oldLine: Int
  var newLine: Int
  var lines: [DesktopNativeDiffLine] = []
}
