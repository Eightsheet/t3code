#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
  @ObservedObject var store: AppStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Connection") {
          connectionStatus
        }

        Section("Runtime") {
          runtimeInfo
        }

        Section("About") {
          aboutInfo
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Settings")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
    .frame(width: 480, height: 400)
  }

  private var connectionStatus: some View {
    Group {
      HStack {
        Text("Server")
        Spacer()
        switch store.transport.connectionState {
        case .connected:
          Label("Connected", systemImage: "checkmark.circle.fill")
            .foregroundStyle(T3Design.successGreen)
        case .connecting:
          Label("Connecting…", systemImage: "arrow.triangle.2.circlepath")
            .foregroundStyle(T3Design.warningAmber)
        case .reconnecting(let attempt):
          Label("Reconnecting (\(attempt))", systemImage: "arrow.triangle.2.circlepath")
            .foregroundStyle(T3Design.warningAmber)
        case .disconnected:
          Label("Disconnected", systemImage: "xmark.circle.fill")
            .foregroundStyle(T3Design.errorRed)
        }
      }

      if let welcome = store.transport.welcomePayload {
        LabeledContent("Project", value: welcome.projectName)
        LabeledContent("Working Directory", value: welcome.cwd)
      }
    }
    .font(T3Design.Fonts.body)
  }

  private var runtimeInfo: some View {
    Group {
      LabeledContent("Threads", value: "\(store.threads.count)")
      LabeledContent("Projects", value: "\(store.projects.count)")
      LabeledContent("State Synced", value: store.isHydrated ? "Yes" : "No")
    }
    .font(T3Design.Fonts.body)
  }

  private var aboutInfo: some View {
    Group {
      LabeledContent("App", value: "T3 Code for macOS")
      LabeledContent("Engine", value: "Native SwiftUI")
    }
    .font(T3Design.Fonts.body)
  }
}
#endif
