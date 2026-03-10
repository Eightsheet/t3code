#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Chat View

struct ChatView: View {
  @ObservedObject var store: AppStore
  let thread: OrchestrationThread
  @State private var composerText = ""
  @State private var scrollProxy: ScrollViewProxy?
  @State private var isAutoScrolling = true
  @State private var showDiffPanel = false
  @Namespace private var bottomAnchor

  private var timelineEntries: [TimelineEntry] {
    var entries: [TimelineEntry] = []

    for message in thread.messages {
      entries.append(TimelineEntry(
        id: "msg-\(message.id)",
        kind: .message(message),
        createdAt: message.createdAt
      ))
    }

    if let plans = thread.proposedPlans {
      for plan in plans {
        entries.append(TimelineEntry(
          id: "plan-\(plan.id)",
          kind: .proposedPlan(plan),
          createdAt: plan.createdAt
        ))
      }
    }

    for activity in thread.activities {
      if activity.tone == .tool || activity.tone == .approval {
        entries.append(TimelineEntry(
          id: "act-\(activity.id)",
          kind: .activity(activity),
          createdAt: activity.createdAt
        ))
      }
    }

    return entries.sorted { $0.createdAt < $1.createdAt }
  }

  private var isRunning: Bool {
    thread.latestTurn?.state == .running || thread.session?.status == .running
  }

  var body: some View {
    VStack(spacing: 0) {
      chatHeader
      Divider()
      messagesArea
      composerArea
    }
  }

  // MARK: - Header

