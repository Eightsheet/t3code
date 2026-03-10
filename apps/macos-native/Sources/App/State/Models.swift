import Foundation

// MARK: - Core Entity IDs

typealias ThreadId = String
typealias ProjectId = String
typealias MessageId = String
typealias TurnId = String
typealias CommandId = String
typealias EventId = String
typealias ApprovalRequestId = String

// MARK: - Enums

enum MessageRole: String, Codable, Sendable {
  case user
  case assistant
  case system
}

enum RuntimeMode: String, Codable, Sendable {
  case approvalRequired = "approval-required"
  case fullAccess = "full-access"
}

enum InteractionMode: String, Codable, Sendable {
  case `default`
  case plan
}

enum SessionStatus: String, Codable, Sendable {
  case idle
  case starting
  case running
  case ready
  case interrupted
  case stopped
  case error
}

enum TurnState: String, Codable, Sendable {
  case running
  case interrupted
  case completed
  case error
}

enum ActivityTone: String, Codable, Sendable {
  case info
  case tool
  case approval
  case error
}

enum EnvMode: String, Codable, Sendable {
  case local
  case worktree
}

enum AppTheme: String, Codable, Sendable {
  case system
  case light
  case dark
}

enum ScriptIcon: String, Codable, Sendable, CaseIterable {
  case play
  case test
  case lint
  case build
  case debug
  case configure

  var systemImage: String {
    switch self {
    case .play: "play.fill"
    case .test: "checkmark.circle"
    case .lint: "wand.and.stars"
    case .build: "hammer.fill"
    case .debug: "ant.fill"
    case .configure: "gearshape.fill"
    }
  }
}

enum GitPRState: String, Codable, Sendable {
  case open
  case merged
  case closed
}

// MARK: - Core Data Models

struct ChatAttachment: Codable, Identifiable, Sendable {
  let type: String
  let id: String
  let name: String
  let mimeType: String
  let sizeBytes: Int
}

struct UploadChatAttachment: Codable, Sendable {
  let type: String
  let name: String
  let mimeType: String
  let sizeBytes: Int
  let dataUrl: String
}

struct ProjectScript: Codable, Identifiable, Sendable {
  let id: String
  let name: String
  let command: String
  let icon: String
  let runOnWorktreeCreate: Bool
  var keybinding: String?
}

struct OrchestrationProject: Codable, Identifiable, Sendable {
  let id: ProjectId
  let title: String
  let workspaceRoot: String
  let defaultModel: String?
  let scripts: [ProjectScript]
  let createdAt: String
  let updatedAt: String
  let deletedAt: String?
}

// MARK: - Git Models

struct GitBranch: Codable, Identifiable, Sendable {
  var id: String { name }
  let name: String
  let isCurrent: Bool
  let isDefault: Bool
}

struct GitStatus: Codable, Sendable {
  let branch: String?
  let ahead: Int
  let behind: Int
  let hasChanges: Bool
  let changedFiles: [GitChangedFile]
  let prState: GitPRState?
  let prUrl: String?
}

struct GitChangedFile: Codable, Identifiable, Sendable {
  var id: String { path }
  let path: String
  let status: String
  let additions: Int
  let deletions: Int
}

// MARK: - Diff Models

struct FileDiff: Codable, Identifiable, Sendable {
  var id: String { path }
  let path: String
  let oldPath: String?
  let kind: String
  let additions: Int
  let deletions: Int
  let hunks: [DiffHunk]
}

struct DiffHunk: Codable, Identifiable, Sendable {
  let id: String
  let header: String
  let lines: [DiffLine]
}

struct DiffLine: Codable, Identifiable, Sendable {
  let id: String
  let type: String
  let content: String
  let oldLineNumber: Int?
  let newLineNumber: Int?
}

// MARK: - Terminal Models

struct TerminalInfo: Identifiable, Sendable {
  let id: String
  let label: String
  var isRunning: Bool
}

// MARK: - App Settings

struct AppSettings: Codable, Sendable {
  var theme: AppTheme = .system
  var codexBinaryPath: String?
  var codexHomePath: String?
  var defaultServiceTier: String = "standard"
  var customModelSlugs: [String] = []
  var streamAssistantMessages: Bool = true
  var confirmThreadDelete: Bool = true
}

// MARK: - Draft Thread

struct DraftThread: Sendable {
  let projectId: ProjectId
  let branch: String?
  let worktreePath: String?
  let envMode: EnvMode
  var composerText: String
}

struct OrchestrationMessage: Codable, Identifiable, Sendable {
  let id: MessageId
  let role: MessageRole
  let text: String
  let attachments: [ChatAttachment]?
  let turnId: TurnId?
  let streaming: Bool
  let createdAt: String
  let updatedAt: String
}

struct OrchestrationProposedPlan: Codable, Identifiable, Sendable {
  let id: String
  let turnId: TurnId?
  let planMarkdown: String
  let createdAt: String
  let updatedAt: String
}

