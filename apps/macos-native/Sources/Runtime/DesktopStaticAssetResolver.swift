import Foundation

public enum DesktopStaticAssetResolution: Equatable, Sendable {
  case asset(URL)
  case document(URL)
}

public enum DesktopStaticAssetResolver {
  public static func resolveStaticRoot(
    appRoot: URL,
    fileManager: FileManager = .default
  ) -> URL? {
    let candidates = [
      appRoot.appendingPathComponent("apps/server/dist/client", isDirectory: true),
      appRoot.appendingPathComponent("apps/web/dist", isDirectory: true),
    ]

    for candidate in candidates {
      let indexURL = candidate.appendingPathComponent("index.html", isDirectory: false)
      if fileManager.fileExists(atPath: indexURL.path) {
        return candidate
      }
    }

    return nil
  }

  public static func resolvePath(
    staticRoot: URL,
    requestURL: URL,
    fileManager: FileManager = .default
  ) -> DesktopStaticAssetResolution {
    let fallbackIndex = staticRoot.appendingPathComponent("index.html", isDirectory: false)
    let normalizedPath = normalizedRequestPath(for: requestURL)
    let requestIsAsset = isStaticAssetRequest(requestURL)

    guard normalizedPath.contains("..") == false else {
      return requestIsAsset ? .asset(fallbackIndex) : .document(fallbackIndex)
    }

    let requestedRelativePath = normalizedPath.isEmpty ? "index.html" : normalizedPath
    let candidate = staticRoot.appendingPathComponent(requestedRelativePath, isDirectory: false)

    if candidate.pathExtension.isEmpty == false {
      let resolved = candidate.standardizedFileURL
      if fileManager.fileExists(atPath: resolved.path), isInside(staticRoot: staticRoot, candidate: resolved) {
        return .asset(resolved)
      }
      return .asset(fallbackIndex)
    }

    let nestedIndex = candidate.appendingPathComponent("index.html", isDirectory: false)
    if fileManager.fileExists(atPath: nestedIndex.path), isInside(staticRoot: staticRoot, candidate: nestedIndex) {
      return .document(nestedIndex.standardizedFileURL)
    }

    return .document(fallbackIndex)
  }

  public static func isStaticAssetRequest(_ requestURL: URL) -> Bool {
    requestURL.pathExtension.isEmpty == false
  }

  private static func normalizedRequestPath(for requestURL: URL) -> String {
    let decoded = requestURL.path.removingPercentEncoding ?? requestURL.path
    return NSString.path(withComponents: decoded.split(separator: "/").map(String.init))
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }

  private static func isInside(staticRoot: URL, candidate: URL) -> Bool {
    let root = staticRoot.standardizedFileURL.path
    let child = candidate.standardizedFileURL.path
    return child == root || child.hasPrefix("\(root)/")
  }
}
