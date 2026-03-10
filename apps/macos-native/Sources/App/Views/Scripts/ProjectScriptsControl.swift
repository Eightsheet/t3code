#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Project Scripts Control

struct ProjectScriptsControl: View {
  @ObservedObject var store: AppStore
  let project: OrchestrationProject
  @State private var showAddScript = false
  @State private var editingScript: ProjectScript?
  @State private var showDeleteConfirm = false
  @State private var pendingDeleteScriptId: String?

  var body: some View {
    Menu {
      ForEach(project.scripts) { script in
        Button {
          runScript(script)
        } label: {
          Label(script.name, systemImage: ScriptIcon(rawValue: script.icon)?.systemImage ?? "play.fill")
        }
      }

      Divider()

      Button {
        showAddScript = true
      } label: {
        Label("Add Script…", systemImage: "plus.circle")
      }

      if !project.scripts.isEmpty {
        Menu("Edit Scripts") {
          ForEach(project.scripts) { script in
            Button {
              editingScript = script
              showAddScript = true
            } label: {
              Label("Edit \(script.name)", systemImage: "pencil")
            }
          }
        }

        Menu("Delete Scripts") {
          ForEach(project.scripts) { script in
            Button(role: .destructive) {
              pendingDeleteScriptId = script.id
              showDeleteConfirm = true
            } label: {
              Label("Delete \(script.name)", systemImage: "trash")
            }
          }
        }
      }
    } label: {
      Label("Scripts", systemImage: "play.rectangle")
        .font(T3Design.Fonts.caption)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .sheet(isPresented: $showAddScript) {
      ScriptEditorSheet(
        store: store,
        project: project,
        existingScript: editingScript,
        onDismiss: {
          showAddScript = false
          editingScript = nil
        }
      )
    }
    .alert("Delete Script?", isPresented: $showDeleteConfirm) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        if let scriptId = pendingDeleteScriptId {
          Task { await store.deleteScript(projectId: project.id, scriptId: scriptId) }
        }
      }
    } message: {
      Text("This cannot be undone.")
    }
  }

  private func runScript(_ script: ProjectScript) {
    store.addToast(.info("Running \(script.name)…"))
  }
}

// MARK: - Script Editor Sheet

struct ScriptEditorSheet: View {
  @ObservedObject var store: AppStore
  let project: OrchestrationProject
  let existingScript: ProjectScript?
  let onDismiss: () -> Void

  @State private var name = ""
  @State private var command = ""
  @State private var selectedIcon = "play"
  @State private var runOnCreate = false

  private let iconOptions = ["play", "test", "lint", "build", "debug", "configure"]

  var body: some View {
    VStack(spacing: T3Design.Spacing.lg) {
      Text(existingScript != nil ? "Edit Script" : "Add Script")
        .font(T3Design.Fonts.headline)

      VStack(alignment: .leading, spacing: T3Design.Spacing.md) {
        // Name
        VStack(alignment: .leading, spacing: T3Design.Spacing.xs) {
          Text("Name")
            .font(T3Design.Fonts.caption)
            .foregroundStyle(.secondary)
          TextField("Script name", text: $name)
            .textFieldStyle(.roundedBorder)
        }

        // Command
        VStack(alignment: .leading, spacing: T3Design.Spacing.xs) {
          Text("Command")
            .font(T3Design.Fonts.caption)
            .foregroundStyle(.secondary)
          TextField("npm test", text: $command)
            .textFieldStyle(.roundedBorder)
            .font(T3Design.Fonts.code)
        }

        // Icon picker
        VStack(alignment: .leading, spacing: T3Design.Spacing.xs) {
          Text("Icon")
            .font(T3Design.Fonts.caption)
            .foregroundStyle(.secondary)

          HStack(spacing: T3Design.Spacing.sm) {
            ForEach(iconOptions, id: \.self) { icon in
              Button {
                selectedIcon = icon
              } label: {
                Image(systemName: ScriptIcon(rawValue: icon)?.systemImage ?? "play.fill")
                  .font(.system(size: 16))
                  .frame(width: 36, height: 36)
                  .background(
                    selectedIcon == icon
                      ? T3Design.accentPurple.opacity(0.15)
                      : T3Design.Colors.surface,
                    in: RoundedRectangle(cornerRadius: T3Design.Radius.sm)
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: T3Design.Radius.sm)
                      .strokeBorder(
                        selectedIcon == icon ? T3Design.accentPurple : Color.clear,
                        lineWidth: 1
                      )
                  )
              }
              .buttonStyle(.plain)
            }
          }
        }

        // Run on worktree create
        Toggle("Run when worktree is created", isOn: $runOnCreate)
          .font(T3Design.Fonts.body)
      }

      HStack {
        Button("Cancel") { onDismiss() }
          .keyboardShortcut(.cancelAction)

        Spacer()

        Button(existingScript != nil ? "Save" : "Add") {
          Task {
            if let script = existingScript {
              await store.updateScript(
                projectId: project.id, scriptId: script.id, name: name, command: command,
                icon: selectedIcon, runOnCreate: runOnCreate)
            } else {
              await store.addScript(
                projectId: project.id, name: name, command: command,
                icon: selectedIcon, runOnCreate: runOnCreate)
            }
            onDismiss()
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(name.isEmpty || command.isEmpty)
      }
    }
    .padding(T3Design.Spacing.xl)
    .frame(width: 400)
    .onAppear {
      if let script = existingScript {
        name = script.name
        command = script.command
        selectedIcon = script.icon
        runOnCreate = script.runOnWorktreeCreate
      }
    }
  }
}
#endif