  private var chatHeader: some View {
    HStack(spacing: T3Design.Spacing.md) {
      VStack(alignment: .leading, spacing: 2) {
        Text(thread.title)
          .font(T3Design.Fonts.headline)
          .lineLimit(1)

        HStack(spacing: T3Design.Spacing.sm) {
          if let project = store.projects.first(where: { $0.id == thread.projectId }) {
            Label(project.title, systemImage: "folder")
              .font(T3Design.Fonts.caption)
              .foregroundStyle(.secondary)
          }

          if let branch = thread.branch {
            Label(branch, systemImage: "arrow.triangle.branch")
              .font(T3Design.Fonts.caption)
              .foregroundStyle(.secondary)
          }

          Text(thread.model)
            .font(T3Design.Fonts.codeSmall)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
        }
      }

      Spacer()

      HStack(spacing: T3Design.Spacing.sm) {
        if isRunning {
          runningIndicator
        }

        runtimeModeToggle

        Button {
          showDiffPanel.toggle()
        } label: {
          Image(systemName: "doc.text.magnifyingglass")
            .font(.system(size: 13))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Toggle diff panel")
      }
    }
    .padding(.horizontal, T3Design.Spacing.xl)
    .padding(.vertical, T3Design.Spacing.md)
    .background(.bar)
  }

  private var runningIndicator: some View {
    HStack(spacing: T3Design.Spacing.xs) {
      PulsingDot()
      Text("Working…")
        .font(T3Design.Fonts.caption)
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(T3Design.accentPurple.opacity(0.1), in: Capsule())
  }

  private var runtimeModeToggle: some View {
    Menu {
      Button {
        // full-access
      } label: {
        Label("Full Access", systemImage: "lock.open")
      }
      Button {
        // approval-required
      } label: {
        Label("Supervised", systemImage: "lock.shield")
      }
    } label: {
      Label(
        thread.runtimeMode == .fullAccess ? "Full Access" : "Supervised",
        systemImage: thread.runtimeMode == .fullAccess ? "lock.open" : "lock.shield"
      )
      .font(T3Design.Fonts.caption)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
  }

  // MARK: - Messages Area

  private var messagesArea: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(timelineEntries) { entry in
            timelineRow(for: entry)
              .id(entry.id)
          }

          if isRunning {
            streamingIndicator
          }

          Color.clear
            .frame(height: 1)
            .id("bottom")
        }
        .padding(.vertical, T3Design.Spacing.md)
      }
      .onAppear { scrollProxy = proxy }
      .onChange(of: thread.messages.count) {
        if isAutoScrolling {
          withAnimation(T3Design.Animation.smooth) {
            proxy.scrollTo("bottom", anchor: .bottom)
          }
        }
      }
      .onChange(of: thread.activities.count) {
        if isAutoScrolling {
          withAnimation(T3Design.Animation.smooth) {
            proxy.scrollTo("bottom", anchor: .bottom)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func timelineRow(for entry: TimelineEntry) -> some View {
    switch entry.kind {
    case .message(let message):
      MessageBubble(message: message)
        .padding(.horizontal, T3Design.Spacing.xl)
        .padding(.vertical, T3Design.Spacing.xs)
        .transition(.opacity.combined(with: .move(edge: .bottom)))

    case .proposedPlan(let plan):
      PlanCard(plan: plan)
        .padding(.horizontal, T3Design.Spacing.xl)
        .padding(.vertical, T3Design.Spacing.xs)

    case .activity(let activity):
      ActivityRow(activity: activity)
        .padding(.horizontal, T3Design.Spacing.xl)
        .padding(.vertical, T3Design.Spacing.xxs)
    }
  }

  private var streamingIndicator: some View {
    HStack(spacing: T3Design.Spacing.sm) {
      ThinkingIndicator()
      Text("Thinking…")
        .font(T3Design.Fonts.caption)
        .foregroundStyle(.tertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, T3Design.Spacing.xl)
    .padding(.vertical, T3Design.Spacing.sm)
  }

  // MARK: - Composer

  private var composerArea: some View {
    VStack(spacing: 0) {
      Divider()

      VStack(spacing: T3Design.Spacing.sm) {
        HStack(alignment: .bottom, spacing: T3Design.Spacing.sm) {
          composerTextField

          VStack(spacing: T3Design.Spacing.xs) {
            if isRunning {
              Button {
                Task { await store.interruptThread(thread.id) }
              } label: {
                Image(systemName: "stop.circle.fill")
                  .font(.system(size: 22))
                  .foregroundStyle(T3Design.errorRed)
              }
              .buttonStyle(.plain)
              .help("Stop")
            } else {
              Button {
                Task { await sendMessage() }
              } label: {
                Image(systemName: "arrow.up.circle.fill")
                  .font(.system(size: 22))
                  .foregroundStyle(
                    composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      ? Color.secondary.opacity(0.4)
                      : T3Design.accentPurple
                  )
              }
              .buttonStyle(.plain)
              .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
              .help("Send message")
              .keyboardShortcut(.return, modifiers: .command)
            }
          }
        }

        composerToolbar
      }
      .padding(.horizontal, T3Design.Spacing.xl)
      .padding(.vertical, T3Design.Spacing.md)
      .background(.bar)
    }
  }

  private var composerTextField: some View {
    ZStack(alignment: .topLeading) {
      if composerText.isEmpty {
        Text("Ask anything… use /plan for planning mode")
          .font(T3Design.Fonts.body)
          .foregroundStyle(.tertiary)
          .padding(.horizontal, T3Design.Spacing.md)
          .padding(.vertical, T3Design.Spacing.sm)
      }

      TextEditor(text: $composerText)
        .font(T3Design.Fonts.body)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 36, maxHeight: 120)
        .padding(.horizontal, T3Design.Spacing.sm)
        .padding(.vertical, T3Design.Spacing.xs)
    }
    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: T3Design.Radius.lg, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: T3Design.Radius.lg, style: .continuous)
        .strokeBorder(T3Design.Colors.border.opacity(0.2), lineWidth: 0.5)
    )
  }

  private var composerToolbar: some View {
    HStack(spacing: T3Design.Spacing.md) {
      Label(thread.model, systemImage: "cpu")
        .font(T3Design.Fonts.caption)
        .foregroundStyle(.secondary)

      Spacer()

      if let turn = thread.latestTurn {
        Text(turnStatusLabel(turn))
          .font(T3Design.Fonts.caption)
          .foregroundStyle(.tertiary)
      }
    }
  }

  // MARK: - Helpers

  private func sendMessage() async {
    let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    composerText = ""
    await store.sendMessage(threadId: thread.id, text: text)
  }

  private func turnStatusLabel(_ turn: OrchestrationLatestTurn) -> String {
    switch turn.state {
    case .running: "Running…"
    case .completed: "Completed"
    case .interrupted: "Interrupted"
    case .error: "Error"
    }
  }
}

// MARK: - Message Bubble

struct MessageBubble: View {
  let message: OrchestrationMessage
  @State private var isHovering = false

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      if message.role == .user {
        Spacer(minLength: 60)
      }

      VStack(alignment: message.role == .user ? .trailing : .leading, spacing: T3Design.Spacing.xs) {
        messageContent

        HStack(spacing: T3Design.Spacing.sm) {
          Text(formattedTime)
            .font(T3Design.Fonts.caption)
            .foregroundStyle(.quaternary)

          if message.streaming {
            ProgressView()
              .scaleEffect(0.5)
              .frame(width: 12, height: 12)
          }

          if isHovering && message.role == .assistant {
            Button {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(message.text, forType: .string)
            } label: {
              Image(systemName: "doc.on.doc")
                .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .transition(.opacity)
          }
        }
      }

      if message.role == .assistant || message.role == .system {
        Spacer(minLength: 60)
      }
    }
    .onHover { isHovering = $0 }
    .animation(T3Design.Animation.quick, value: isHovering)
  }

  @ViewBuilder
  private var messageContent: some View {
    if message.role == .user {
      Text(message.text)
        .font(T3Design.Fonts.body)
        .foregroundStyle(.primary)
        .textSelection(.enabled)
        .padding(.horizontal, T3Design.Spacing.md)
        .padding(.vertical, T3Design.Spacing.sm)
        .background(
          T3Design.accentPurple.opacity(0.08),
          in: RoundedRectangle(cornerRadius: T3Design.Radius.xl, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: T3Design.Radius.xl, style: .continuous)
            .strokeBorder(T3Design.accentPurple.opacity(0.12), lineWidth: 0.5)
        )
    } else {
      MarkdownTextView(text: message.text)
        .padding(.horizontal, T3Design.Spacing.md)
        .padding(.vertical, T3Design.Spacing.sm)
    }
  }

  private var formattedTime: String {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: message.createdAt) else { return "" }
    let timeFormatter = DateFormatter()
    timeFormatter.timeStyle = .short
    return timeFormatter.string(from: date)
  }
}

