import Foundation

enum DesktopNativeGitCommandRunnerError: Error, Equatable, Sendable {
  case commandFailed(command: String, message: String)
  case invalidUTF8(command: String)
  case notGitRepository
}

struct DesktopNativeGitCommandRunner: Sendable {
  private let environment: [String: String]

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    var resolvedEnvironment = environment
    if let inheritedPath = LoginShellPathResolver.resolve(environment: environment) {
      resolvedEnvironment["PATH"] = inheritedPath
    }
    self.environment = resolvedEnvironment
  }

  func run(cwd: String, arguments: [String], commandName: String) throws -> (stdout: String, stderr: String) {
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
      throw DesktopNativeGitCommandRunnerError.commandFailed(
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
      throw DesktopNativeGitCommandRunnerError.invalidUTF8(command: commandName)
    }

    guard process.terminationStatus == 0 else {
      let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      if message.localizedCaseInsensitiveContains("not a git repository") {
        throw DesktopNativeGitCommandRunnerError.notGitRepository
      }
      throw DesktopNativeGitCommandRunnerError.commandFailed(
        command: commandName,
        message: message.isEmpty ? "Command failed with status \(process.terminationStatus)." : message
      )
    }

    return (stdout, stderr)
  }
}
