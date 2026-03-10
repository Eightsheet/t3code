#if canImport(SwiftUI) && os(macOS)
import Foundation
import SwiftUI
import T3CodeMacOSRuntime

// MARK: - App Store

@MainActor
final class AppStore: ObservableObject {
  // MARK: - Core state
  @Published var projects: [OrchestrationProject] = []
  @Published var threads: [OrchestrationThread] = []
  @Published var selectedThreadId: ThreadId?
  @Published var snapshotSequence: Int = 0
  @Published var isHydrated = false

  // MARK: - App settings
  @Published var settings: AppSettings {
    didSet { settings.save() }
  }

  // MARK: - UI state
  @Published var showSettings = false
  @Published var showDiffPanel = false
  @Published var showPlanSidebar = false
  @Published var showTerminalDrawer = false
  @Published var terminalDrawerHeight: CGFloat = 240
  @Published var diffPanelWidth: CGFloat = 380
  @Published var isSidebarCollapsed = false

  // MARK: - Git state
  @Published var gitStatusByThread: [ThreadId: GitStatus] = [:]
  @Published var gitBranches: [GitBranch] = []

  // MARK: - Terminal state
  @Published var terminalsByThread: [ThreadId: [TerminalInfo]] = [:]
  @Published var activeTerminalId: String?

  // MARK: - Thread expansion state (sidebar)
  @Published var expandedProjects: Set<ProjectId> = []
  @Published var projectShowAll: [ProjectId: Bool] = [:]

  // MARK: - Delete confirmation
  @Published var pendingDeleteThreadId: ThreadId?
  @Published var pendingDeleteProjectId: ProjectId?
  @Published var pendingDeleteWorktree = false

  // MARK: - Toast messages
  @Published var toasts: [ToastMessage] = []

  // MARK: - Draft threads
  @Published var draftThreads: [ProjectId: DraftThread] = [:]

  // MARK: - Welcome context
  @Published var welcomeCwd: String?
  @Published var welcomeProjectName: String?

  let transport = WebSocketTransport()
  private let snapshotSyncCoalescer = AsyncChangeCoalescer(debounceMilliseconds: 75)

  init() {
    settings = AppSettings.load()
  }

  // MARK: - Computed

  var selectedThread: OrchestrationThread? {
    guard let id = selectedThreadId else { return nil }
    return threads.first { $0.id == id }
  }

  var sortedThreads: [OrchestrationThread] {
    threads
      .filter { $0.deletedAt == nil }
      .sorted { $0.updatedAt > $1.updatedAt }
  }

  func threadsForProject(_ projectId: ProjectId) -> [OrchestrationThread] {
    sortedThreads.filter { $0.projectId == projectId }
  }

  var activeProjects: [OrchestrationProject] {
    projects.filter { $0.deletedAt == nil }
  }

  func threadStatus(_ thread: OrchestrationThread) -> ThreadStatusKind {
    if thread.session?.status == .running || thread.latestTurn?.state == .running {
      return .working
    }
    if thread.session?.status == .starting {
      return .connecting
    }
    if thread.activities.contains(where: { $0.tone == .approval }) {
      return .pendingApproval
    }
    if let terminals = terminalsByThread[thread.id], terminals.contains(where: { $0.isRunning }) {
      return .terminalRunning
    }
    if thread.latestTurn?.state == .completed {
      return .completed
    }
    return .idle
  }

  // MARK: - Connection

  func connectToBackend(url: URL) {
    transport.connect(to: url)

    transport.onPush(channel: "orchestration.domainEvent") { [weak self] _ in
      Task { @MainActor in self?.requestSnapshotSync() }
    }

    transport.onPush(channel: "server.welcome") { [weak self] data in
      Task { @MainActor in
        if let dict = data as? [String: Any] {
          self?.welcomeCwd = dict["cwd"] as? String
          self?.welcomeProjectName = dict["projectName"] as? String
          if let threadId = dict["bootstrapThreadId"] as? String {
            self?.selectedThreadId = threadId
          }
        }
        self?.requestSnapshotSync()
      }
    }

    transport.onPush(channel: "server.configUpdated") { _ in }

    Task {
      try? await Task.sleep(nanoseconds: 500_000_000)
      await MainActor.run { requestSnapshotSync() }
    }
  }

  private func requestSnapshotSync() {
    snapshotSyncCoalescer.signal { [weak self] in
      await self?.syncSnapshot()
    }
  }

  func syncSnapshot() async {
    do {
      let response = try await transport.send(
        method: "orchestration.getSnapshot",
        params: ["_tag": "orchestration.getSnapshot"]
      )

      guard let resultValue = response.result?.value,
        let resultData = try? JSONSerialization.data(withJSONObject: resultValue)
      else {
        return
      }

      if isHydrated,
        let nextSnapshot = try? JSONDecoder().decode(SnapshotSequenceEnvelope.self, from: resultData),
        nextSnapshot.snapshotSequence == snapshotSequence
      {
        return
      }

      guard let snapshot = try? JSONDecoder().decode(OrchestrationReadModel.self, from: resultData)
      else {
        return
      }

      projects = snapshot.projects
      threads = snapshot.threads
      snapshotSequence = snapshot.snapshotSequence
      isHydrated = true

      // Auto-expand all projects with threads
      for project in activeProjects {
        if !threadsForProject(project.id).isEmpty {
          expandedProjects.insert(project.id)
        }
      }

      if selectedThreadId == nil, let firstThread = sortedThreads.first {
        selectedThreadId = firstThread.id
      }
    } catch {
      // Will retry on next domain event
    }
  }