// MARK: - Markdown Text View

struct MarkdownTextView: View {
  let text: String

  private var parsedBlocks: [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var i = 0
    while i < lines.count {
      let line = lines[i]
      if line.hasPrefix("```") {
        let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var codeLines: [String] = []
        i += 1
        while i < lines.count && !lines[i].hasPrefix("```") {
          codeLines.append(lines[i])
          i += 1
        }
        blocks.append(.codeBlock(language: lang, content: codeLines.joined(separator: "\n")))
        i += 1
      } else {
        blocks.append(.line(line))
        i += 1
      }
    }
    return blocks
  }

  var body: some View {
    VStack(alignment: .leading, spacing: T3Design.Spacing.xs) {
      ForEach(Array(parsedBlocks.enumerated()), id: \.offset) { _, block in
        switch block {
        case .codeBlock(let language, let content):
          codeBlockView(content: content, language: language)
        case .line(let lineStr):
          lineView(lineStr)
        }
      }
    }
  }

  @ViewBuilder
  private func lineView(_ lineStr: String) -> some View {
    if lineStr.hasPrefix("# ") {
      Text(String(lineStr.dropFirst(2)))
        .font(.system(size: 18, weight: .bold))
        .textSelection(.enabled)
    } else if lineStr.hasPrefix("## ") {
      Text(String(lineStr.dropFirst(3)))
        .font(.system(size: 16, weight: .semibold))
        .textSelection(.enabled)
    } else if lineStr.hasPrefix("### ") {
      Text(String(lineStr.dropFirst(4)))
        .font(.system(size: 14, weight: .semibold))
        .textSelection(.enabled)
    } else if lineStr.hasPrefix("- ") || lineStr.hasPrefix("* ") {
      HStack(alignment: .top, spacing: T3Design.Spacing.sm) {
        Text("•")
          .foregroundStyle(.secondary)
        Text(renderInlineMarkdown(String(lineStr.dropFirst(2))))
          .font(T3Design.Fonts.body)
          .textSelection(.enabled)
      }
    } else if lineStr.isEmpty {
      Spacer().frame(height: 4)
    } else {
      Text(renderInlineMarkdown(lineStr))
        .font(T3Design.Fonts.body)
        .textSelection(.enabled)
    }
  }

