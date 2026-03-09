#if canImport(SwiftUI) && os(macOS)
import SwiftUI

@main
struct T3CodeMacOSApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
        .frame(minWidth: 960, minHeight: 640)
    }
    .windowResizability(.contentSize)
  }
}

private struct ContentView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("T3 Code for macOS")
        .font(.largeTitle.weight(.semibold))

      Text(
        "This workspace is the native Swift host for macOS. Electron stays in apps/desktop for Windows and Linux while the macOS app reaches feature parity."
      )
      .font(.body)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      VStack(alignment: .leading, spacing: 10) {
        Label("Native macOS window lifecycle and app shell", systemImage: "macwindow")
        Label("Shared backend and protocol layers stay in the existing monorepo packages", systemImage: "arrow.triangle.branch")
        Label("Electron desktop build remains available for non-macOS targets", systemImage: "shippingbox")
      }
      .font(.headline)

      Spacer()
    }
    .padding(24)
  }
}
#else
@main
struct T3CodeMacOSUnsupportedHost {
  static func main() {
    print("T3CodeMacOS builds a native app on macOS. This placeholder target is non-interactive on unsupported platforms.")
  }
}
#endif
