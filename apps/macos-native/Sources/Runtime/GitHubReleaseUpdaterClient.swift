#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import Foundation

public struct DesktopUpdateFeedConfiguration: Equatable, Sendable {
  public let provider: String
  public let owner: String
  public let repo: String

  public init(provider: String, owner: String, repo: String) {
    self.provider = provider
    self.owner = owner
    self.repo = repo
  }
}

public enum DesktopUpdateFeedConfigurationResolverError: Error, Equatable {
  case missingRepository
  case unsupportedProvider(String)
}

public enum DesktopUpdateFeedConfigurationResolver {
  public static func resolve(
    environment: [String: String],
    appRoot: URL,
    fileManager: FileManager = .default
  ) throws -> DesktopUpdateFeedConfiguration {
    let repositorySlug =
      environment["T3CODE_DESKTOP_UPDATE_REPOSITORY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? environment["GITHUB_REPOSITORY"]?.trimmingCharacters(in: .whitespacesAndNewlines)

    if let repositorySlug, repositorySlug.isEmpty == false {
      return try configuration(
        provider: "github",
        repositorySlug: repositorySlug
      )
    }

    let candidates = [
      environment["T3CODE_UPDATE_CONFIG_PATH"].map { URL(fileURLWithPath: $0, isDirectory: false) },
      appRoot.appendingPathComponent("app-update.yml", isDirectory: false),
      appRoot.appendingPathComponent("dev-app-update.yml", isDirectory: false),
    ].compactMap { $0 }

    for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
      let raw = try String(contentsOf: candidate, encoding: .utf8)
      let entries = parseSimpleYAML(raw)
      let provider = entries["provider"] ?? "github"
      let repositorySlug = entries["repo"].flatMap { repo in
        entries["owner"].map { owner in "\(owner)/\(repo)" }
      }
      guard let repositorySlug else {
        continue
      }
      return try configuration(provider: provider, repositorySlug: repositorySlug)
    }

    throw DesktopUpdateFeedConfigurationResolverError.missingRepository
  }

  private static func configuration(provider: String, repositorySlug: String) throws -> DesktopUpdateFeedConfiguration {
    guard provider == "github" else {
      throw DesktopUpdateFeedConfigurationResolverError.unsupportedProvider(provider)
    }
    let parts = repositorySlug.split(separator: "/", omittingEmptySubsequences: true)
    guard parts.count == 2, let owner = parts.first, let repo = parts.last else {
      throw DesktopUpdateFeedConfigurationResolverError.missingRepository
    }
    return DesktopUpdateFeedConfiguration(provider: provider, owner: String(owner), repo: String(repo))
  }

  private static func parseSimpleYAML(_ raw: String) -> [String: String] {
    var entries: [String: String] = [:]
    for line in raw.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.isEmpty == false,
        trimmed.hasPrefix("#") == false,
        let separator = trimmed.firstIndex(of: ":")
      else {
        continue
      }
      let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
      let value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
      entries[key] = value.replacingOccurrences(of: "\"", with: "")
    }
    return entries
  }
}

public protocol DesktopUpdateTransport: Sendable {
  func fetchData(from url: URL, headers: [String: String]) async throws -> Data
  func downloadData(
    from url: URL,
    headers: [String: String],
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> Data
}

public struct URLSessionDesktopUpdateTransport: DesktopUpdateTransport {
  public init() {}

  public func fetchData(from url: URL, headers: [String: String]) async throws -> Data {
    var request = URLRequest(url: url)
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response: response, url: url)
    return data
  }

  public func downloadData(
    from url: URL,
    headers: [String: String],
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> Data {
    let data = try await fetchData(from: url, headers: headers)
    progress(100)
    return data
  }

  private func validate(response: URLResponse, url: URL) throws {
    guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
      throw GitHubReleaseUpdaterClientError.httpFailure(url.absoluteString)
    }
  }
}

