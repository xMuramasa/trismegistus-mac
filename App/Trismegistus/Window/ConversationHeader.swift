import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Above the open conversation in the window (#68): its avatar, title, pin, tags and the subtitle (source · run ·
/// started) on the left; the token meter, the model, the effort (#74), the terminal and Settings buttons and the actions
/// menu on the right, in the `DetailHeader` with the narrow-window rule (`FittedHeader`: the title keeps 120 pt, the meter
/// then the model pill shorten); the tag editor and errors open under its rule on white.
struct ConversationHeader: View {
    let sessionID: String

    @Environment(AppModel.self) private var model
    @State private var actions = ConversationActions()

    /// The thread's newest part: the header shows and acts on it.
    private var id: String { model.store?.threadTip(of: sessionID) ?? sessionID }
    private var info: SessionInfo? { model.sessions.first { $0.id == id } }

    var body: some View {
        if let info {
            let tags = model.store?.tags[info.id] ?? []
            VStack(spacing: 0) {
                FittedHeader {
                    SourceAvatar(PopoverFormat.source(info.source), size: Size.avatar.header)
                } title: {
                    if actions.renaming == info.id {
                        RenameField(info: info, actions: actions, store: model.store).frame(height: Size.control)
                    } else {
                        Text(PopoverFormat.title(info))
                        if info.isPinned {
                            Image(systemName: Symbol.pinOutline).font(.system(size: Icon.l)).foregroundStyle(Ink.text.secondary)
                                .accessibilityLabel("Pinned")
                        }
                        TagChips(tags: tags, limit: 4)
                    }
                } subtitle: {
                    Text(PopoverFormat.subtitle(info.id, info: info, store: model.store))
                } trailing: { fit in
                    ContextMeter(info: info) { actions.handingOff = info }.environment(\.compactMeter, fit.meterCompact)
                    ModelMenu(info: info, fit: fit)
                    EffortMenu(info: info, fit: fit)
                    DetailTools(section: .chat)
                    Menu {
                        ConversationMenuItems(info: info, actions: actions, store: model.store)
                    } label: {
                        IconCell(symbol: Symbol.ellipsis)
                    }
                    .menuStyle(.button).buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Actions")
                    .accessibilityLabel("Actions")
                }
                if actions.tagging == info.id || actions.error != nil {
                    VStack(spacing: Space.s) {
                        if actions.tagging == info.id, let store = model.store {
                            TagEditor(
                                tags: tags, known: SessionListing.tagCounts(ids: model.sessions.map(\.id), tags: store.tags).map(\.tag),
                                onChange: { actions.setTags(info.id, $0, store: store) }, onDone: { actions.tagging = nil })
                        }
                        ActionError(message: actions.error)
                    }
                    .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                    .background(Ink.surface.raised)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline) }
                }
            }
            .confirmsDelete(actions, store: model.store)
            // A header for another conversation starts clean; a handoff stays in the same thread (its oldest part), so
            // the handoff sheet opened here survives the new part becoming the tip.
            .id(model.store?.olderParts(of: info.id).last ?? info.id)
        }
    }
}

extension EnvironmentValues {
    /// The header's narrow-window rule, stage 1 (#74): the context meter shows only its percentage (`35%`).
    @Entry var compactMeter = false
}
