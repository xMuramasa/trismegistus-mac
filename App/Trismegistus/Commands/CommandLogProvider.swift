import SwiftUI
import TrismegistusKit

extension View {
    /// Gives the window's views (`@Environment(CommandLog.self)`) a CommandLog for the current connection, cached in the
    /// app's Caches folder, one file per relay.
    func providesCommandLog(_ model: AppModel) -> some View {
        modifier(CommandLogProvider(model: model))
    }
}

extension CommandLog {
    static func cacheURL(for relay: URL) -> URL {
        URL.cachesDirectory.appending(path: "commands-\(relay.host() ?? "relay").json")
    }
}

private struct CommandLogProvider: ViewModifier {
    let model: AppModel
    @State private var log: CommandLog?

    func body(content: Content) -> some View {
        content
            .environment(log)
            .onChange(of: model.store.map(ObjectIdentifier.init), initial: true) {
                log = model.store.map { CommandLog(rest: $0.rest, cacheURL: CommandLog.cacheURL(for: model.relayURL)) }
            }
    }
}