  // MARK: - Commands

  func dispatchCommand(_ command: [String: Any]) async {
    let params: [String: Any] = [
      "_tag": "orchestration.dispatchCommand",
      "command": command,
    ]
    _ = try? await transport.send(method: "orchestration.dispatchCommand", params: params)
  }

  func createThread(
    projectId: ProjectId,
    title: String = "New thread",
    model: String = "codex",
    branch: String? = nil,
    worktreePath: String? = nil
  ) async -> ThreadId {
    let threadId = UUID().uuidString
    let command = CommandBuilder.threadCreate(
      threadId: threadId,
      projectId: projectId,
      title: title,
      model: model,
      runtimeMode: .fullAccess,
      branch: branch,
      worktreePath: worktreePath
    )
    await dispatchCommand(command)
    selectedThreadId = threadId
    return threadId
  }

  func createThreadInheritingContext() async -> ThreadId? {
    guard let project = activeProjects.first else { return nil }
    let currentThread = selectedThread
    return await createThread(
      projectId: project.id,
      branch: currentThread?.branch,
      worktreePath: currentThread?.worktreePath
    )
  }

  func sendMessage(threadId: ThreadId, text: String, model: String? = nil) async {
    let messageId = UUID().uuidString
    let thread = threads.first { $0.id == threadId }
    let command = CommandBuilder.threadTurnStart(
      threadId: threadId,
      messageId: messageId,
      text: text,
      model: model ?? thread?.model,
      runtimeMode: thread?.runtimeMode ?? .fullAccess,
      interactionMode: thread?.interactionMode ?? .default
    )
    ComposerDraftStore.shared.clearDraft(for: threadId)
    await dispatchCommand(command)
  }

  func interruptThread(_ threadId: ThreadId) async {
    await dispatchCommand(CommandBuilder.threadTurnInterrupt(threadId: threadId))
  }

  func deleteThread(_ threadId: ThreadId, deleteWorktree: Bool = false) async {
    await dispatchCommand(CommandBuilder.threadDelete(threadId: threadId))
    ComposerDraftStore.shared.clearDraft(for: threadId)
    terminalsByThread.removeValue(forKey: threadId)
    gitStatusByThread.removeValue(forKey: threadId)
    if selectedThreadId == threadId {
      selectedThreadId = sortedThreads.first(where: { $0.id != threadId })?.id
    }
  }

  func renameThread(_ threadId: ThreadId, title: String) async {
    await dispatchCommand(CommandBuilder.threadMetaUpdate(threadId: threadId, title: title))
  }

  // MARK: - Approval commands

  func approveRequest(threadId: ThreadId, approvalRequestId: ApprovalRequestId) async {
    await dispatchCommand(CommandBuilder.threadTurnApprove(threadId: threadId, approvalRequestId: approvalRequestId))
  }

  func rejectRequest(threadId: ThreadId, approvalRequestId: ApprovalRequestId) async {
    await dispatchCommand(CommandBuilder.threadTurnReject(threadId: threadId, approvalRequestId: approvalRequestId))
  }

  // MARK: - Project commands

  func addProject(path: String) async {
    let projectId = UUID().uuidString
    let title = URL(fileURLWithPath: path).lastPathComponent
    await dispatchCommand(CommandBuilder.projectAdd(projectId: projectId, path: path, title: title))
    expandedProjects.insert(projectId)
  }

  func deleteProject(_ projectId: ProjectId) async {
    let projectThreads = threadsForProject(projectId)
    guard projectThreads.isEmpty else {
      addToast(.error("Cannot delete project with active threads"))
      return
    }
    await dispatchCommand(CommandBuilder.projectDelete(projectId: projectId))
    expandedProjects.remove(projectId)
  }

  // MARK: - Script commands

  func addScript(projectId: ProjectId, name: String, command: String, icon: String, runOnCreate: Bool) async {
    let scriptId = UUID().uuidString
    await dispatchCommand(
      CommandBuilder.projectScriptAdd(
        projectId: projectId, scriptId: scriptId, name: name, command: command, icon: icon,
        runOnWorktreeCreate: runOnCreate))
  }

  func updateScript(
    projectId: ProjectId, scriptId: String, name: String, command: String, icon: String, runOnCreate: Bool
  ) async {
    await dispatchCommand(
      CommandBuilder.projectScriptUpdate(
        projectId: projectId, scriptId: scriptId, name: name, command: command, icon: icon,
        runOnWorktreeCreate: runOnCreate))
  }

  func deleteScript(projectId: ProjectId, scriptId: String) async {
    await dispatchCommand(CommandBuilder.projectScriptDelete(projectId: projectId, scriptId: scriptId))
  }

  // MARK: - Git integration

