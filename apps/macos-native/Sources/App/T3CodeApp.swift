#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI
import T3CodeMacOSRuntime

@main
struct T3CodeMacOSApp: App {
  @StateObject private var runtimeModel = DesktopRuntimeModel()
  @StateObject private var appStore = AppStore()
  @State private var showSettings = false

  var body: some Scene {
    WindowGroup {
      MainLayout(store: appStore, runtimeModel: runtimeModel)
        .frame(minWidth: 840, minHeight: 620)
        .task {
          await runtimeModel.start()
          if let wsURL = runtimeModel.snapshot.websocketURL {
            appStore.connectToBackend(url: wsURL)
          }
        }
        .onChange(of: runtimeModel.snapshot.websocketURL) { _, newURL in
          if let url = newURL {
            appStore.connectToBackend(url: url)
          }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
          appStore.transport.disconnect()
          runtimeModel.stop()
        }
        .sheet(isPresented: $showSettings) {
          SettingsView(store: appStore)
        }
    }
    .windowResizability(.contentMinSize)
    .windowToolbarStyle(.unified(showsTitle: false))
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Thread") {
          Task {
            guard let project = appStore.activeProjects.first else { return }
            _ = await appStore.createThread(projectId: project.id)
          }
        }
        .keyboardShortcut("n", modifiers: .command)
      }

      CommandGroup(after: .appSettings) {
        Button("Settings…") { showSettings = true }
          .keyboardShortcut(",", modifiers: .command)
      }
    }
  }
}

// MARK: - Main Layout

struct MainLayout: View {
  @ObservedObject var store: AppStore
  @ObservedObject var runtimeModel: DesktopRuntimeModel

  var body: some View {
    NavigationSplitView {
      ThreadSidebar(store: store)
        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
    } detail: {
      if let thread = store.selectedThread {
        ChatView(store: store, thread: thread)
          .id(thread.id)
      } else if runtimeModel.snapshot.lifecycle == .running || store.isHydrated {
        EmptyStateView(store: store)
      } else {
        startupView
      }
    }
    .navigationSplitViewStyle(.balanced)
  }

  private var startupView: some View {
    VStack(spacing: T3Design.Spacing.xl) {
      ProgressView()
        .scaleEffect(1.2)

      VStack(spacing: T3Design.Spacing.sm) {
        Text("Starting T3 Code…")
          .font(T3Design.Fonts.headline)

        Text(runtimeModel.snapshot.message ?? runtimeModel.snapshot.lifecycle.rawValue)
          .font(T3Design.Fonts.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Runtime Model

@MainActor
final class DesktopRuntimeModel: ObservableObject {
  @Published private(set) var snapshot = DesktopRuntimeSessionSnapshot(
    lifecycle: .idle,
    message: nil,
    restartAttempt: 0,
    websocketURL: nil,
    backendEntry: nil,
    updateState: nil
  )

  private let session: DesktopRuntimeSession?
  private var hasStarted = false

  init() {
    if let options = AppPreviewContext.current.runtimeSessionOptions {
      session = DesktopRuntimeSession(options: options)
      Task { [weak self] in
        await self?.session?.setOnStateChanged { snapshot in
          Task { @MainActor in
            self?.snapshot = snapshot
          }
        }
      }
    } else {
      session = nil
    }
  }

  func start() async {
    guard hasStarted == false, let session else { return }
    hasStarted = true
    await session.start()
    snapshot = await session.currentSnapshot()
  }

  func stop() {
    guard let session else { return }
    Task { await session.stop() }
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
    let runtimeSessionOptions = AppPreviewContext.current.runtimeSessionOptions
    print(status.headline)
    print(status.swiftUIStatus)
    print("")
    print("Already native in Swift:")
    for item in status.nativeComponents { print("- \(item)") }
    print("")
    print("Still missing before the app is fully functional:")
    for item in status.missingForFullApp { print("- \(item)") }
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
    print("- runtime session orchestration: \(runtimeSessionOptions == nil ? "unavailable in this launch context" : "native runtime session available")")
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
  let runtimeSessionOptions: DesktopRuntimeSessionOptions?

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
    let updateEnvironment = DesktopUpdateEnvironment(
      isDevelopment: environment["VITE_DEV_SERVER_URL"] != nil,
      isPackaged: AppPreviewContext.isPackagedBuild(),
      platformIdentifier: AppPreviewContext.platformIdentifier(),
      appImagePath: environment["APPIMAGE"],
      disabledByEnvironment: environment["T3CODE_DISABLE_AUTO_UPDATE"] == "1"
    )
    let updateAvailability = DesktopUpdatePolicy.disabledReason(for: updateEnvironment)
    return AppPreviewContext(
      metadata: metadata,
      staticRoot: DesktopStaticAssetResolver.resolveStaticRoot(appRoot: appRoot),
      updateAvailability: updateAvailability,
      runtimeSessionOptions: DesktopRuntimeSessionOptions(
        environment: environment,
        currentVersion: AppPreviewContext.currentVersion(),
        runtimeInfo: DesktopRuntimeInfoResolver.current(),
        updateEnvironment: updateEnvironment,
        currentDirectoryURL: appRoot,
        shouldEnablePackagedLogging: AppPreviewContext.isPackagedBuild()
      )
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
