import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Above the open conversation in the window: source, title, pin, tags, the subtitle (source · run · started) and the
/// same actions menu as its row, in the `DetailHeader`; the tag editor and errors open under its rule on white.
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
                DetailHeader {
                    SourceIcon(PopoverFormat.source(info.source))
                } title: {
                    if actions.renaming == info.id {
                        RenameField(info: info, actions: actions, store: model.store).frame(height: Size.control)
                    } else {
                        Text(PopoverFormat.title(info))
                        if info.isPinned {
                            Image(systemName: "pin.fill").font(.system(size: Icon.m)).opacity(Opacity.secondaryOnDark)
                                .accessibilityLabel("Pinned")
                        }
                        TagChips(tags: tags, limit: 4)
                    }
                } subtitle: {
                    Text(PopoverFormat.subtitle(info.id, info: info, store: model.store))
                } trailing: {
                    ContextMeter(info: info) { actions.handingOff = info }
                    ModelMenu(info: info)
                    // `ConversationMenuButton` with a light icon.
                    Menu {
                        ConversationMenuItems(info: info, actions: actions, store: model.store)
                    } label: {
                        Image(systemName: "ellipsis").typeRole(.button).frame(width: Size.menuButton, height: Size.menuButton).contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
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
