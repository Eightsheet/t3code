#if canImport(SwiftUI) && os(macOS)
import AppKit
import SwiftUI

// MARK: - Plan Sidebar

struct PlanSidebar: View {
  @ObservedObject var store: AppStore
  let thread: OrchestrationThread
  @State private var isExpanded = true

  private var activePlan: OrchestrationProposedPlan? {
    thread.proposedPlans?.last
  }

  var body: some View {
    VStack(spacing: 0) {
      planHeader
      Divider()

      if let plan = activePlan {
        planContent(plan)
      } else {
        emptyPlanState
      }
    }
    .frame(width: 340)
  }

  // MARK: - Header

  private var planHeader: some View {
    HStack(spacing: T3Design.Spacing.md) {
      Image(systemName: "list.bullet.clipboard")
        .foregroundStyle(T3Design.accentPurple)
      Text("Plan")
        .font(T3Design.Fonts.bodyMedium)

      Spacer()

      if activePlan != nil {
        planActionsMenu
      }

      Button { store.showPlanSidebar = false } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .medium))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, T3Design.Spacing.md)
    .padding(.vertical, T3Design.Spacing.sm)
    .background(.bar)
  }

  private var planActionsMenu: some View {
    Menu {
      Button {
        if let plan = activePlan {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(plan.planMarkdown, forType: .string)
          store.addToast(.success("Plan copied to clipboard"))
        }
      } label: {
        Label("Copy to clipboard", systemImage: "doc.on.doc")
      }

      Button {
        exportPlanAsFile()
      } label: {
        Label("Download as Markdown", systemImage: "arrow.down.doc")
      }

      Button {
        savePlanToWorkspace()
      } label: {
        Label("Save to workspace", systemImage: "square.and.arrow.down")
      }
    } label: {
      Image(systemName: "ellipsis.circle")
        .font(.system(size: 13))
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
  }

  // MARK: - Plan content

  private func planContent(_ plan: OrchestrationProposedPlan) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: T3Design.Spacing.md) {
        // Plan timestamp
        HStack(spacing: T3Design.Spacing.sm) {
          Image(systemName: "clock")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
          Text(formatTime(plan.createdAt))
            .font(T3Design.Fonts.caption)
            .foregroundStyle(.tertiary)
        }

        // Steps from markdown
        planStepsView(plan.planMarkdown)

        // Full markdown (collapsible)
        DisclosureGroup(isExpanded: $isExpanded) {
          MarkdownTextView(text: plan.planMarkdown)
            .padding(.top, T3Design.Spacing.sm)
        } label: {
          Text("Full plan")
            .font(T3Design.Fonts.bodyMedium)
        }
      }
      .padding(T3Design.Spacing.md)
    }
  }

  private func planStepsView(_ markdown: String) -> some View {
    let steps = extractPlanSteps(from: markdown)
    return VStack(alignment: .leading, spacing: T3Design.Spacing.sm) {
      ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
        HStack(alignment: .top, spacing: T3Design.Spacing.sm) {
          stepStatusIcon(for: step, index: index, total: steps.count)
            .frame(width: 18)

          VStack(alignment: .leading, spacing: 2) {
            Text(step.text)
              .font(T3Design.Fonts.body)
              .foregroundStyle(step.isCompleted ? .secondary : .primary)
              .strikethrough(step.isCompleted)

            if let detail = step.detail {
              Text(detail)
                .font(T3Design.Fonts.caption)
                .foregroundStyle(.tertiary)
            }
          }
        }
      }
    }
  }

  @ViewBuilder
  private func stepStatusIcon(for step: PlanStep, index: Int, total: Int) -> some View {
    if step.isCompleted {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 14))
        .foregroundStyle(T3Design.successGreen)
    } else if index == 0 || (index > 0 && index < total) {
      Image(systemName: "circle")
        .font(.system(size: 14))
        .foregroundStyle(.tertiary)
    } else {
      Image(systemName: "circle")
        .font(.system(size: 14))
        .foregroundStyle(.quaternary)
    }
  }

  // MARK: - Empty state

  private var emptyPlanState: some View {
    VStack(spacing: T3Design.Spacing.lg) {
      Image(systemName: "list.bullet.clipboard")
        .font(.system(size: 32))
        .foregroundStyle(.tertiary)
      VStack(spacing: T3Design.Spacing.xs) {
        Text("No plan yet")
          .font(T3Design.Fonts.bodyMedium)
        Text("Use /plan in the composer to create a plan")
          .font(T3Design.Fonts.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Helpers

  private struct PlanStep {
    let text: String
    let detail: String?
    let isCompleted: Bool
  }

  private func extractPlanSteps(from markdown: String) -> [PlanStep] {
    let lines = markdown.components(separatedBy: "\n")
    var steps: [PlanStep] = []
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
        steps.append(PlanStep(text: String(trimmed.dropFirst(6)), detail: nil, isCompleted: true))
      } else if trimmed.hasPrefix("- [ ] ") {
        steps.append(PlanStep(text: String(trimmed.dropFirst(6)), detail: nil, isCompleted: false))
      } else if trimmed.hasPrefix("- ") && !trimmed.hasPrefix("---") {
        steps.append(PlanStep(text: String(trimmed.dropFirst(2)), detail: nil, isCompleted: false))
      }
    }
    return steps
  }

  private func formatTime(_ iso: String) -> String {
    let formatter = ISO8601DateFormatter()
    guard let date = formatter.date(from: iso) else { return iso }
    let timeFormatter = DateFormatter()
    timeFormatter.timeStyle = .short
    timeFormatter.dateStyle = .short
    return timeFormatter.string(from: date)
  }

  private func exportPlanAsFile() {
    guard let plan = activePlan else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.plainText]
    panel.nameFieldStringValue = "plan.md"
    if panel.runModal() == .OK, let url = panel.url {
      try? plan.planMarkdown.write(to: url, atomically: true, encoding: .utf8)
      store.addToast(.success("Plan exported"))
    }
  }

  private func savePlanToWorkspace() {
    guard let plan = activePlan,
      let project = store.projects.first(where: { $0.id == thread.projectId })
    else { return }
    let workspaceURL = URL(fileURLWithPath: project.workspaceRoot)
    let fileURL = workspaceURL.appendingPathComponent("PLAN.md")
    do {
      try plan.planMarkdown.write(to: fileURL, atomically: true, encoding: .utf8)
      store.addToast(.success("Plan saved to workspace"))
    } catch {
      store.addToast(.error("Failed to save plan: \(error.localizedDescription)"))
    }
  }
}
#endif
