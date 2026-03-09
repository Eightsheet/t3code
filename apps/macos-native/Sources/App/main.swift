#if canImport(SwiftUI) && os(macOS)
import SwiftUI
import T3CodeMacOSRuntime

@main
struct T3CodeMacOSApp: App {
  private let bootstrap = DesktopRuntimeBootstrapper.prepareOrNil()

  var body: some Scene {
    WindowGroup {
      ContentView(bootstrap: bootstrap)
        .frame(minWidth: 960, minHeight: 640)
    }
    .windowResizability(.contentMinSize)
  }
}

private struct ContentView: View {
  let bootstrap: DesktopRuntimeConfiguration?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("T3 Code for macOS")
        .font(.largeTitle.weight(.semibold))

      Text(
        "Native runtime migration is underway. This Swift host now resolves backend launch configuration, login-shell PATH, rotating logs, and process control separately from the Electron shell."
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 10) {
        Label("Native runtime bootstrap for backend launch and auth handoff", systemImage: "bolt.horizontal.circle")
        Label("Rotating log sink and process supervision implemented in Swift", systemImage: "doc.text")
        Label("Electron remains available for Windows and Linux while macOS migrates", systemImage: "shippingbox")
      }
      .font(.headline)

      if let bootstrap {
        Divider()
        LabeledContent("Backend entry", value: bootstrap.paths.backendEntry.path)
        LabeledContent("State directory", value: bootstrap.paths.stateDirectory.path)
        LabeledContent("WebSocket URL", value: bootstrap.websocketURL.absoluteString)
      }

      Spacer()
    }
    .padding(24)
  }
}
#else
import Foundation
import T3CodeMacOSRuntime

@main
struct T3CodeMacOSUnsupportedHost {
  static func main() {
    let bootstrap = DesktopRuntimeBootstrapper.prepareOrNil()
    if let bootstrap {
      print("Prepared native macOS runtime bootstrap for \(bootstrap.paths.backendEntry.path)")
      print("WebSocket URL: \(bootstrap.websocketURL.absoluteString)")
      return
    }
    print("T3CodeMacOS builds a native app on macOS. This host can still exercise the runtime bootstrap on unsupported platforms.")
  }
}
#endif
