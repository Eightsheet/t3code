#if canImport(SwiftUI) && os(macOS)
import Foundation
import SwiftUI

// MARK: - App Store

@MainActor
final class AppStore: ObservableObject {
  @Published var projects: [OrchestrationProject] = []
  @Published var threads: [OrchestrationThread] = []
  @Published var selectedThreadId: ThreadId?
  @Published var snapshotSequence: Int = 0
  @Published var isHydrated = false

  let transport = WebSocketTransport()

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

  // MARK: - Connection

  func connectToBackend(url: URL) {
    transport.connect(to: url)

    transport.onPush(channel: "orchestration.domainEvent") { [weak self] _ in
      Task { @MainActor in
        await self?.syncSnapshot()
      }
    }

    transport.onPush(channel: "server.welcome") { [weak self] data in
      Task { @MainActor in
        if let dict = data as? [String: Any],
          let threadId = dict["bootstrapThreadId"] as? String
        {
          self?.selectedThreadId = threadId
        }
        await self?.syncSnapshot()
      }
    }

    transport.onPush(channel: "server.configUpdated") { _ in }

    Task {
      try? await Task.sleep(nanoseconds: 500_000_000)
      await syncSnapshot()
    }
  }

  func syncSnapshot() async {
    do {
      let response = try await transport.send(
        method: "orchestration.getSnapshot",
        params: ["_tag": "orchestration.getSnapshot"]
      )

      guard let resultValue = response.result?.value,
        let resultData = try? JSONSerialization.data(withJSONObject: resultValue),
        let snapshot = try? JSONDecoder().decode(OrchestrationReadModel.self, from: resultData)
      else {
        return
      }

      projects = snapshot.projects
      threads = snapshot.threads
      snapshotSequence = snapshot.snapshotSequence
      isHydrated = true

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

  func createThread(projectId: ProjectId, title: String = "New thread", model: String = "codex") async -> ThreadId {
    let threadId = UUID().uuidString
    let command = CommandBuilder.threadCreate(
      threadId: threadId,
      projectId: projectId,
      title: title,
      model: model,
      runtimeMode: .fullAccess
    )
    await dispatchCommand(command)
    selectedThreadId = threadId
    return threadId
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
    await dispatchCommand(command)
  }

  func interruptThread(_ threadId: ThreadId) async {
    await dispatchCommand(CommandBuilder.threadTurnInterrupt(threadId: threadId))
  }

  func deleteThread(_ threadId: ThreadId) async {
    await dispatchCommand(CommandBuilder.threadDelete(threadId: threadId))
    if selectedThreadId == threadId {
      selectedThreadId = sortedThreads.first(where: { $0.id != threadId })?.id
    }
  }

  func renameThread(_ threadId: ThreadId, title: String) async {
    await dispatchCommand(CommandBuilder.threadMetaUpdate(threadId: threadId, title: title))
  }
}
#endif
