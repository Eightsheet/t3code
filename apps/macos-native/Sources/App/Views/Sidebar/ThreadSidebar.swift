#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Thread Sidebar

struct ThreadSidebar: View {
  @ObservedObject var store: AppStore
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

      Button {
        Task { await createNewThread() }
      } label: {
        Image(systemName: "plus.message")
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(.secondary)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("New thread")
      .keyboardShortcut("n", modifiers: .command)
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
        if store.activeProjects.isEmpty && filteredThreads.isEmpty {
          emptyState
        } else {
          ForEach(store.activeProjects) { project in
            ProjectSection(
              project: project,
              threads: filteredThreads.filter { $0.projectId == project.id },
              selectedThreadId: store.selectedThreadId,
              hoveredThreadId: hoveredThreadId,
              renamingThreadId: renamingThreadId,
              renameText: $renameText,
              onSelect: { store.selectedThreadId = $0 },
              onHover: { hoveredThreadId = $0 },
              onDelete: { id in Task { await store.deleteThread(id) } },
              onStartRename: { id in
                renamingThreadId = id
                renameText = filteredThreads.first { $0.id == id }?.title ?? ""
              },
              onCommitRename: { id in
                Task {
                  await store.renameThread(id, title: renameText)
                  renamingThreadId = nil
                }
              },
              onCancelRename: { renamingThreadId = nil }
            )
          }

          let orphanThreads = filteredThreads.filter { thread in
            !store.activeProjects.contains { $0.id == thread.projectId }
          }
          if !orphanThreads.isEmpty {
            Section {
              ForEach(orphanThreads) { thread in
                ThreadRow(
                  thread: thread,
                  isSelected: store.selectedThreadId == thread.id,
                  isHovered: hoveredThreadId == thread.id,
                  isRenaming: renamingThreadId == thread.id,
                  renameText: $renameText,
                  onSelect: { store.selectedThreadId = thread.id },
                  onHover: { hoveredThreadId = $0 ? thread.id : nil },
                  onDelete: { Task { await store.deleteThread(thread.id) } },
                  onStartRename: {
                    renamingThreadId = thread.id
                    renameText = thread.title
                  },
                  onCommitRename: {
                    Task {
                      await store.renameThread(thread.id, title: renameText)
                      renamingThreadId = nil
                    }
                  },
                  onCancelRename: { renamingThreadId = nil }
                )
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

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: T3Design.Spacing.md) {
      Image(systemName: "bubble.left.and.text.bubble.right")
        .font(.system(size: 32))
        .foregroundStyle(.quaternary)

      Text("No threads yet")
        .font(T3Design.Fonts.body)
        .foregroundStyle(.secondary)

      Button("Create a thread") {
        Task { await createNewThread() }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
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

  // MARK: - Actions

  private func createNewThread() async {
    guard let project = store.activeProjects.first else { return }
    _ = await store.createThread(projectId: project.id)
  }
}

// MARK: - Project Section

private struct ProjectSection: View {
  let project: OrchestrationProject
  let threads: [OrchestrationThread]
  let selectedThreadId: ThreadId?
  let hoveredThreadId: ThreadId?
  let renamingThreadId: ThreadId?
  @Binding var renameText: String
  let onSelect: (ThreadId) -> Void
  let onHover: (ThreadId?) -> Void
  let onDelete: (ThreadId) -> Void
  let onStartRename: (ThreadId) -> Void
  let onCommitRename: (ThreadId) -> Void
  let onCancelRename: () -> Void

  @State private var isExpanded = true

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      ForEach(threads) { thread in
        ThreadRow(
          thread: thread,
          isSelected: selectedThreadId == thread.id,
          isHovered: hoveredThreadId == thread.id,
          isRenaming: renamingThreadId == thread.id,
          renameText: $renameText,
          onSelect: { onSelect(thread.id) },
          onHover: { onHover($0 ? thread.id : nil) },
          onDelete: { onDelete(thread.id) },
          onStartRename: { onStartRename(thread.id) },
          onCommitRename: { onCommitRename(thread.id) },
          onCancelRename: onCancelRename
        )
      }
    } label: {
      HStack(spacing: T3Design.Spacing.sm) {
        Image(systemName: "folder.fill")
          .font(.system(size: 12))
          .foregroundStyle(T3Design.accentPurple)

        Text(project.title)
          .font(T3Design.Fonts.captionMedium)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Spacer()

        Text("\(threads.count)")
          .font(T3Design.Fonts.caption)
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, T3Design.Spacing.lg)
      .padding(.vertical, T3Design.Spacing.xs)
    }
    .disclosureGroupStyle(SidebarDisclosureStyle())
  }
}

// MARK: - Thread Row

struct ThreadRow: View {
  let thread: OrchestrationThread
  let isSelected: Bool
  let isHovered: Bool
  let isRenaming: Bool
  @Binding var renameText: String
  let onSelect: () -> Void
  let onHover: (Bool) -> Void
  let onDelete: () -> Void
  let onStartRename: () -> Void
  let onCommitRename: () -> Void
  let onCancelRename: () -> Void

  private var isActive: Bool {
    thread.session?.status == .running || thread.session?.status == .ready
  }

  private var lastMessagePreview: String? {
    thread.messages.last?.text.prefix(60).trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: T3Design.Spacing.sm) {
        if isActive {
          StatusDot(T3Design.successGreen, size: 6)
        }

        VStack(alignment: .leading, spacing: 2) {
          if isRenaming {
            TextField("Thread name", text: $renameText, onCommit: onCommitRename)
              .textFieldStyle(.plain)
              .font(T3Design.Fonts.body)
              .onExitCommand(perform: onCancelRename)
          } else {
            Text(thread.title)
              .font(T3Design.Fonts.body)
              .foregroundStyle(.primary)
              .lineLimit(1)

            if let preview = lastMessagePreview {
              Text(preview)
                .font(T3Design.Fonts.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
          }
        }

        Spacer(minLength: 0)

        if thread.latestTurn?.state == .running {
          ProgressView()
            .scaleEffect(0.5)
            .frame(width: 14, height: 14)
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
    .onHover { onHover($0) }
    .contextMenu {
      Button("Rename…") { onStartRename() }
      Divider()
      Button("Delete", role: .destructive) { onDelete() }
    }
  }
}

// MARK: - Custom Disclosure Style

struct SidebarDisclosureStyle: DisclosureGroupStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(spacing: 0) {
      Button {
        withAnimation(T3Design.Animation.quick) {
          configuration.isExpanded.toggle()
        }
      } label: {
        HStack(spacing: 4) {
          Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 14)

          configuration.label
        }
      }
      .buttonStyle(.plain)

      if configuration.isExpanded {
        configuration.content
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }
}
#endif