  func fetchGitStatus(for threadId: ThreadId) async {
    do {
      let response = try await transport.send(
        method: "git.getStatus",
        params: ["_tag": "git.getStatus", "threadId": threadId]
      )
      guard let resultValue = response.result?.value,
        let resultData = try? JSONSerialization.data(withJSONObject: resultValue),
        let status = try? JSONDecoder().decode(GitStatus.self, from: resultData)
      else { return }
      gitStatusByThread[threadId] = status
    } catch {}
  }

  func fetchGitBranches(for threadId: ThreadId) async {
    do {
      let response = try await transport.send(
        method: "git.getBranches",
        params: ["_tag": "git.getBranches", "threadId": threadId]
      )
      guard let resultValue = response.result?.value,
        let resultData = try? JSONSerialization.data(withJSONObject: resultValue),
        let branches = try? JSONDecoder().decode([GitBranch].self, from: resultData)
      else { return }
      gitBranches = branches
    } catch {}
  }

  func gitCommit(threadId: ThreadId, message: String) async {
    do {
      _ = try await transport.send(
        method: "git.commit",
        params: ["_tag": "git.commit", "threadId": threadId, "message": message]
      )
      addToast(.success("Changes committed"))
      await fetchGitStatus(for: threadId)
    } catch {
      addToast(.error("Commit failed: \(error.localizedDescription)"))
    }
  }

  func gitPush(threadId: ThreadId) async {
    do {
      _ = try await transport.send(
        method: "git.push",
        params: ["_tag": "git.push", "threadId": threadId]
      )
      addToast(.success("Pushed to remote"))
      await fetchGitStatus(for: threadId)
    } catch {
      addToast(.error("Push failed: \(error.localizedDescription)"))
    }
  }

  func gitPull(threadId: ThreadId) async {
    do {
      _ = try await transport.send(
        method: "git.pull",
        params: ["_tag": "git.pull", "threadId": threadId]
      )
      addToast(.success("Pulled from remote"))
      await fetchGitStatus(for: threadId)
    } catch {
      addToast(.error("Pull failed: \(error.localizedDescription)"))
    }
  }

  func gitCheckoutBranch(threadId: ThreadId, branch: String) async {
    do {
      _ = try await transport.send(
        method: "git.checkoutBranch",
        params: ["_tag": "git.checkoutBranch", "threadId": threadId, "branch": branch]
      )
      await fetchGitStatus(for: threadId)
    } catch {
      addToast(.error("Branch switch failed: \(error.localizedDescription)"))
    }
  }

  // MARK: - Diff fetching

  func fetchDiffs(for threadId: ThreadId, turnId: TurnId? = nil) async -> [FileDiff] {
    do {
      var params: [String: Any] = ["_tag": "git.getDiffs", "threadId": threadId]
      if let turnId { params["turnId"] = turnId }
      let response = try await transport.send(method: "git.getDiffs", params: params)
      guard let resultValue = response.result?.value,
        let resultData = try? JSONSerialization.data(withJSONObject: resultValue),
        let diffs = try? JSONDecoder().decode([FileDiff].self, from: resultData)
      else { return [] }
      return diffs
    } catch {
      return []
    }
  }

  // MARK: - Toast system

  func addToast(_ toast: ToastMessage) {
    toasts.append(toast)
    Task {
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      await MainActor.run {
        toasts.removeAll { $0.id == toast.id }
      }
    }
  }

  // MARK: - Terminal management

  func addTerminal(for threadId: ThreadId) {
    var terminals = terminalsByThread[threadId] ?? []
    guard terminals.count < 8 else {
      addToast(.error("Maximum 8 terminals per thread"))
      return
    }
    let terminalId = UUID().uuidString
    terminals.append(TerminalInfo(id: terminalId, label: "Terminal \(terminals.count + 1)", isRunning: false))
    terminalsByThread[threadId] = terminals
    activeTerminalId = terminalId
  }

  func removeTerminal(for threadId: ThreadId, terminalId: String) {
    terminalsByThread[threadId]?.removeAll { $0.id == terminalId }
    if activeTerminalId == terminalId {
      activeTerminalId = terminalsByThread[threadId]?.first?.id
    }
  }

  // MARK: - Folder picker

  func showFolderPicker() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.message = "Select a project folder"
    panel.prompt = "Add Project"
    return panel.runModal() == .OK ? panel.url?.path : nil
  }
}

// MARK: - Thread Status

enum ThreadStatusKind {
  case idle
  case working
  case connecting
  case completed
  case pendingApproval
  case terminalRunning
}

private struct SnapshotSequenceEnvelope: Decodable {
  let snapshotSequence: Int
}

// MARK: - Toast Message

struct ToastMessage: Identifiable {
  let id = UUID().uuidString
  let text: String
  let kind: ToastKind

  enum ToastKind {
    case success
    case error
    case info
  }

  static func success(_ text: String) -> ToastMessage { .init(text: text, kind: .success) }
  static func error(_ text: String) -> ToastMessage { .init(text: text, kind: .error) }
  static func info(_ text: String) -> ToastMessage { .init(text: text, kind: .info) }
}
#endif
