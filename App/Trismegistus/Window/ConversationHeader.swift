import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Above the open conversation in the window: source, title, pin, tags, the subtitle (source · run · started) and the
/// same actions menu as its row. Its top row continues the toolbar's steel strip (#30); the tag editor and errors open
/// below it on white; the title rule ends it.
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
                HStack(spacing: 10) {
                    SourceIcon(PopoverFormat.source(info.source))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 10) {
                            if actions.renaming == info.id {
                                RenameField(info: info, actions: actions, store: model.store).frame(height: 30)
                            } else {
                                Text(PopoverFormat.title(info)).typeRole(.title).lineLimit(1)
                                if info.isPinned {
                                    Image(systemName: "pin.fill").font(.system(size: 11)).opacity(0.7)
                                        .accessibilityLabel("Pinned")
                                }
                                TagChips(tags: tags, limit: 4)
                            }
                        }
                        Text(PopoverFormat.subtitle(info.id, info: info, store: model.store))
                            .typeRole(.monoSmall).opacity(0.7).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    ContextMeter(info: info) { actions.handingOff = info }
                    ModelMenu(info: info)
                    // `ConversationMenuButton` with a light icon.
                    Menu {
                        ConversationMenuItems(info: info, actions: actions, store: model.store)
                    } label: {
                        Image(systemName: "ellipsis").typeRole(.button).frame(width: 22, height: 22).contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Actions")
                    .accessibilityLabel("Actions")
                }
                .foregroundStyle(Theme.onSteel)
                .environment(\.onSteel, true)
                .padding(.horizontal, 16).padding(.vertical, 8)
                // Reaches 1 pt up over the rule under the toolbar's part, so the two parts meet without a seam.
                .background { TopBarBackdrop().padding(.top, -1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.steelRule).frame(height: 1) }
                if actions.tagging == info.id || actions.error != nil {
                    VStack(spacing: 8) {
                        if actions.tagging == info.id, let store = model.store {
                            TagEditor(
                                tags: tags, known: SessionListing.tagCounts(ids: model.sessions.map(\.id), tags: store.tags).map(\.tag),
                                onChange: { actions.setTags(info.id, $0, store: store) }, onDone: { actions.tagging = nil })
                        }
                        ActionError(message: actions.error)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.raised)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.rule).frame(height: 1) }
                }
                // Endfield's title rule between the header and the messages (the draft, #32); the chat's padding is
                // the space below it.
                SegmentRule((48, 120, 24), height: 4, hairline: false)
                    .padding(.leading, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(EndfieldBackdrop())
            }
            .confirmsDelete(actions, store: model.store)
            // A header for another conversation starts clean; a handoff stays in the same thread (its oldest part), so
            // the handoff sheet opened here survives the new part becoming the tip.
            .id(model.store?.olderParts(of: info.id).last ?? info.id)
        }
    }
}
