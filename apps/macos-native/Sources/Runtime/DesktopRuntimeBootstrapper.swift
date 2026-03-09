import Foundation

public struct DesktopRuntimeConfiguration: Sendable {
  public let paths: DesktopRuntimePaths
  public let executableURL: URL
  public let arguments: [String]
  public let environment: [String: String]
  public let authToken: String
  public let port: Int
  public let websocketURL: URL
  public let inheritedPath: String?

  public init(
    paths: DesktopRuntimePaths,
    executableURL: URL,
    arguments: [String],
    environment: [String: String],
    authToken: String,
    port: Int,
    websocketURL: URL,
    inheritedPath: String?
  ) {
    self.paths = paths
    self.executableURL = executableURL
    self.arguments = arguments
    self.environment = environment
    self.authToken = authToken
    self.port = port
    self.websocketURL = websocketURL
    self.inheritedPath = inheritedPath
  }
}

public enum DesktopRuntimeBootstrapper {
  public static func prepare(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default,
    currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  ) throws -> DesktopRuntimeConfiguration {
    let paths = DesktopRuntimePathResolver.resolve(
      environment: environment,
      fileManager: fileManager,
      currentDirectoryURL: currentDirectoryURL
    )
    let port = try BackendPortAllocator.reserveLoopbackPort()
    let authToken = generateHexToken(byteCount: 24)
    let websocketURL = URL(string: "ws://127.0.0.1:\(port)/?token=\(authToken)")!

    var backendEnvironment = environment
    let inheritedPath = LoginShellPathResolver.resolve(environment: environment)
    if let inheritedPath {
      backendEnvironment["PATH"] = inheritedPath
    }
    backendEnvironment["T3CODE_MODE"] = "desktop"
    backendEnvironment["T3CODE_PORT"] = String(port)
    backendEnvironment["T3CODE_AUTH_TOKEN"] = authToken
    backendEnvironment["T3CODE_STATE_DIR"] = paths.stateDirectory.path
    backendEnvironment["T3CODE_DESKTOP_WS_URL"] = websocketURL.absoluteString

    let executableURL: URL
    let arguments: [String]
    if let configuredNodePath = environment["T3CODE_NODE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
      configuredNodePath.isEmpty == false
    {
      executableURL = URL(fileURLWithPath: configuredNodePath, isDirectory: false)
      arguments = [paths.backendEntry.path]
    } else {
      executableURL = URL(fileURLWithPath: "/usr/bin/env", isDirectory: false)
      arguments = ["node", paths.backendEntry.path]
    }

    return DesktopRuntimeConfiguration(
      paths: paths,
      executableURL: executableURL,
      arguments: arguments,
      environment: backendEnvironment,
      authToken: authToken,
      port: port,
      websocketURL: websocketURL,
      inheritedPath: inheritedPath
    )
  }

  public static func prepareOrNil(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default,
    currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
  ) -> DesktopRuntimeConfiguration? {
    try? prepare(
      environment: environment,
      fileManager: fileManager,
      currentDirectoryURL: currentDirectoryURL
    )
  }

  private static func generateHexToken(byteCount: Int) -> String {
    let bytes = (0..<byteCount).map { _ in
      UInt8.random(in: .min ... .max)
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }
}