  private func codeBlockView(content: String, language: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if !language.isEmpty {
        Text(language)
          .font(T3Design.Fonts.codeSmall)
          .foregroundStyle(.tertiary)
          .padding(.horizontal, T3Design.Spacing.md)
          .padding(.top, T3Design.Spacing.sm)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        Text(content)
          .font(T3Design.Fonts.code)
          .textSelection(.enabled)
          .padding(T3Design.Spacing.md)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(T3Design.Colors.codeBg, in: RoundedRectangle(cornerRadius: T3Design.Radius.md, style: .continuous))
  }

  private func renderInlineMarkdown(_ text: String) -> AttributedString {
    // Use SwiftUI's built-in markdown for inline formatting
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
  }
}

private enum MarkdownBlock {
  case codeBlock(language: String, content: String)
  case line(String)
}

// MARK: - Plan Card

struct PlanCard: View {
  let plan: OrchestrationProposedPlan
  @State private var isExpanded = true

  var body: some View {
    VStack(alignment: .leading, spacing: T3Design.Spacing.sm) {
      Button {
        withAnimation(T3Design.Animation.quick) { isExpanded.toggle() }
      } label: {
        HStack(spacing: T3Design.Spacing.sm) {
          Image(systemName: "doc.text")
            .font(.system(size: 12))
            .foregroundStyle(T3Design.accentPurple)

          Text("Proposed Plan")
            .font(T3Design.Fonts.bodyMedium)

          Spacer()

          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
        }
      }
      .buttonStyle(.plain)

      if isExpanded {
        MarkdownTextView(text: plan.planMarkdown)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .cardStyle()
    .subtleBorder()
  }
}

// MARK: - Activity Row

struct ActivityRow: View {
  let activity: ThreadActivity

  var body: some View {
    HStack(spacing: T3Design.Spacing.sm) {
      Image(systemName: iconName)
        .font(.system(size: 10))
        .foregroundStyle(iconColor)
        .frame(width: 16)

      Text(activity.summary)
        .font(T3Design.Fonts.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)

      Spacer()
    }
    .padding(.vertical, 2)
  }

  private var iconName: String {
    switch activity.tone {
    case .tool: "wrench"
    case .approval: "checkmark.shield"
    case .error: "exclamationmark.triangle"
    case .info: "info.circle"
    }
  }

  private var iconColor: Color {
    switch activity.tone {
    case .tool: .secondary
    case .approval: T3Design.warningAmber
    case .error: T3Design.errorRed
    case .info: T3Design.infoBlue
    }
  }
}

// MARK: - Animated Components

struct PulsingDot: View {
  @State private var isPulsing = false

  var body: some View {
    Circle()
      .fill(T3Design.accentPurple)
      .frame(width: 6, height: 6)
      .scaleEffect(isPulsing ? 1.3 : 1.0)
      .opacity(isPulsing ? 0.6 : 1.0)
      .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
      .onAppear { isPulsing = true }
  }
}

struct ThinkingIndicator: View {
  @State private var phase = 0.0

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<3, id: \.self) { i in
        Circle()
          .fill(T3Design.accentPurple.opacity(0.6))
          .frame(width: 5, height: 5)
          .offset(y: sin(phase + Double(i) * 0.8) * 3)
      }
    }
    .onAppear {
      withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
        phase = .pi * 2
      }
    }
  }
}
#endif
