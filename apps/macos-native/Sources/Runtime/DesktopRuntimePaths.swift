import Foundation

public struct DesktopRuntimePaths: Equatable, Sendable {
  public let appRoot: URL
  public let backendEntry: URL
  public let backendWorkingDirectory: URL
  public let stateDirectory: URL
  public let logDirectory: URL

  public init(
    appRoot: URL,
    backendEntry: URL,
    backendWorkingDirectory: URL,
    stateDirectory: URL,
    logDirectory: URL
  ) {
    self.appRoot = appRoot
    self.backendEntry = backendEntry
    self.backendWorkingDirectory = backendWorkingDirectory
    self.stateDirectory = stateDirectory
    self.logDirectory = logDirectory
  }
}

public enum DesktopRuntimePathResolver {
  public static func resolve(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default,
    currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  ) -> DesktopRuntimePaths {
    let appRoot = resolveAppRoot(
      environment: environment,
      fileManager: fileManager,
      currentDirectoryURL: currentDirectoryURL
    )
    let stateDirectory = resolveStateDirectory(environment: environment, fileManager: fileManager)
    let backendEntry = appRoot.appendingPathComponent("apps/server/dist/index.mjs", isDirectory: false)
    let logDirectory = stateDirectory.appendingPathComponent("logs", isDirectory: true)

    return DesktopRuntimePaths(
      appRoot: appRoot,
      backendEntry: backendEntry,
      backendWorkingDirectory: appRoot,
      stateDirectory: stateDirectory,
      logDirectory: logDirectory
    )
  }

  private static func resolveAppRoot(
    environment: [String: String],
    fileManager: FileManager,
    currentDirectoryURL: URL
  ) -> URL {
    if let configuredRoot = environment["T3CODE_APP_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      configuredRoot.isEmpty == false
    {
      return URL(fileURLWithPath: configuredRoot, isDirectory: true)
    }

    let startPoints = [currentDirectoryURL, Bundle.main.bundleURL]
    for startPoint in startPoints {
      if let matchedRoot = firstRepositoryRoot(startingAt: startPoint, fileManager: fileManager) {
        return matchedRoot
      }
    }

    return currentDirectoryURL
  }

  private static func firstRepositoryRoot(startingAt startURL: URL, fileManager: FileManager) -> URL? {
    var candidate = startURL.standardizedFileURL

    for _ in 0..<12 {
      if isRepositoryRoot(candidate, fileManager: fileManager) {
        return candidate
      }

      let parent = candidate.deletingLastPathComponent()
      if parent.path == candidate.path {
        return nil
      }
      candidate = parent
    }

    return nil
  }

  private static func isRepositoryRoot(_ candidate: URL, fileManager: FileManager) -> Bool {
    let packageJSON = candidate.appendingPathComponent("package.json", isDirectory: false).path
    let serverDirectory = candidate.appendingPathComponent("apps/server", isDirectory: true).path
    return fileManager.fileExists(atPath: packageJSON) && fileManager.fileExists(atPath: serverDirectory)
  }

  private static func resolveStateDirectory(
    environment: [String: String],
    fileManager: FileManager
  ) -> URL {
    if let configuredStateDirectory = environment["T3CODE_STATE_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      configuredStateDirectory.isEmpty == false
    {
      return URL(fileURLWithPath: configuredStateDirectory, isDirectory: true)
    }

    let homeDirectory = fileManager.homeDirectoryForCurrentUser
    return homeDirectory
      .appendingPathComponent(".t3", isDirectory: true)
      .appendingPathComponent("userdata", isDirectory: true)
  }
}
