#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import T3CodeMacOSRuntime

@main
struct T3CodeMacOSApp: App {
  private let bootstrap = DesktopRuntimeBootstrapper.prepareOrNil()
  private let status = DesktopMigrationStatus.current
  private let runtimeInfo = DesktopRuntimeInfoResolver.current()
  private let metadata = AppPreviewContext.current.metadata
  private let staticRoot = AppPreviewContext.current.staticRoot
  private let updateAvailability = AppPreviewContext.current.updateAvailability

  var body: some Scene {
    WindowGroup {
      ContentView(
        bootstrap: bootstrap,
        status: status,
        runtimeInfo: runtimeInfo,
        metadata: metadata,
        staticRoot: staticRoot,
        updateAvailability: updateAvailability
      )
        .frame(minWidth: 960, minHeight: 640)
    }
    .windowResizability(.contentMinSize)
  }
}

private struct ContentView: View {
  let bootstrap: DesktopRuntimeConfiguration?
  let status: DesktopMigrationStatus
  let runtimeInfo: DesktopRuntimeInfo
  let metadata: DesktopAppMetadata?
  let staticRoot: URL?
  let updateAvailability: String?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("T3 Code for macOS")
          .font(.largeTitle.weight(.semibold))

        Text(status.headline)
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        StatusCard(
          title: "Already native in Swift",
          systemImage: "checkmark.circle",
          items: status.nativeComponents
        )

        StatusCard(
          title: "Still missing before this is a fully functional native app",
          systemImage: "exclamationmark.triangle",
          items: status.missingForFullApp
        )

        Label(status.swiftUIStatus, systemImage: "swift")
          .font(.headline)

        Divider()
        Text("Current runtime foundation preview")
          .font(.title3.weight(.semibold))
        LabeledContent("Runtime host arch", value: runtimeInfo.hostArch.rawValue)
        LabeledContent("Runtime app arch", value: runtimeInfo.appArch.rawValue)
        if let metadata {
          LabeledContent("Display name", value: metadata.displayName)
          LabeledContent("User data directory", value: metadata.userDataDirectory.path)
          LabeledContent("Commit hash", value: metadata.commitHash ?? "unavailable")
        }
        LabeledContent("Static bundle root", value: staticRoot?.path ?? "unavailable")
        LabeledContent("Auto-update readiness", value: updateAvailability ?? "ready for packaged production builds")

        if let bootstrap {
          Divider()
          Text("Current bootstrap preview")
            .font(.title3.weight(.semibold))
          LabeledContent("Backend entry", value: bootstrap.paths.backendEntry.path)
          LabeledContent("State directory", value: bootstrap.paths.stateDirectory.path)
          LabeledContent("WebSocket URL", value: bootstrap.websocketURL.absoluteString)
        } else {
          Label(
            "Bootstrap preview is unavailable in this launch context, but the Swift runtime module is still part of the native app.",
            systemImage: "info.circle"
          )
          .foregroundStyle(.secondary)
        }
      }
      .padding(24)
    }
  }
}

private struct StatusCard: View {
  let title: String
  let systemImage: String
  let items: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: systemImage)
        .font(.title3.weight(.semibold))

      ForEach(items, id: \.self) { item in
        Label(item, systemImage: "circle.fill")
          .font(.body)
          .symbolRenderingMode(.hierarchical)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}
#else
import Foundation
import T3CodeMacOSRuntime

@main
struct T3CodeMacOSUnsupportedHost {
  static func main() {
    let status = DesktopMigrationStatus.current
    let bootstrap = DesktopRuntimeBootstrapper.prepareOrNil()
    let runtimeInfo = DesktopRuntimeInfoResolver.current()
    let previewContext = AppPreviewContext.current
    print(status.headline)
    print(status.swiftUIStatus)
    print("")
    print("Already native in Swift:")
    for item in status.nativeComponents {
      print("- \(item)")
    }
    print("")
    print("Still missing before the app is fully functional:")
    for item in status.missingForFullApp {
      print("- \(item)")
    }
    print("")
    print("Runtime foundation preview:")
    print("- host arch: \(runtimeInfo.hostArch.rawValue)")
    print("- app arch: \(runtimeInfo.appArch.rawValue)")
    if let metadata = previewContext.metadata {
      print("- display name: \(metadata.displayName)")
      print("- user data directory: \(metadata.userDataDirectory.path)")
      print("- commit hash: \(metadata.commitHash ?? "unavailable")")
    }
    print("- static bundle root: \(previewContext.staticRoot?.path ?? "unavailable")")
    print("- auto-update readiness: \(previewContext.updateAvailability ?? "ready for packaged production builds")")
    if let bootstrap {
      print("")
      print("Prepared native macOS runtime bootstrap for \(bootstrap.paths.backendEntry.path)")
      print("WebSocket URL: \(bootstrap.websocketURL.absoluteString)")
    } else {
      print("")
      print("Bootstrap preview is unavailable in this launch context, but the Swift runtime module is still part of the native app.")
    }
  }
}
#endif

private struct AppPreviewContext {
  let metadata: DesktopAppMetadata?
  let staticRoot: URL?
  let updateAvailability: String?

  static let current: AppPreviewContext = {
    let environment = ProcessInfo.processInfo.environment
    let bootstrap = DesktopRuntimeBootstrapper.prepareOrNil(environment: environment)
    let appRoot = bootstrap?.paths.appRoot
      ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    let metadata = DesktopAppMetadataResolver.resolve(
      environment: environment,
      currentVersion: AppPreviewContext.currentVersion(),
      isDevelopment: environment["VITE_DEV_SERVER_URL"] != nil,
      isPackaged: AppPreviewContext.isPackagedBuild(),
      platformIdentifier: AppPreviewContext.platformIdentifier(),
      appRoot: appRoot
    )
    let updateAvailability = DesktopUpdatePolicy.disabledReason(
      for: DesktopUpdateEnvironment(
        isDevelopment: environment["VITE_DEV_SERVER_URL"] != nil,
        isPackaged: AppPreviewContext.isPackagedBuild(),
        platformIdentifier: AppPreviewContext.platformIdentifier(),
        appImagePath: environment["APPIMAGE"],
        disabledByEnvironment: environment["T3CODE_DISABLE_AUTO_UPDATE"] == "1"
      )
    )
    return AppPreviewContext(
      metadata: metadata,
      staticRoot: DesktopStaticAssetResolver.resolveStaticRoot(appRoot: appRoot),
      updateAvailability: updateAvailability
    )
  }()

  private static func currentVersion() -> String {
    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      version.isEmpty == false
    {
      return version
    }
    return ProcessInfo.processInfo.environment["T3CODE_APP_VERSION"] ?? "0.0.0-dev"
  }

  private static func isPackagedBuild() -> Bool {
    Bundle.main.bundleURL.pathExtension == "app"
  }

  private static func platformIdentifier() -> String {
#if os(macOS)
    return "darwin"
#elseif os(Linux)
    return "linux"
#elseif os(Windows)
    return "win32"
#else
    return "other"
#endif
  }
}