struct OrchestrationLatestTurn: Codable, Sendable {
  let turnId: TurnId
  let state: TurnState
  let requestedAt: String
  let startedAt: String?
  let completedAt: String?
  let assistantMessageId: MessageId?
}

struct OrchestrationSession: Codable, Sendable {
  let threadId: ThreadId
  let status: SessionStatus
  let providerName: String?
  let runtimeMode: RuntimeMode
  let activeTurnId: TurnId?
  let lastError: String?
  let updatedAt: String
}

struct ThreadActivity: Codable, Identifiable, Sendable {
  let id: EventId
  let tone: ActivityTone
  let kind: String
  let summary: String
  let turnId: TurnId?
  let sequence: Int?
  let createdAt: String
}

struct CheckpointFile: Codable, Sendable {
  let path: String
  let kind: String
  let additions: Int
  let deletions: Int
}

struct CheckpointSummary: Codable, Sendable {
  let turnId: TurnId
  let checkpointTurnCount: Int
  let checkpointRef: String
  let status: String
  let files: [CheckpointFile]
  let assistantMessageId: MessageId?
  let completedAt: String
}

struct OrchestrationThread: Codable, Identifiable, Sendable {
  let id: ThreadId
  let projectId: ProjectId
  let title: String
  let model: String
  let runtimeMode: RuntimeMode
  let interactionMode: InteractionMode?
  let branch: String?
  let worktreePath: String?
  let latestTurn: OrchestrationLatestTurn?
  let createdAt: String
  let updatedAt: String
  let deletedAt: String?
  let messages: [OrchestrationMessage]
  let proposedPlans: [OrchestrationProposedPlan]?
  let activities: [ThreadActivity]
  let checkpoints: [CheckpointSummary]?
  let session: OrchestrationSession?
}

struct OrchestrationReadModel: Codable, Sendable {
  let snapshotSequence: Int
  let projects: [OrchestrationProject]
  let threads: [OrchestrationThread]
  let updatedAt: String
}

// MARK: - WebSocket Protocol

struct WebSocketRequest: Codable, Sendable {
  let id: String
  let body: [String: AnyCodable]
}

struct WebSocketResponseError: Codable, Sendable {
  let message: String
}

struct WebSocketResponse: Codable, Sendable {
  let id: String?
  let result: AnyCodable?
  let error: WebSocketResponseError?
  let type: String?
  let channel: String?
  let data: AnyCodable?
}

struct WsWelcomePayload: Codable, Sendable {
  let cwd: String
  let projectName: String
  let bootstrapProjectId: ProjectId?
  let bootstrapThreadId: ThreadId?
}

// MARK: - AnyCodable helper

// AnyCodable wraps JSON-decoded values (Bool, Int, Double, String, Array, Dictionary, NSNull).
// All concrete values stored are either value types or immutable Foundation types, making
// cross-actor transfer safe despite the `Any` type erasure.
struct AnyCodable: Codable, @unchecked Sendable {
  let value: Any

  init(_ value: Any) {
    self.value = value
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      value = NSNull()
    } else if let bool = try? container.decode(Bool.self) {
      value = bool
    } else if let int = try? container.decode(Int.self) {
      value = int
    } else if let double = try? container.decode(Double.self) {
      value = double
    } else if let string = try? container.decode(String.self) {
      value = string
    } else if let array = try? container.decode([AnyCodable].self) {
      value = array.map(\.value)
    } else if let dict = try? container.decode([String: AnyCodable].self) {
      value = dict.mapValues(\.value)
    } else {
      value = NSNull()
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch value {
    case is NSNull:
      try container.encodeNil()
    case let bool as Bool:
      try container.encode(bool)
    case let int as Int:
      try container.encode(int)
    case let double as Double:
      try container.encode(double)
    case let string as String:
      try container.encode(string)
    case let array as [Any]:
      try container.encode(array.map { AnyCodable($0) })
    case let dict as [String: Any]:
      try container.encode(dict.mapValues { AnyCodable($0) })
    default:
      try container.encodeNil()
    }
  }
}

// MARK: - Timeline Entry

enum TimelineEntryKind {
  case message(OrchestrationMessage)
  case proposedPlan(OrchestrationProposedPlan)
  case activity(ThreadActivity)
}

struct TimelineEntry: Identifiable {
  let id: String
  let kind: TimelineEntryKind
  let createdAt: String

  var sortDate: Date {
    ISO8601DateFormatter().date(from: createdAt) ?? Date.distantPast
  }
}

// MARK: - Command Builders

