#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import T3CodeMacOSRuntime

@main
struct T3CodeMacOSApp: App {
  private let bootstrap = DesktopRuntimeBootstrapper.prepareOrNil()
  private let status = DesktopMigrationStatus.current

  var body: some Scene {
    WindowGroup {
      ContentView(bootstrap: bootstrap, status: status)
        .frame(minWidth: 960, minHeight: 640)
    }
    .windowResizability(.contentMinSize)
  }
}

private struct ContentView: View {
  let bootstrap: DesktopRuntimeConfiguration?
  let status: DesktopMigrationStatus

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
