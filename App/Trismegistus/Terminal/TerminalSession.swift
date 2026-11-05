import Foundation
import Observation
import TrismegistusKit
import TrismegistusUI

/// The drawer's one shell (#64), on the host over the relay. Shared rather than the window's state: closing the window,
/// like hiding the drawer, keeps the shell for the rest of the app's run. An ended shell stays ended until the next open
/// or the next Return; nothing here reconnects on its own.
@MainActor @Observable
final class TerminalSession {
    static let shared = TerminalSession()

    private(set) var isShown = false
    @ObservationIgnored let screen = TerminalScreen()
    /// Nil: no shell.
    @ObservationIgnored private var link: TerminalLink?
    @ObservationIgnored private var model: AppModel?

    private init() {
        screen.onInput = { [weak self] in self?.input($0) }
        screen.onResize = { [weak self] in self?.link?.resize(cols: $0, rows: $1) }
    }

    /// From the window, which has the app's model. Unpairing or pairing anew ends the shell with the token it ran on.
    func attach(_ model: AppModel) {
        guard self.model == nil else { return }
        self.model = model
        Task { [weak self] in
            var paired = model.store.map(ObjectIdentifier.init)
            for await store in Observations({ model.store.map(ObjectIdentifier.init) }) where store != paired {
                paired = store
                self?.end()
            }
        }
    }

    func toggle() {
        isShown.toggle()
        if isShown { start() }
    }

    private func input(_ bytes: Data) {
        if let link {
            link.write(bytes)
        } else if bytes.contains(0x0D) {
            start()
        }
    }

    private func start() {
        guard link == nil else { return }
        guard let model, model.store != nil, let token = try? KeychainTokenStore().token() else {
            screen.notice("[not paired]")
            return
        }
        let (cols, rows) = screen.size
        let link = TerminalLink(relayURL: model.relayURL, token: token, cols: cols, rows: rows)
        self.link = link
        Task { [weak self] in
            // One frame at a time: a screen that falls behind slows the shell instead of queueing here.
            while let output = await link.next() {
                switch output {
                case .bytes(let bytes): self?.screen.feed(bytes)
                case .state(let state):
                    // Not a link `end()` already let go: a newer one may be running.
                    guard let self, self.link === link, let notice = state.notice else { continue }
                    screen.notice(notice)
                    self.link = nil
                }
            }
        }
    }

    private func end() {
        guard let link else { return }
        self.link = nil
        Task { await link.close() }
    }
}
