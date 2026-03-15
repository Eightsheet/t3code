import Foundation

public struct DesktopAppMetadata: Equatable, Sendable {
  public let displayName: String
  public let userModelID: String
  public let userDataDirectoryName: String
  public let legacyUserDataDirectoryName: String
  public let commitHash: String?
  public let userDataDirectory: URL

  public init(
    displayName: String,
    userModelID: String,
    userDataDirectoryName: String,
    legacyUserDataDirectoryName: String,
    commitHash: String?,
    userDataDirectory: URL
  ) {
    self.displayName = displayName
    self.userModelID = userModelID
    self.userDataDirectoryName = userDataDirectoryName
    self.legacyUserDataDirectoryName = legacyUserDataDirectoryName
    self.commitHash = commitHash
    self.userDataDirectory = userDataDirectory
  }
}

public enum DesktopAppMetadataResolver {
  private static let commitHashDisplayLength = 12

  public static func resolve(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    currentVersion _: String,
    isDevelopment: Bool,
    isPackaged: Bool,
    platformIdentifier: String,
    appRoot: URL,
    fileManager: FileManager = .default
  ) -> DesktopAppMetadata {
    let displayName = isDevelopment ? "T3 Code (Dev)" : "T3 Code (Alpha)"
    let userDataDirectoryName = isDevelopment ? "t3code-dev" : "t3code"
    let legacyUserDataDirectoryName = isDevelopment ? "T3 Code (Dev)" : "T3 Code (Alpha)"
    let commitHash = resolveAboutCommitHash(
      environment: environment,
      isPackaged: isPackaged,
      appRoot: appRoot,
      fileManager: fileManager
    )

    return DesktopAppMetadata(
      displayName: displayName,
      userModelID: "com.t3tools.t3code",
      userDataDirectoryName: userDataDirectoryName,
      legacyUserDataDirectoryName: legacyUserDataDirectoryName,
      commitHash: commitHash,
      userDataDirectory: resolveUserDataDirectory(
        platformIdentifier: platformIdentifier,
        userDataDirectoryName: userDataDirectoryName,
        legacyUserDataDirectoryName: legacyUserDataDirectoryName,
        environment: environment,
        fileManager: fileManager
      )
    )
  }

  public static func normalizeCommitHash(_ value: String?) -> String? {
    guard let value else {
      return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 7,
      trimmed.count <= 40,
      trimmed.unicodeScalars.allSatisfy({ scalar in
        CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains(scalar)
      })
    else {
      return nil
    }
    return String(trimmed.prefix(commitHashDisplayLength)).lowercased()
  }

  public static func resolveEmbeddedCommitHash(
    appRoot: URL,
    fileManager: FileManager = .default
  ) -> String? {
    let packageJSON = appRoot.appendingPathComponent("package.json", isDirectory: false)
    guard fileManager.fileExists(atPath: packageJSON.path),
      let data = try? Data(contentsOf: packageJSON),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }
    return normalizeCommitHash(object["t3codeCommitHash"] as? String)
  }

  public static func resolveAboutCommitHash(
    environment: [String: String],
    isPackaged: Bool,
    appRoot: URL,
    fileManager: FileManager = .default
  ) -> String? {
    if let envCommitHash = normalizeCommitHash(environment["T3CODE_COMMIT_HASH"]) {
      return envCommitHash
    }
    guard isPackaged else {
      return nil
    }
    return resolveEmbeddedCommitHash(appRoot: appRoot, fileManager: fileManager)
  }

  public static func resolveUserDataDirectory(
    platformIdentifier: String,
    userDataDirectoryName: String,
    legacyUserDataDirectoryName: String,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) -> URL {
    let baseDirectory: URL
    switch platformIdentifier {
    case "win32":
      let appData =
        environment["APPDATA"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
          ?? fileManager.homeDirectoryForCurrentUser
          .appendingPathComponent("AppData", isDirectory: true)
          .appendingPathComponent("Roaming", isDirectory: true).path
      baseDirectory = URL(fileURLWithPath: appData, isDirectory: true)
    case "darwin":
      let homePath =
        environment["HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
          ?? fileManager.homeDirectoryForCurrentUser.path
      baseDirectory = URL(fileURLWithPath: homePath, isDirectory: true)
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
    default:
      let configHome =
        environment["XDG_CONFIG_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
          ?? fileManager.homeDirectoryForCurrentUser
          .appendingPathComponent(".config", isDirectory: true).path
      baseDirectory = URL(fileURLWithPath: configHome, isDirectory: true)
    }

    let legacyURL = baseDirectory.appendingPathComponent(legacyUserDataDirectoryName, isDirectory: true)
    if fileManager.fileExists(atPath: legacyURL.path) {
      return legacyURL
    }
    return baseDirectory.appendingPathComponent(userDataDirectoryName, isDirectory: true)
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
