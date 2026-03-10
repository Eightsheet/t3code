#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
  @ObservedObject var store: AppStore
  @Environment(\.dismiss) private var dismiss
  @State private var newModelSlug = ""
  @State private var modelError: String?

  var body: some View {
    NavigationStack {
      Form {
        // MARK: Appearance
        Section("Appearance") {
          Picker("Theme", selection: $store.settings.theme) {
            Text("System").tag(AppTheme.system)
            Text("Light").tag(AppTheme.light)
            Text("Dark").tag(AppTheme.dark)
          }
          .pickerStyle(.segmented)

          HStack {
            Text("Active theme")
              .font(T3Design.Fonts.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Text(resolvedThemeName)
              .font(T3Design.Fonts.caption)
              .foregroundStyle(.tertiary)
          }
        }

        // MARK: Codex App Server
        Section("Codex App Server") {
          VStack(alignment: .leading, spacing: T3Design.Spacing.xs) {
            Text("Binary path override")
              .font(T3Design.Fonts.caption)
              .foregroundStyle(.secondary)
            TextField("Defaults to codex in PATH", text: Binding(
              get: { store.settings.codexBinaryPath ?? "" },
              set: { store.settings.codexBinaryPath = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(T3Design.Fonts.code)
          }

          VStack(alignment: .leading, spacing: T3Design.Spacing.xs) {
            Text("CODEX_HOME directory")
              .font(T3Design.Fonts.caption)
              .foregroundStyle(.secondary)
            TextField("Leave empty for default", text: Binding(
              get: { store.settings.codexHomePath ?? "" },
              set: { store.settings.codexHomePath = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(T3Design.Fonts.code)
          }

          Button("Reset to Defaults") {
            store.settings.codexBinaryPath = nil
            store.settings.codexHomePath = nil
          }
          .font(T3Design.Fonts.caption)
          .foregroundStyle(.secondary)
        }

        // MARK: Models
        Section("Models") {
          Picker("Default service tier", selection: $store.settings.defaultServiceTier) {
            Label("Standard", systemImage: "circle").tag("standard")
            Label("Fast ⚡", systemImage: "bolt").tag("fast")
          }

          VStack(alignment: .leading, spacing: T3Design.Spacing.sm) {
            Text("Custom model slugs")
              .font(T3Design.Fonts.caption)
              .foregroundStyle(.secondary)

            ForEach(store.settings.customModelSlugs, id: \.self) { slug in
              HStack {
                Text(slug)
                  .font(T3Design.Fonts.code)
                Spacer()
                Button {
                  store.settings.customModelSlugs.removeAll { $0 == slug }
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
              }
            }

            HStack(spacing: T3Design.Spacing.sm) {
              TextField("Model slug", text: $newModelSlug)
                .textFieldStyle(.roundedBorder)
                .font(T3Design.Fonts.code)
                .onSubmit { addCustomModel() }

              Button("Add") { addCustomModel() }
                .disabled(newModelSlug.isEmpty)
            }

            if let error = modelError {
              Text(error)
                .font(T3Design.Fonts.caption)
                .foregroundStyle(T3Design.errorRed)
            }
          }

          if !store.settings.customModelSlugs.isEmpty {
            Button("Reset Custom Models") {
              store.settings.customModelSlugs = []
            }
            .font(T3Design.Fonts.caption)
            .foregroundStyle(.secondary)
          }
        }

        // MARK: Responses
        Section("Responses") {
          Toggle("Stream assistant messages", isOn: $store.settings.streamAssistantMessages)
            .font(T3Design.Fonts.body)

          HStack {
            Text("Shows token-by-token output as the model generates")
              .font(T3Design.Fonts.caption)
              .foregroundStyle(.tertiary)
            Spacer()
            Button("Restore Default") {
              store.settings.streamAssistantMessages = true
            }
            .font(T3Design.Fonts.caption)
            .foregroundStyle(.secondary)
          }
        }

        // MARK: Keybindings
        Section("Keybindings") {
          HStack {
            Text("Configuration")
              .font(T3Design.Fonts.body)
            Spacer()
            Button("Open keybindings.json") {
              openKeybindingsFile()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
          }

          VStack(alignment: .leading, spacing: T3Design.Spacing.xs) {
            keybindingRow("New Thread", shortcut: "⌘N")
            keybindingRow("Settings", shortcut: "⌘,")
            keybindingRow("Close Tab", shortcut: "⌘W")
            keybindingRow("Toggle Sidebar", shortcut: "⌘⇧L")
          }
        }

        // MARK: Safety
        Section("Safety") {
          Toggle("Confirm thread deletion", isOn: $store.settings.confirmThreadDelete)
            .font(T3Design.Fonts.body)

          HStack {
            Text("Ask before permanently deleting threads")
              .font(T3Design.Fonts.caption)
              .foregroundStyle(.tertiary)
            Spacer()
            Button("Restore Default") {
              store.settings.confirmThreadDelete = true
            }
            .font(T3Design.Fonts.caption)
            .foregroundStyle(.secondary)
          }
        }

        // MARK: Connection
        Section("Connection") {
          connectionStatus
        }

        // MARK: Runtime
        Section("Runtime") {
          runtimeInfo
        }

        // MARK: About
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
    .frame(width: 520, height: 700)
  }

  // MARK: - Existing sections

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
      LabeledContent("Threads", value: "\(store.threads.filter { $0.deletedAt == nil }.count)")
      LabeledContent("Projects", value: "\(store.activeProjects.count)")
      LabeledContent("State Synced", value: store.isHydrated ? "Yes (seq \(store.snapshotSequence))" : "No")
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

  // MARK: - Helpers

  private var resolvedThemeName: String {
    switch store.settings.theme {
    case .system:
      let appearance = NSApp.effectiveAppearance
      return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "Dark (System)" : "Light (System)"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }

  private func addCustomModel() {
    let slug = newModelSlug.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !slug.isEmpty else { return }
    guard slug.count <= 256 else {
      modelError = "Model slug must be 256 characters or fewer"
      return
    }
    guard !store.settings.customModelSlugs.contains(slug) else {
      modelError = "Model already added"
      return
    }
    let builtInModels = ["codex", "o4-mini", "o3", "gpt-4.1"]
    guard !builtInModels.contains(slug) else {
      modelError = "This is a built-in model"
      return
    }
    store.settings.customModelSlugs.append(slug)
    newModelSlug = ""
    modelError = nil
  }

  private func keybindingRow(_ label: String, shortcut: String) -> some View {
    HStack {
      Text(label)
        .font(T3Design.Fonts.body)
      Spacer()
      Text(shortcut)
        .font(T3Design.Fonts.code)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(T3Design.Colors.surface, in: RoundedRectangle(cornerRadius: 4))
        .overlay(
          RoundedRectangle(cornerRadius: 4)
            .strokeBorder(T3Design.Colors.border.opacity(0.3), lineWidth: 0.5)
        )
    }
  }

  private func openKeybindingsFile() {
    let configDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/t3code")
    let keybindingsFile = configDir.appendingPathComponent("keybindings.json")

    if !FileManager.default.fileExists(atPath: keybindingsFile.path) {
      try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
      try? "{}".write(to: keybindingsFile, atomically: true, encoding: .utf8)
    }

    NSWorkspace.shared.open(keybindingsFile)
  }
}
#endif
