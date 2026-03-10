#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Diff Panel

struct DiffPanel: View {
  @ObservedObject var store: AppStore
  let thread: OrchestrationThread
  @State private var diffs: [FileDiff] = []
  @State private var selectedTurnId: TurnId?
  @State private var selectedFileIndex: Int?
  @State private var isLoading = false
  @State private var viewMode: DiffViewMode = .stacked

  enum DiffViewMode: String, CaseIterable {
    case stacked = "Stacked"
    case split = "Split"
  }

  var body: some View {
    VStack(spacing: 0) {
      diffHeader
      Divider()

      if let checkpoints = thread.checkpoints, !checkpoints.isEmpty {
        turnChipBar(checkpoints: checkpoints)
        Divider()
      }

      if isLoading {
        ProgressView("Loading diffs…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if diffs.isEmpty {
        emptyDiffState
      } else {
        diffContent
      }
    }
    .frame(minWidth: 320)
    .task { await loadDiffs() }
    .onChange(of: selectedTurnId) {
      Task { await loadDiffs() }
    }
  }

  // MARK: - Header

  private var diffHeader: some View {
    HStack(spacing: T3Design.Spacing.md) {
      Image(systemName: "doc.text.magnifyingglass")
        .foregroundStyle(T3Design.accentPurple)
      Text("Changes")
        .font(T3Design.Fonts.bodyMedium)

      Spacer()

      Picker("View", selection: $viewMode) {
        ForEach(DiffViewMode.allCases, id: \.self) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .frame(width: 140)

      Button { store.showDiffPanel = false } label: {
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

  // MARK: - Turn chips

  private func turnChipBar(checkpoints: [CheckpointSummary]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: T3Design.Spacing.xs) {
        turnChip(label: "All", turnId: nil, isSelected: selectedTurnId == nil)

        ForEach(Array(checkpoints.enumerated()), id: \.element.turnId) { index, checkpoint in
          turnChip(
            label: "Turn \(index + 1)",
            turnId: checkpoint.turnId,
            isSelected: selectedTurnId == checkpoint.turnId,
            fileCount: checkpoint.files.count
          )
        }
      }
      .padding(.horizontal, T3Design.Spacing.md)
      .padding(.vertical, T3Design.Spacing.sm)
    }
    .background(T3Design.Colors.surfaceSecondary)
  }

  private func turnChip(label: String, turnId: TurnId?, isSelected: Bool, fileCount: Int? = nil) -> some View {
    Button {
      selectedTurnId = turnId
    } label: {
      HStack(spacing: 4) {
        Text(label)
          .font(T3Design.Fonts.caption)

        if let count = fileCount {
          Text("\(count)")
            .font(T3Design.Fonts.codeSmall)
            .foregroundStyle(.tertiary)
        }
      }
      .padding(.horizontal, T3Design.Spacing.sm)
      .padding(.vertical, T3Design.Spacing.xxs)
      .background(
        isSelected ? T3Design.accentPurple.opacity(0.15) : T3Design.Colors.surface.opacity(0.5),
        in: Capsule()
      )
      .overlay(Capsule().strokeBorder(isSelected ? T3Design.accentPurple.opacity(0.3) : Color.clear, lineWidth: 1))
    }
    .buttonStyle(.plain)
  }

  // MARK: - Diff content

  private var diffContent: some View {
    ScrollView {
      LazyVStack(spacing: T3Design.Spacing.md) {
        ForEach(Array(diffs.enumerated()), id: \.element.id) { index, diff in
          fileDiffCard(diff: diff, index: index)
        }
      }
      .padding(T3Design.Spacing.md)
    }
  }

  private func fileDiffCard(diff: FileDiff, index: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: T3Design.Spacing.sm) {
        Image(systemName: fileIcon(for: diff.kind))
          .font(.system(size: 11))
          .foregroundStyle(fileColor(for: diff.kind))

        Text(diff.path)
          .font(T3Design.Fonts.codeSmall)
          .lineLimit(1)
          .truncationMode(.middle)

        Spacer()

        HStack(spacing: T3Design.Spacing.xs) {
          if diff.additions > 0 {
            Text("+\(diff.additions)")
              .font(T3Design.Fonts.codeSmall)
              .foregroundStyle(T3Design.successGreen)
          }
          if diff.deletions > 0 {
            Text("-\(diff.deletions)")
              .font(T3Design.Fonts.codeSmall)
              .foregroundStyle(T3Design.errorRed)
          }
        }
      }
      .padding(.horizontal, T3Design.Spacing.md)
      .padding(.vertical, T3Design.Spacing.sm)
      .background(T3Design.Colors.surfaceSecondary)
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation(T3Design.Animation.quick) {
          selectedFileIndex = selectedFileIndex == index ? nil : index
        }
      }

      if selectedFileIndex == index || selectedFileIndex == nil {
        ForEach(diff.hunks) { hunk in
          VStack(alignment: .leading, spacing: 0) {
            Text(hunk.header)
              .font(T3Design.Fonts.codeSmall)
              .foregroundStyle(.tertiary)
              .padding(.horizontal, T3Design.Spacing.md)
              .padding(.vertical, 2)
              .background(T3Design.Colors.surfaceTertiary.opacity(0.5))
              .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(hunk.lines) { line in
              diffLineView(line)
            }
          }
        }
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: T3Design.Radius.md, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: T3Design.Radius.md, style: .continuous)
        .strokeBorder(T3Design.Colors.border.opacity(0.2), lineWidth: 0.5)
    )
  }

