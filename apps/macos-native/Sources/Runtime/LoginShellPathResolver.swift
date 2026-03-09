import Foundation

public enum LoginShellPathResolver {
  public static func resolve(
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> String? {
    let shell = environment["SHELL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedShell = shell?.isEmpty == false ? shell! : "/bin/zsh"
    return try? readPath(shell: resolvedShell, environment: environment)
  }

  public static func readPath(
    shell: String,
    environment: [String: String]
  ) throws -> String? {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: shell, isDirectory: false)
    process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
    process.environment = shellEnvironment(from: environment)
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      return nil
    }

    let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let pathValue = String(decoding: output, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return pathValue.isEmpty ? nil : pathValue
  }

  private static func shellEnvironment(from environment: [String: String]) -> [String: String] {
    var result: [String: String] = [:]
    for key in ["HOME", "USER", "LOGNAME", "TERM"] {
      if let value = environment[key], value.isEmpty == false {
        result[key] = value
      }
    }
    result["PATH"] = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
    return result
  }
}