public protocol DesktopUpdateIntegrityVerifier: Sendable {
  func verify(fileURL: URL, expectedSHA512: String) throws
}

public struct ShellDesktopUpdateIntegrityVerifier: DesktopUpdateIntegrityVerifier {
  public init() {}

  public func verify(fileURL: URL, expectedSHA512: String) throws {
    let output = try computeDigest(fileURL: fileURL)
    guard output.caseInsensitiveCompare(expectedSHA512) == .orderedSame else {
      throw GitHubReleaseUpdaterClientError.integrityCheckFailed(fileURL.lastPathComponent)
    }
  }

  private func computeDigest(fileURL: URL) throws -> String {
    let candidates: [([String], URL)] = [
      (["-a", "512", fileURL.path], URL(fileURLWithPath: "/usr/bin/shasum", isDirectory: false)),
      ([fileURL.path], URL(fileURLWithPath: "/usr/bin/sha512sum", isDirectory: false)),
    ]

    for (arguments, executableURL) in candidates where FileManager.default.fileExists(atPath: executableURL.path) {
      let process = Process()
      let outputPipe = Pipe()
      process.executableURL = executableURL
      process.arguments = arguments
      process.standardOutput = outputPipe
      try process.run()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        continue
      }
      let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
      let output = String(decoding: data, as: UTF8.self)
      if let digest = output.split(whereSeparator: \.isWhitespace).first {
        return String(digest)
      }
    }

    throw GitHubReleaseUpdaterClientError.integrityToolUnavailable
  }
}

public protocol DesktopUpdateInstaller: Sendable {
  func install(fileURL: URL) throws
}

public struct OpenDesktopUpdateInstaller: DesktopUpdateInstaller {
  public init() {}

  public func install(fileURL: URL) throws {
#if os(macOS)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open", isDirectory: false)
    process.arguments = [fileURL.path]
    try process.run()
#else
    throw GitHubReleaseUpdaterClientError.installUnsupported
#endif
  }
}

public enum GitHubReleaseUpdaterClientError: Error, Equatable {
  case httpFailure(String)
  case invalidReleaseResponse
  case noManifestAsset
  case noDownloadableAsset
  case updateNotAvailable
  case integrityCheckFailed(String)
  case integrityToolUnavailable
  case installUnsupported
  case missingDownloadedUpdate
}