enum CommandBuilder {
  static func threadCreate(
    threadId: ThreadId,
    projectId: ProjectId,
    title: String,
    model: String,
    runtimeMode: RuntimeMode,
    interactionMode: InteractionMode = .default,
    branch: String? = nil,
    worktreePath: String? = nil
  ) -> [String: Any] {
    [
      "_tag": "thread.create",
      "type": "thread.create",
      "commandId": UUID().uuidString,
      "threadId": threadId,
      "projectId": projectId,
      "title": title,
      "model": model,
      "runtimeMode": runtimeMode.rawValue,
      "interactionMode": interactionMode.rawValue,
      "branch": branch as Any? ?? NSNull(),
      "worktreePath": worktreePath as Any? ?? NSNull(),
      "createdAt": ISO8601DateFormatter().string(from: Date()),
    ]
  }

  static func threadTurnStart(
    threadId: ThreadId,
    messageId: MessageId,
    text: String,
    model: String? = nil,
    runtimeMode: RuntimeMode = .fullAccess,
    interactionMode: InteractionMode = .default
  ) -> [String: Any] {
    var body: [String: Any] = [
      "_tag": "thread.turn.start",
      "type": "thread.turn.start",
      "commandId": UUID().uuidString,
      "threadId": threadId,
      "message": [
        "messageId": messageId,
        "role": "user",
        "text": text,
        "attachments": [] as [[String: Any]],
      ] as [String: Any],
      "runtimeMode": runtimeMode.rawValue,
      "interactionMode": interactionMode.rawValue,
      "createdAt": ISO8601DateFormatter().string(from: Date()),
    ]
    if let model { body["model"] = model }
    return body
  }

  static func threadTurnInterrupt(threadId: ThreadId) -> [String: Any] {
    [
      "_tag": "thread.turn.interrupt",
      "type": "thread.turn.interrupt",
      "commandId": UUID().uuidString,
      "threadId": threadId,
      "createdAt": ISO8601DateFormatter().string(from: Date()),
    ]
  }

  static func threadDelete(threadId: ThreadId) -> [String: Any] {
    [
      "_tag": "thread.delete",
      "type": "thread.delete",
      "commandId": UUID().uuidString,
      "threadId": threadId,
    ]
  }

  static func threadMetaUpdate(threadId: ThreadId, title: String? = nil, model: String? = nil) -> [String: Any] {
    var body: [String: Any] = [
      "_tag": "thread.meta.update",
      "type": "thread.meta.update",
      "commandId": UUID().uuidString,
      "threadId": threadId,
    ]
    if let title { body["title"] = title }
    if let model { body["model"] = model }
    return body
  }

  // MARK: - Project Commands

  static func projectAdd(projectId: ProjectId, path: String, title: String) -> [String: Any] {
    [
      "_tag": "project.add",
      "type": "project.add",
      "commandId": UUID().uuidString,
      "projectId": projectId,
      "workspaceRoot": path,
      "title": title,
    ]
  }

  static func projectDelete(projectId: ProjectId) -> [String: Any] {
    [
      "_tag": "project.delete",
      "type": "project.delete",
      "commandId": UUID().uuidString,
      "projectId": projectId,
    ]
  }

  // MARK: - Script Commands

  static func projectScriptAdd(
    projectId: ProjectId, scriptId: String, name: String, command: String, icon: String,
    runOnWorktreeCreate: Bool = false
  ) -> [String: Any] {
    [
      "_tag": "project.script.add",
      "type": "project.script.add",
      "commandId": UUID().uuidString,
      "projectId": projectId,
      "scriptId": scriptId,
      "name": name,
      "command": command,
      "icon": icon,
      "runOnWorktreeCreate": runOnWorktreeCreate,
    ]
  }

  static func projectScriptUpdate(
    projectId: ProjectId, scriptId: String, name: String, command: String, icon: String,
    runOnWorktreeCreate: Bool = false
  ) -> [String: Any] {
    [
      "_tag": "project.script.update",
      "type": "project.script.update",
      "commandId": UUID().uuidString,
      "projectId": projectId,
      "scriptId": scriptId,
      "name": name,
      "command": command,
      "icon": icon,
      "runOnWorktreeCreate": runOnWorktreeCreate,
    ]
  }

  static func projectScriptDelete(projectId: ProjectId, scriptId: String) -> [String: Any] {
    [
      "_tag": "project.script.delete",
      "type": "project.script.delete",
      "commandId": UUID().uuidString,
      "projectId": projectId,
      "scriptId": scriptId,
    ]
  }

  // MARK: - Approval Commands

  static func threadTurnApprove(threadId: ThreadId, approvalRequestId: ApprovalRequestId) -> [String: Any] {
    [
      "_tag": "thread.turn.approve",
      "type": "thread.turn.approve",
      "commandId": UUID().uuidString,
      "threadId": threadId,
      "approvalRequestId": approvalRequestId,
    ]
  }

  static func threadTurnReject(threadId: ThreadId, approvalRequestId: ApprovalRequestId) -> [String: Any] {
    [
      "_tag": "thread.turn.reject",
      "type": "thread.turn.reject",
      "commandId": UUID().uuidString,
      "threadId": threadId,
      "approvalRequestId": approvalRequestId,
    ]
  }
}
