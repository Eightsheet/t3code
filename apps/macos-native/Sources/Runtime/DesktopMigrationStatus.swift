import Foundation

/// Describes the current state of the native macOS rewrite so the app and fallback
/// host can show which responsibilities already moved into Swift and which major
/// Electron-owned features are still missing before the macOS app is complete.
public struct DesktopMigrationStatus: Equatable, Sendable {
  public let nativeComponents: [String]
  public let missingForFullApp: [String]
  public let hasStartedSwiftUI: Bool

  public init(
    nativeComponents: [String],
    missingForFullApp: [String],
    hasStartedSwiftUI: Bool
  ) {
    self.nativeComponents = nativeComponents
    self.missingForFullApp = missingForFullApp
    self.hasStartedSwiftUI = hasStartedSwiftUI
  }

  public var headline: String {
    if nativeComponents.isEmpty {
      return "The macOS app has not started moving important runtime work into Swift yet."
    }
    if missingForFullApp.isEmpty {
      return "The macOS app runtime has been rewritten in Swift and is ready as a fully functional native app."
    }
    return "The macOS app has started moving important runtime work into Swift, but it is not fully rewritten or feature-complete yet."
  }

  public var swiftUIStatus: String {
    hasStartedSwiftUI
      ? "SwiftUI has started: the macOS app already boots through a native SwiftUI App and WindowGroup shell."
      : "SwiftUI has not started yet."
  }

  /// Keep this snapshot in sync when major Electron-owned responsibilities move into
  /// the native macOS workspace so the app and README continue to describe the
  /// current migration state accurately.
  public static let current = DesktopMigrationStatus(
    nativeComponents: [
      "App startup/bootstrap configuration in Swift",
      "Backend path and state directory resolution in Swift",
      "Login-shell PATH resolution in Swift",
      "Loopback port reservation and auth token generation in Swift",
      "Backend process launch/supervision in Swift",
      "Rotating desktop/backend logging in Swift",
      "Packaged stdout/stderr log capture in Swift",
      "App identity, commit metadata, and user-data path resolution in Swift",
      "Secure static asset bundle resolution in Swift",
      "Desktop update state machine and polling orchestration in Swift",
      "GitHub release manifest parsing, download, and install handoff in Swift",
      "Backend lifecycle restart/shutdown orchestration in Swift",
    ],
    missingForFullApp: [
      "Native renderer UI for sessions, conversations, and event streaming",
      "Native WebSocket/client orchestration instead of relying on the existing web app surface",
      "App menus, dialogs, folder pickers, and context menus in native macOS APIs",
      "Deep-link/protocol handling and full window lifecycle parity",
      "Feature parity validation against the existing Electron desktop app",
    ],
    hasStartedSwiftUI: true
  )
}