  private func diffLineView(_ line: DiffLine) -> some View {
    HStack(spacing: 0) {
      HStack(spacing: 0) {
        Text(line.oldLineNumber.map(String.init) ?? "")
          .frame(width: 36, alignment: .trailing)
        Text(line.newLineNumber.map(String.init) ?? "")
          .frame(width: 36, alignment: .trailing)
      }
      .font(T3Design.Fonts.codeSmall)
      .foregroundStyle(.quaternary)
      .padding(.trailing, T3Design.Spacing.sm)

      Text(line.content)
        .font(T3Design.Fonts.code)
        .textSelection(.enabled)
        .lineLimit(1)

      Spacer()
    }
    .padding(.horizontal, T3Design.Spacing.sm)
    .padding(.vertical, 1)
    .background(diffLineBackground(line.type))
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func diffLineBackground(_ type: String) -> Color {
    switch type {
    case "add": T3Design.successGreen.opacity(0.08)
    case "delete": T3Design.errorRed.opacity(0.08)
    default: .clear
    }
  }

  // MARK: - Empty state

  private var emptyDiffState: some View {
    VStack(spacing: T3Design.Spacing.lg) {
      Image(systemName: "doc.text.magnifyingglass")
        .font(.system(size: 32))
        .foregroundStyle(.tertiary)
      VStack(spacing: T3Design.Spacing.xs) {
        Text("No changes yet")
          .font(T3Design.Fonts.bodyMedium)
        Text("File changes from AI turns will appear here")
          .font(T3Design.Fonts.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  // MARK: - Helpers

  private func loadDiffs() async {
    isLoading = true
    diffs = await store.fetchDiffs(for: thread.id, turnId: selectedTurnId)
    isLoading = false
  }

  private func fileIcon(for kind: String) -> String {
    switch kind {
    case "added": "plus.circle"
    case "deleted": "minus.circle"
    case "modified": "pencil.circle"
    case "renamed": "arrow.right.circle"
    default: "doc.circle"
    }
  }

  private func fileColor(for kind: String) -> Color {
    switch kind {
    case "added": T3Design.successGreen
    case "deleted": T3Design.errorRed
    case "modified": T3Design.warningAmber
    case "renamed": T3Design.infoBlue
    default: .secondary
    }
  }
}
#endif
