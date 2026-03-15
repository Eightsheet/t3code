#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI

// MARK: - Thread Sidebar

struct ThreadSidebar: View {
  @ObservedObject var store: AppStore
  @ObservedObject var runtimeModel: DesktopRuntimeModel
  @State private var searchText = ""
  @State private var hoveredThreadId: ThreadId?
  @State private var renamingThreadId: ThreadId?
  @State private var renameText = ""

  private var filteredThreads: [OrchestrationThread] {
    if searchText.isEmpty {
      return store.sortedThreads
    }
    return store.sortedThreads.filter {
      $0.title.localizedCaseInsensitiveContains(searchText)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      sidebarHeader
      searchField
      Divider()
      threadList
      Divider()
      sidebarFooter
    }
    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
    .background(T3Design.Colors.sidebarBg)
  }

  // MARK: - Header

  private var sidebarHeader: some View {
    HStack(spacing: T3Design.Spacing.sm) {
      Text("T3 Code")
        .font(T3Design.Fonts.headline)
        .foregroundStyle(.primary)

      Spacer()

      // Add project button
      Button {
        if let path = store.showFolderPicker() {
          Task { await store.addProject(path: path) }
        }
      } label: {
        Image(systemName: "folder.badge.plus")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help("Add project folder")

      Button {
        Task { _ = await store.createThreadInheritingContext() }
      } label: {
        Image(systemName: "plus.message")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.secondary)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("New thread (⌘N)")
    }
    .padding(.horizontal, T3Design.Spacing.lg)
    .padding(.top, T3Design.Spacing.lg)
    .padding(.bottom, T3Design.Spacing.sm)
  }

  // MARK: - Search

  private var searchField: some View {
    HStack(spacing: T3Design.Spacing.sm) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)

      TextField("Search threads…", text: $searchText)
        .textFieldStyle(.plain)
        .font(T3Design.Fonts.body)
    }
    .padding(.horizontal, T3Design.Spacing.sm)
    .padding(.vertical, 6)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: T3Design.Radius.sm, style: .continuous))
    .padding(.horizontal, T3Design.Spacing.md)
    .padding(.bottom, T3Design.Spacing.sm)
  }

  // MARK: - Thread List

  private var threadList: some View {
    ScrollView {
      LazyVStack(spacing: 2) {
        // Desktop update status
        if let updateState = runtimeModel.snapshot.updateState {
          updateBanner(updateState)
        }

        if store.activeProjects.isEmpty && filteredThreads.isEmpty {
          emptyState
        } else {
          ForEach(store.activeProjects) { project in
            projectSection(project)
          }

          let orphanThreads = filteredThreads.filter { thread in
            !store.activeProjects.contains { $0.id == thread.projectId }
          }
          if !orphanThreads.isEmpty {
            Section {
              ForEach(orphanThreads) { thread in
                threadRow(thread)
              }
            } header: {
              Text("Threads")
                .font(T3Design.Fonts.captionMedium)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, T3Design.Spacing.lg)
                .padding(.top, T3Design.Spacing.md)
            }
          }
        }
      }
      .padding(.vertical, T3Design.Spacing.xs)
    }
  }

  // MARK: - Update Banner

  @ViewBuilder
  private func updateBanner(_ state: String) -> some View {
    let isUpdateAvailable = state.contains("available") || state.contains("downloaded")
    if isUpdateAvailable {
      HStack(spacing: T3Design.Spacing.sm) {
        Image(systemName: "arrow.down.circle.fill")
          .font(.system(size: 13))
          .foregroundStyle(state.contains("downloaded") ? T3Design.successGreen : T3Design.warningAmber)

        VStack(alignment: .leading, spacing: 1) {
          Text(state.contains("downloaded") ? "Update ready" : "Update available")
            .font(T3Design.Fonts.caption)
          Text("Restart to apply")
            .font(T3Design.Fonts.codeSmall)
            .foregroundStyle(.tertiary)
        }

        Spacer()
      }
      .padding(.horizontal, T3Design.Spacing.lg)
      .padding(.vertical, T3Design.Spacing.sm)
      .background(T3Design.warningAmber.opacity(0.06), in: RoundedRectangle(cornerRadius: T3Design.Radius.md))
      .padding(.horizontal, T3Design.Spacing.sm)
    }
  }

  // MARK: - Project section

  @ViewBuilder
  private func projectSection(_ project: OrchestrationProject) -> some View {
    let threads = filteredThreads.filter { $0.projectId == project.id }
    let isExpanded = store.expandedProjects.contains(project.id)
    let showAll = store.projectShowAll[project.id] ?? false
    let maxVisible = 6
    let visibleThreads = showAll ? threads : Array(threads.prefix(maxVisible))

    VStack(spacing: 0) {
      // Project header
      Button {
        withAnimation(T3Design.Animation.quick) {
          if isExpanded {
            store.expandedProjects.remove(project.id)
          } else {
            store.expandedProjects.insert(project.id)
          }
        }
      } label: {
        HStack(spacing: 4) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 14)

          Image(systemName: "folder.fill")
            .font(.system(size: 12))
            .foregroundStyle(T3Design.accentPurple)

          Text(project.title)
            .font(T3Design.Fonts.captionMedium)
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Spacer()

          // Scripts menu
          if !project.scripts.isEmpty {
            ProjectScriptsControl(store: store, project: project)
          }

          Text("\(threads.count)")
            .font(T3Design.Fonts.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, T3Design.Spacing.lg)
        .padding(.vertical, T3Design.Spacing.xs)
      }
      .buttonStyle(.plain)
      .contextMenu {
        Button("Add Script…") {
          // Open script editor for this project
        }
        Divider()
        Button("Delete Project", role: .destructive) {
          store.pendingDeleteProjectId = project.id
        }
        .disabled(!threads.isEmpty)
      }

      if isExpanded {
        ForEach(visibleThreads) { thread in
          threadRow(thread)
        }

        if threads.count > maxVisible {
          Button {
            store.projectShowAll[project.id] = !showAll
          } label: {
            Text(showAll ? "Show less" : "Show \(threads.count - maxVisible) more…")
              .font(T3Design.Fonts.caption)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .padding(.horizontal, T3Design.Spacing.xl)
          .padding(.vertical, T3Design.Spacing.xxs)
        }
      }
    }
  }

  // MARK: - Thread Row

  private func threadRow(_ thread: OrchestrationThread) -> some View {
    let isSelected = store.selectedThreadId == thread.id
    let isHovered = hoveredThreadId == thread.id
    let isRenaming = renamingThreadId == thread.id
    let status = store.threadStatus(thread)

    return Button {
      store.selectedThreadId = thread.id
    } label: {
      HStack(spacing: T3Design.Spacing.sm) {
        // Status indicator
        threadStatusIndicator(status)

        VStack(alignment: .leading, spacing: 2) {
          if isRenaming {
            TextField("Thread name", text: $renameText, onCommit: {
              Task {
                await store.renameThread(thread.id, title: renameText)
                renamingThreadId = nil
              }
            })
            .textFieldStyle(.plain)
            .font(T3Design.Fonts.body)
            .onExitCommand { renamingThreadId = nil }
          } else {
            Text(thread.title)
              .font(T3Design.Fonts.body)
              .foregroundStyle(.primary)
              .lineLimit(1)

            if let preview = thread.messages.last?.text.prefix(60).trimmingCharacters(in: .whitespacesAndNewlines),
              !preview.isEmpty
            {
              Text(preview)
                .font(T3Design.Fonts.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
          }
        }

        Spacer(minLength: 0)

        // Right-side indicators
        HStack(spacing: 4) {
          // PR badge
          if let gitStatus = store.gitStatusByThread[thread.id], let prState = gitStatus.prState {
            prBadge(prState, url: gitStatus.prUrl)
          }

          // Relative timestamp
          Text(relativeTime(thread.updatedAt))
            .font(T3Design.Fonts.codeSmall)
            .foregroundStyle(.quaternary)

          if status == .working {
            ProgressView()
              .scaleEffect(0.5)
              .frame(width: 14, height: 14)
          }
        }
      }
      .padding(.horizontal, T3Design.Spacing.md)
      .padding(.vertical, T3Design.Spacing.sm)
      .background(
        RoundedRectangle(cornerRadius: T3Design.Radius.md, style: .continuous)
          .fill(isSelected ? T3Design.Colors.sidebarActive : (isHovered ? T3Design.Colors.sidebarHover : .clear))
      )
      .padding(.horizontal, T3Design.Spacing.sm)
    }
    .buttonStyle(.plain)
    .onHover { hoveredThreadId = $0 ? thread.id : nil }
    .contextMenu {
      Button("Rename…") {
        renamingThreadId = thread.id
        renameText = thread.title
      }

      Button("Copy Thread ID") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(thread.id, forType: .string)
      }

      Divider()

      Button("Delete", role: .destructive) {
        if store.settings.confirmThreadDelete {
          store.pendingDeleteThreadId = thread.id
        } else {
          Task { await store.deleteThread(thread.id) }
        }
      }
    }
  }

  @ViewBuilder
  private func threadStatusIndicator(_ status: ThreadStatusKind) -> some View {
    switch status {
    case .working:
      PulsingDot(color: T3Design.infoBlue)
    case .connecting:
      PulsingDot(color: T3Design.infoBlue)
    case .completed:
      Circle()
        .fill(T3Design.successGreen)
        .frame(width: 6, height: 6)
    case .pendingApproval:
      Circle()
        .fill(T3Design.warningAmber)
        .frame(width: 6, height: 6)
    case .terminalRunning:
      Image(systemName: "terminal")
        .font(.system(size: 8))
        .foregroundStyle(Color.teal)
    case .idle:
      Color.clear.frame(width: 6, height: 6)
    }
  }

  @ViewBuilder
  private func prBadge(_ state: GitPRState, url: String?) -> some View {
    let color: Color = {
      switch state {
      case .open: return T3Design.successGreen
      case .merged: return T3Design.accentPurple
      case .closed: return .secondary
      }
    }()

    Image(systemName: "arrow.triangle.pull")
      .font(.system(size: 8))
      .foregroundStyle(color)
      .onTapGesture {
        if let url, let nsURL = URL(string: url) {
          NSWorkspace.shared.open(nsURL)
        }
      }
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: T3Design.Spacing.md) {
      Image(systemName: "bubble.left.and.text.bubble.right")
        .font(.system(size: 32))
        .foregroundStyle(.quaternary)

      Text("No threads yet")
        .font(T3Design.Fonts.body)
        .foregroundStyle(.secondary)

      VStack(spacing: T3Design.Spacing.sm) {
        Button("Create a thread") {
          Task { _ = await store.createThreadInheritingContext() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)

        Button("Add project folder…") {
          if let path = store.showFolderPicker() {
            Task { await store.addProject(path: path) }
          }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 48)
  }

  // MARK: - Footer

  private var sidebarFooter: some View {
    HStack(spacing: T3Design.Spacing.sm) {
      if let wsState = connectionLabel {
        StatusDot(wsState.color, size: 6)
        Text(wsState.label)
          .font(T3Design.Fonts.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()

      Button {
        store.showSettings = true
      } label: {
        Image(systemName: "gearshape")
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.plain)
      .help("Settings (⌘,)")
    }
    .padding(.horizontal, T3Design.Spacing.lg)
    .padding(.vertical, T3Design.Spacing.sm)
  }

  private var connectionLabel: (label: String, color: Color)? {
    switch store.transport.connectionState {
    case .connected:
      return ("Connected", T3Design.successGreen)
    case .connecting:
      return ("Connecting…", T3Design.warningAmber)
    case .reconnecting(let attempt):
      return ("Reconnecting (\(attempt))…", T3Design.warningAmber)
    case .disconnected:
      return ("Disconnected", T3Design.errorRed)
    }
  }

  // MARK: - Helpers

  private func relativeTime(_ iso: String) -> String {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: iso) else { return "" }
    let interval = Date().timeIntervalSince(date)
    if interval < 60 { return "now" }
    if interval < 3600 { return "\(Int(interval / 60))m" }
    if interval < 86400 { return "\(Int(interval / 3600))h" }
    return "\(Int(interval / 86400))d"
  }
}

// MARK: - Pulsing Dot (enhanced)

struct PulsingDot: View {
  var color: Color = T3Design.accentPurple
  @State private var isPulsing = false

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 6, height: 6)
      .scaleEffect(isPulsing ? 1.3 : 1.0)
      .opacity(isPulsing ? 0.6 : 1.0)
      .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
      .onAppear { isPulsing = true }
  }
}
#endif
