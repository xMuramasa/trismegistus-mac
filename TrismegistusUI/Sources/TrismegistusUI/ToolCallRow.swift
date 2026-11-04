import SwiftUI

/// A tool call as one step (#57, `.tool-row`, `.raw`): a raised row with its icon, tool name, the command's first line,
/// duration, status and fold chevron, paper under the pointer; the raw output folds under it, terminal-red when the call
/// failed. Rows stack edge to edge, a 0.5 pt rule above each.
public struct ToolCallRow: View {
    let symbol: String
    let tool: String
    let command: String
    let duration: String?
    /// Nil while it runs: no status yet.
    let failed: Bool?
    let output: String?
    let nameWidth: CGFloat
    @Binding var isOpen: Bool
    var forceHovered = false  // snapshots and previews: hover can't be set from outside
    @State private var hovered = false

    public init(
        symbol: String, tool: String, command: String, duration: String? = nil, failed: Bool? = nil, output: String? = nil,
        nameWidth: CGFloat = Size.toolRow.name, isOpen: Binding<Bool>
    ) {
        self.symbol = symbol
        self.tool = tool
        self.command = command
        self.duration = duration
        self.failed = failed
        self.output = output
        self.nameWidth = nameWidth
        self._isOpen = isOpen
    }

    static func firstLine(_ command: String) -> String {
        String(command.trimmingCharacters(in: .whitespacesAndNewlines).prefix { !$0.isNewline })
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button { isOpen.toggle() } label: { row }
                .buttonStyle(.plain)
                .allowsHitTesting(output != nil)
                .accessibilityHint(output == nil ? "" : isOpen ? "Hides the output" : "Shows the output")
                .help(command)
            if isOpen, let output {
                Text(output).typeRole(.monoSmall).foregroundStyle(failed == true ? Ink.status.error : Ink.text.primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.surface.raised)
            }
        }
        .onHover { hovered = $0 }
    }

    private var row: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).font(.system(size: Icon.l)).frame(width: Size.toolRow.cell).accessibilityHidden(true)
            Text(tool).frame(width: nameWidth, alignment: .leading)
            Text(Self.firstLine(command)).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            // The cell stays while the time is unknown, so the status column lines up down the list.
            Text(duration ?? "").foregroundStyle(Ink.text.secondary).frame(width: Size.toolRow.duration, alignment: .trailing)
            status.frame(width: Size.toolRow.status, alignment: .leading)
            Group {
                if output != nil { Image(systemName: Symbol.fold(isOpen: isOpen)).font(.system(size: Icon.l)) }
            }
            .frame(width: Size.toolRow.cell)
            .accessibilityHidden(true)
        }
        .typeRole(.monoSmall)
        .lineLimit(1)
        .foregroundStyle(Ink.text.primary)
        .padding(.horizontal, Space.m)
        .frame(height: Size.rowTool)
        .background(hovered || forceHovered ? Ink.surface.window : Ink.surface.raised)
        .overlay(alignment: .top) { Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairlineFine) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        if let failed {
            HStack(spacing: Space.xs) {
                Image(systemName: failed ? Symbol.close : Symbol.check).font(.system(size: Icon.m, weight: .semibold))
                    .accessibilityHidden(true)
                Text(failed ? "Failed" : "OK").typeRole(.label)
            }
            .foregroundStyle(failed ? Ink.status.error : Ink.status.ok)
        }
    }
}

/// A narration line between tool rows (#57, `.say`), a 0.5 pt rule above it.
public struct ToolNarration: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text).typeRole(.callout).foregroundStyle(Ink.text.secondary)
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface.raised)
            .overlay(alignment: .top) { Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairlineFine) }
    }
}
