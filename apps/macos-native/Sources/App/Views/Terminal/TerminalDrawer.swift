#if canImport(SwiftUI) && os(macOS)
import SwiftUI

// MARK: - Terminal Drawer

struct TerminalDrawer: View {
  @ObservedObject var store: AppStore
  let thread: OrchestrationThread
  @State private var isDragging = false

  private var terminals: [TerminalInfo] {
    store.terminalsByThread[thread.id] ?? []
  }

  private let minHeight: CGFloat = 180
  private let maxHeightRatio: CGFloat = 0.75

  var body: some View {
    VStack(spacing: 0) {
      resizeHandle
      Divider()
      terminalHeader
      Divider()
      terminalContent
    }
    .frame(height: store.terminalDrawerHeight)
    .background(T3Design.Colors.surface)
  }

  // MARK: - Resize handle

  private var resizeHandle: some View {
    Rectangle()
      .fill(Color.clear)
      .frame(height: 6)
      .contentShape(Rectangle())
      .cursor(.resizeUpDown)
      .gesture(
        DragGesture()
          .onChanged { value in
            isDragging = true
            let newHeight = store.terminalDrawerHeight - value.translation.height
            store.terminalDrawerHeight = max(minHeight, min(newHeight, 600))
          }
          .onEnded { _ in isDragging = false }
      )
      .overlay(
        RoundedRectangle(cornerRadius: 1.5)
          .fill(.tertiary)
          .frame(width: 36, height: 3)
      )
  }

  // MARK: - Header

  private var terminalHeader: some View {
    HStack(spacing: T3Design.Spacing.sm) {
      Image(systemName: "terminal")
        .foregroundStyle(T3Design.accentPurple)

      // Terminal tabs
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
          ForEach(terminals) { terminal in
            terminalTab(terminal)
          }
        }
      }

      Spacer()

      HStack(spacing: T3Design.Spacing.xs) {
        Button {
          store.addTerminal(for: thread.id)
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("New terminal")
        .disabled(terminals.count >= 8)

        Button {
          store.showTerminalDrawer = false
        } label: {
          Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Close terminal")
      }
    }
    .padding(.horizontal, T3Design.Spacing.md)
    .padding(.vertical, T3Design.Spacing.xs)
    .background(.bar)
  }

  private func terminalTab(_ terminal: TerminalInfo) -> some View {
    HStack(spacing: T3Design.Spacing.xs) {
      if terminal.isRunning {
        Circle()
          .fill(T3Design.successGreen)
          .frame(width: 5, height: 5)
      }

      Text(terminal.label)
        .font(T3Design.Fonts.caption)
        .lineLimit(1)

      Button {
        store.removeTerminal(for: thread.id, terminalId: terminal.id)
      } label: {
        Image(systemName: "xmark")
          .font(.system(size: 8, weight: .bold))
      }
      .buttonStyle(.plain)
      .foregroundStyle(.quaternary)
      .opacity(store.activeTerminalId == terminal.id ? 1 : 0)
    }
    .padding(.horizontal, T3Design.Spacing.sm)
    .padding(.vertical, T3Design.Spacing.xxs)
    .background(
      store.activeTerminalId == terminal.id
        ? T3Design.Colors.surface
        : Color.clear,
      in: RoundedRectangle(cornerRadius: T3Design.Radius.sm)
    )
    .contentShape(Rectangle())
    .onTapGesture {
      store.activeTerminalId = terminal.id
    }
  }

  // MARK: - Terminal content

  private var terminalContent: some View {
    Group {
      if terminals.isEmpty {
        emptyTerminalState
      } else {
        // Terminal placeholder — real terminal emulation requires SwiftTerm
        terminalPlaceholder
      }
    }
  }

  private var terminalPlaceholder: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let activeId = store.activeTerminalId,
        let terminal = terminals.first(where: { $0.id == activeId })
      {
        ScrollView {
          VStack(alignment: .leading, spacing: 2) {
            Text("$ \(terminal.label.lowercased()) ready")
              .font(T3Design.Fonts.code)
              .foregroundStyle(T3Design.successGreen)

            Text("Terminal emulation requires SwiftTerm integration.")
              .font(T3Design.Fonts.code)
              .foregroundStyle(.secondary)

            Text("Process output will stream here when connected to the backend.")
              .font(T3Design.Fonts.code)
              .foregroundStyle(.tertiary)
          }
          .padding(T3Design.Spacing.md)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .background(Color(nsColor: .init(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)))
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyTerminalState: some View {
    VStack(spacing: T3Design.Spacing.md) {
      Image(systemName: "terminal")
        .font(.system(size: 24))
        .foregroundStyle(.tertiary)

      Text("No terminals")
        .font(T3Design.Fonts.caption)
        .foregroundStyle(.secondary)

      Button("New Terminal") {
        store.addTerminal(for: thread.id)
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .init(red: 0.08, green: 0.08, blue: 0.1, alpha: 1)))
  }
}

// MARK: - Cursor Extension

extension View {
  func cursor(_ cursor: NSCursor) -> some View {
    onHover { inside in
      if inside {
        cursor.push()
      } else {
        NSCursor.pop()
      }
    }
  }
}
#endif
