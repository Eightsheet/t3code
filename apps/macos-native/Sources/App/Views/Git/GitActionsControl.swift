#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Branch Toolbar

struct BranchToolbar: View {
  @ObservedObject var store: AppStore
  let thread: OrchestrationThread
  @State private var showBranchPicker = false

  private var gitStatus: GitStatus? {
    store.gitStatusByThread[thread.id]
  }

  var body: some View {
    HStack(spacing: T3Design.Spacing.sm) {
      // Branch selector
      Button {
        showBranchPicker = true
        Task { await store.fetchGitBranches(for: thread.id) }
      } label: {
        HStack(spacing: T3Design.Spacing.xs) {
          Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 10))
          Text(thread.branch ?? gitStatus?.branch ?? "main")
            .font(T3Design.Fonts.codeSmall)
            .lineLimit(1)
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .popover(isPresented: $showBranchPicker) {
        branchPickerPopover
      }

      // Ahead/behind indicators
      if let status = gitStatus {
        if status.ahead > 0 {
          Label("\(status.ahead)", systemImage: "arrow.up")
            .font(T3Design.Fonts.codeSmall)
            .foregroundStyle(T3Design.infoBlue)
        }
        if status.behind > 0 {
          Label("\(status.behind)", systemImage: "arrow.down")
            .font(T3Design.Fonts.codeSmall)
            .foregroundStyle(T3Design.warningAmber)
        }
      }

      // PR status
      if let prState = gitStatus?.prState {
        prStatusBadge(prState)
      }

      // Worktree indicator
      if thread.worktreePath != nil {
        Label("Worktree", systemImage: "folder.badge.gearshape")
          .font(T3Design.Fonts.codeSmall)
          .foregroundStyle(.secondary)
      }
    }
    .task {
      await store.fetchGitStatus(for: thread.id)
    }
  }

  @ViewBuilder
  private func prStatusBadge(_ state: GitPRState) -> some View {
    let (color, icon) = prStateStyle(state)
    HStack(spacing: 3) {
      Image(systemName: icon)
        .font(.system(size: 9))
      Text("PR")
        .font(T3Design.Fonts.codeSmall)
    }
    .foregroundStyle(color)
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
    .background(color.opacity(0.1), in: Capsule())
    .onTapGesture {
      if let url = gitStatus?.prUrl, let nsURL = URL(string: url) {
        NSWorkspace.shared.open(nsURL)
      }
    }
  }

  private func prStateStyle(_ state: GitPRState) -> (Color, String) {
    switch state {
    case .open: (T3Design.successGreen, "arrow.triangle.pull")
    case .merged: (T3Design.accentPurple, "arrow.triangle.merge")
    case .closed: (.secondary, "xmark.circle")
    }
  }