public actor GitHubReleaseUpdaterClient: DesktopUpdaterClient {
  public struct ReleaseAsset: Equatable, Sendable {
    public let name: String
    public let downloadURL: URL
    public let size: Int

    public init(name: String, downloadURL: URL, size: Int) {
      self.name = name
      self.downloadURL = downloadURL
      self.size = size
    }
  }

  public struct Release: Equatable, Sendable {
    public let version: String
    public let assets: [ReleaseAsset]
    public let manifest: DesktopUpdateManifest
    public let selectedAsset: ReleaseAsset

    public init(
      version: String,
      assets: [ReleaseAsset],
      manifest: DesktopUpdateManifest,
      selectedAsset: ReleaseAsset
    ) {
      self.version = version
      self.assets = assets
      self.manifest = manifest
      self.selectedAsset = selectedAsset
    }
  }

  private let feed: DesktopUpdateFeedConfiguration
  private let currentVersion: String
  private let runtimeInfo: DesktopRuntimeInfo
  private let environment: [String: String]
  private let appRoot: URL
  private let transport: DesktopUpdateTransport
  private let verifier: DesktopUpdateIntegrityVerifier
  private let installer: DesktopUpdateInstaller
  private let fileManager: FileManager
  private let downloadDirectory: URL
  private var release: Release?
  private var downloadedUpdateURL: URL?

  public init(
    feed: DesktopUpdateFeedConfiguration,
    currentVersion: String,
    runtimeInfo: DesktopRuntimeInfo,
    environment: [String: String],
    appRoot: URL,
    transport: DesktopUpdateTransport = URLSessionDesktopUpdateTransport(),
    verifier: DesktopUpdateIntegrityVerifier = ShellDesktopUpdateIntegrityVerifier(),
    installer: DesktopUpdateInstaller = OpenDesktopUpdateInstaller(),
    fileManager: FileManager = .default,
    downloadDirectory: URL? = nil
  ) {
    self.feed = feed
    self.currentVersion = currentVersion
    self.runtimeInfo = runtimeInfo
    self.environment = environment
    self.appRoot = appRoot
    self.transport = transport
    self.verifier = verifier
    self.installer = installer
    self.fileManager = fileManager
    self.downloadDirectory =
      downloadDirectory
      ?? fileManager.temporaryDirectory.appendingPathComponent("t3code-updates", isDirectory: true)
  }

  public init?(
    currentVersion: String,
    runtimeInfo: DesktopRuntimeInfo,
    environment: [String: String],
    appRoot: URL,
    transport: DesktopUpdateTransport = URLSessionDesktopUpdateTransport(),
    verifier: DesktopUpdateIntegrityVerifier = ShellDesktopUpdateIntegrityVerifier(),
    installer: DesktopUpdateInstaller = OpenDesktopUpdateInstaller(),
    fileManager: FileManager = .default,
    downloadDirectory: URL? = nil
  ) {
    guard let feed = try? DesktopUpdateFeedConfigurationResolver.resolve(
      environment: environment,
      appRoot: appRoot,
      fileManager: fileManager
    ) else {
      return nil
    }
    let resolvedDownloadDirectory =
      downloadDirectory
      ?? fileManager.temporaryDirectory.appendingPathComponent("t3code-updates", isDirectory: true)

    self.feed = feed
    self.currentVersion = currentVersion
    self.runtimeInfo = runtimeInfo
    self.environment = environment
    self.appRoot = appRoot
    self.transport = transport
    self.verifier = verifier
    self.installer = installer
    self.fileManager = fileManager
    self.downloadDirectory = resolvedDownloadDirectory
    self.release = nil
    self.downloadedUpdateURL = nil
  }

  public func checkForUpdates() async throws -> DesktopUpdateCheckResult {
    let resolvedRelease = try await fetchRelease()
    guard DesktopVersionComparator.isNewerVersion(resolvedRelease.version, than: currentVersion) else {
      release = nil
      downloadedUpdateURL = nil
      return .noUpdate
    }

    release = resolvedRelease
    return .updateAvailable(version: resolvedRelease.version)
  }

  public func downloadUpdate(
    progress: @escaping @Sendable (Double) -> Void
  ) async throws -> DesktopUpdateDownloadResult {
    let release = try await ensuredRelease()
    let assetURL = release.selectedAsset.downloadURL
    let payload = try await transport.downloadData(from: assetURL, headers: requestHeaders(), progress: progress)
    try fileManager.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
    let destinationURL = downloadDirectory.appendingPathComponent(release.selectedAsset.name, isDirectory: false)
    try payload.write(to: destinationURL, options: .atomic)
    let manifestFile = try selectedManifestFile(in: release.manifest, matching: release.selectedAsset.name)
    guard payload.count == manifestFile.size else {
      throw GitHubReleaseUpdaterClientError.httpFailure("Unexpected asset size for \(release.selectedAsset.name)")
    }
    try verifier.verify(fileURL: destinationURL, expectedSHA512: manifestFile.sha512)
    downloadedUpdateURL = destinationURL
    progress(100)
    return DesktopUpdateDownloadResult(version: release.version)
  }

  public func installUpdate() throws {
    guard let downloadedUpdateURL else {
      throw GitHubReleaseUpdaterClientError.missingDownloadedUpdate
    }
    try installer.install(fileURL: downloadedUpdateURL)
  }

  private func ensuredRelease() async throws -> Release {
    if let release {
      return release
    }
    switch try await checkForUpdates() {
    case .noUpdate:
      throw GitHubReleaseUpdaterClientError.updateNotAvailable
    case .updateAvailable:
      guard let release else {
        throw GitHubReleaseUpdaterClientError.updateNotAvailable
      }
      return release
    }
  }

  private func fetchRelease() async throws -> Release {
    let releaseMetadata = try await fetchLatestReleaseMetadata()
    guard let manifestAsset = releaseMetadata.first(where: { $0.name == "latest-mac.yml" }) else {
      throw GitHubReleaseUpdaterClientError.noManifestAsset
    }
    let manifestData = try await transport.fetchData(from: manifestAsset.downloadURL, headers: requestHeaders())
    let manifest = try DesktopUpdateManifestParser.parse(String(decoding: manifestData, as: UTF8.self))
    let selectedManifestFile = try selectManifestFile(from: manifest)
    let selectedAsset =
      releaseMetadata.first(where: { $0.name == selectedManifestFile.url })
      ?? ReleaseAsset(
        name: selectedManifestFile.url,
        downloadURL: fallbackReleaseDownloadURL(fileName: selectedManifestFile.url),
        size: selectedManifestFile.size
      )
    return Release(
      version: manifest.version,
      assets: releaseMetadata,
      manifest: manifest,
      selectedAsset: selectedAsset
    )
  }

  private func fetchLatestReleaseMetadata() async throws -> [ReleaseAsset] {
    let url = URL(string: "https://api.github.com/repos/\(feed.owner)/\(feed.repo)/releases/latest")!
    let data = try await transport.fetchData(from: url, headers: requestHeaders())
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let assets = object["assets"] as? [[String: Any]]
    else {
      throw GitHubReleaseUpdaterClientError.invalidReleaseResponse
    }

    let parsedAssets = assets.compactMap { asset -> ReleaseAsset? in
      guard let name = asset["name"] as? String,
        let downloadURLString = asset["browser_download_url"] as? String,
        let downloadURL = URL(string: downloadURLString),
        let size = asset["size"] as? Int
      else {
        return nil
      }
      return ReleaseAsset(name: name, downloadURL: downloadURL, size: size)
    }
    return parsedAssets
  }

  private func selectManifestFile(from manifest: DesktopUpdateManifest) throws -> DesktopUpdateManifestFile {
    let preferredArch =
      DesktopRuntimeInfoResolver.isArm64HostRunningIntelBuild(runtimeInfo) ? DesktopRuntimeArch.arm64 : runtimeInfo.appArch
    let zipFiles = manifest.files.filter { $0.url.hasSuffix(".zip") || $0.url.hasSuffix(".dmg") }

    if let matched = zipFiles.first(where: { $0.url.localizedCaseInsensitiveContains(preferredArch.rawValue) }) {
      return matched
    }
    if let first = zipFiles.first {
      return first
    }
    throw GitHubReleaseUpdaterClientError.noDownloadableAsset
  }

  private func selectedManifestFile(in manifest: DesktopUpdateManifest, matching assetName: String) throws -> DesktopUpdateManifestFile {
    guard let file = manifest.files.first(where: { $0.url == assetName }) else {
      throw GitHubReleaseUpdaterClientError.noDownloadableAsset
    }
    return file
  }

  private func fallbackReleaseDownloadURL(fileName: String) -> URL {
    URL(string: "https://github.com/\(feed.owner)/\(feed.repo)/releases/latest/download/\(fileName)")!
  }

  private func requestHeaders() -> [String: String] {
    let token =
      environment["T3CODE_DESKTOP_UPDATE_GITHUB_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? environment["GH_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? ""
    var headers = [
      "Accept": "application/vnd.github+json",
      "User-Agent": "T3CodeMacOSRuntime",
    ]
    if token.isEmpty == false {
      headers["Authorization"] = "Bearer \(token)"
    }
    return headers
  }
}