  private var branchPickerPopover: some View {
    VStack(spacing: 0) {
      Text("Switch Branch")
        .font(T3Design.Fonts.bodyMedium)
        .padding(T3Design.Spacing.md)

      Divider()

      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(store.gitBranches) { branch in
            Button {
              Task {
                await store.gitCheckoutBranch(threadId: thread.id, branch: branch.name)
                showBranchPicker = false
              }
            } label: {
              HStack {
                Text(branch.name)
                  .font(T3Design.Fonts.code)
                  .lineLimit(1)
                Spacer()
                if branch.isCurrent {
                  Image(systemName: "checkmark")
                    .font(.system(size: 10))
                    .foregroundStyle(T3Design.accentPurple)
                }
                if branch.isDefault {
                  Text("default")
                    .font(T3Design.Fonts.codeSmall)
                    .foregroundStyle(.tertiary)
                }
              }
              .padding(.horizontal, T3Design.Spacing.md)
              .padding(.vertical, T3Design.Spacing.sm)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
      .frame(width: 260, maxHeight: 300)
    }
  }
}

// MARK: - Git Actions Control

struct GitActionsControl: View {
  @ObservedObject var store: AppStore
  let thread: OrchestrationThread
  @State private var showCommitDialog = false
  @State private var commitMessage = ""
  @State private var showDefaultBranchWarning = false
  @State private var pendingAction: (() async -> Void)?

  private var gitStatus: GitStatus? {
    store.gitStatusByThread[thread.id]
  }

  private var primaryAction: GitAction? {
    guard let status = gitStatus else { return nil }
    if status.hasChanges { return .commit }
    if status.ahead > 0 { return .push }
    if status.prState == nil && status.branch != nil { return .createPR }
    return nil
  }

  var body: some View {
    HStack(spacing: T3Design.Spacing.sm) {
      // Primary action button
      if let action = primaryAction {
        Button {
          performAction(action)
        } label: {
          Label(action.label, systemImage: action.icon)
            .font(T3Design.Fonts.caption)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(action.tint)
      }

      // Git actions menu
      Menu {
        if let status = gitStatus {
          Section("Repository") {
            if status.hasChanges {
              Button {
                showCommitDialog = true
              } label: {
                Label("Commit…", systemImage: "checkmark.circle")
              }
            }

            if status.ahead > 0 {
              Button {
                performAction(.push)
              } label: {
                Label("Push", systemImage: "arrow.up.circle")
              }
            }

            Button {
              performAction(.pull)
            } label: {
              Label("Pull", systemImage: "arrow.down.circle")
            }
          }

          if let prState = status.prState {
            Section("Pull Request") {
              if prState == .open, let url = status.prUrl {
                Button {
                  if let nsURL = URL(string: url) {
                    NSWorkspace.shared.open(nsURL)
                  }
                } label: {
                  Label("View PR", systemImage: "arrow.up.right.square")
                }
              }
            }
          }
        }

        Section {
          Button {
            Task { await store.fetchGitStatus(for: thread.id) }
          } label: {
            Label("Refresh Status", systemImage: "arrow.clockwise")
          }
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.system(size: 13))
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
    .sheet(isPresented: $showCommitDialog) {
      commitDialog
    }
    .alert("Push to Default Branch?", isPresented: $showDefaultBranchWarning) {
      Button("Cancel", role: .cancel) {}
      Button("Push Anyway") {
        if let action = pendingAction {
          Task { await action() }
        }
      }
    } message: {
      Text("You're about to push directly to the default branch. This is usually not recommended.")
    }
  }

  // MARK: - Commit Dialog

  private var commitDialog: some View {
    VStack(spacing: T3Design.Spacing.lg) {
      Text("Commit Changes")
        .font(T3Design.Fonts.headline)

      if let files = gitStatus?.changedFiles {
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            ForEach(files) { file in
              HStack(spacing: T3Design.Spacing.sm) {
                Image(systemName: FileStatusStyle.icon(for: file.status))
                  .font(.system(size: 10))
                  .foregroundStyle(FileStatusStyle.color(for: file.status))
                  .frame(width: 14)

                Text(file.path)
                  .font(T3Design.Fonts.codeSmall)
                  .lineLimit(1)
                  .truncationMode(.middle)

                Spacer()

                HStack(spacing: 4) {
                  if file.additions > 0 {
                    Text("+\(file.additions)")
                      .font(T3Design.Fonts.codeSmall)
                      .foregroundStyle(T3Design.successGreen)
                  }
                  if file.deletions > 0 {
                    Text("-\(file.deletions)")
                      .font(T3Design.Fonts.codeSmall)
                      .foregroundStyle(T3Design.errorRed)
                  }
                }
              }
            }
          }
        }
        .frame(maxHeight: 200)
      }

      TextEditor(text: $commitMessage)
        .font(T3Design.Fonts.body)
        .frame(height: 80)
        .scrollContentBackground(.hidden)
        .padding(T3Design.Spacing.sm)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: T3Design.Radius.md))
        .overlay(
          RoundedRectangle(cornerRadius: T3Design.Radius.md)
            .strokeBorder(T3Design.Colors.border.opacity(0.2), lineWidth: 0.5)
        )

      HStack {
        Button("Cancel") { showCommitDialog = false }
          .keyboardShortcut(.cancelAction)

        Spacer()

        Button("Commit") {
          Task {
            await store.gitCommit(threadId: thread.id, message: commitMessage)
            commitMessage = ""
            showCommitDialog = false
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(T3Design.Spacing.xl)
    .frame(width: 440)
  }

  // MARK: - Helpers

  private func performAction(_ action: GitAction) {
    switch action {
    case .commit:
      showCommitDialog = true
    case .push:
      let branch = gitStatus?.branch ?? ""
      if branch == "main" || branch == "master" {
        pendingAction = { await store.gitPush(threadId: thread.id) }
        showDefaultBranchWarning = true
      } else {
        Task { await store.gitPush(threadId: thread.id) }
      }
    case .pull:
      Task { await store.gitPull(threadId: thread.id) }
    case .createPR:
      store.addToast(.info("PR creation opens in your browser"))
    }
  }
}

enum GitAction {
  case commit, push, pull, createPR

  var label: String {
    switch self {
    case .commit: "Commit"
    case .push: "Push"
    case .pull: "Pull"
    case .createPR: "Create PR"
    }
  }

  var icon: String {
    switch self {
    case .commit: "checkmark.circle"
    case .push: "arrow.up.circle"
    case .pull: "arrow.down.circle"
    case .createPR: "arrow.triangle.pull"
    }
  }

  var tint: Color {
    switch self {
    case .commit: T3Design.accentPurple
    case .push: T3Design.infoBlue
    case .pull: T3Design.successGreen
    case .createPR: T3Design.successGreen
    }
  }
}
#endif
