import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// First launch (05, 05b): run `pair` on the server, paste the code or the QR payload, press PAIR.
/// Success needs no handling here: `model.needsPairing` turns false and the popover swaps to the session list.
struct PairingSheet: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""
    @State private var error: String?
    @State private var pairing = false

    private static let command = "docker exec -it trismegistus-relay \\\n  trismegistus-relay pair --name macbook"

    /// The relay the code will be traded at: the payload's, else the default.
    private var relay: (url: URL, fromPayload: Bool) {
        if let url = (try? PairingPayload.parse(input))?.relayURL { return (url, true) }
        return (AppModel.defaultRelayURL, false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 14) {
                Text("Pair this Mac").typeRole(.title)
                step("01", "On optiplex, create a one-time code:") {
                    CodeBlockView(language: "bash", code: Self.command)
                }
                step("02", "Paste the code or the QR payload:") {
                    VStack(alignment: .leading, spacing: 6) {
                        EndfieldTextField("XXXX-XXXX-XXXX", text: $input, isError: error != nil)
                            .onSubmit { Task { await pair() } }
                            .onChange(of: input) { error = nil }
                        if let message = error ?? model.keychainError {
                            Text(message).typeRole(.caption).foregroundStyle(Theme.red)
                        } else {
                            HStack(spacing: 6) {
                                Text("Relay").typeRole(.label).foregroundStyle(Theme.secondary)
                                Text(relay.url.host() ?? "").typeRole(.monoSmall)
                                Text(relay.fromPayload ? "from the payload" : "default")
                                    .typeRole(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                        HStack(spacing: 10) {
                            EndfieldButton("Pair", symbol: Symbol.link, kind: .primary) { Task { await pair() } }
                                .disabled(pairing || input.allSatisfy(\.isWhitespace))
                            Text("single use · valid 10 min").typeRole(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14)
            Spacer(minLength: 0)
            KeyHintStrip([("⌘V", "paste"), ("↩", "pair"), ("esc", "close")])
        }
        .frame(width: 380, height: 460)
        .background(Theme.paper)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            TMark().padding(.top, 2)
            TitleRule("Trismegistus")
            StatusReadout(.offline, detail: "not paired").fixedSize()
        }
        .padding(.horizontal, 16).padding(.top, 14)
    }

    private func step(_ number: String, _ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number).typeRole(.monoSmall).foregroundStyle(Theme.secondary).padding(.top, 1)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).typeRole(.body)
                content()
            }
        }
    }

    private func pair() async {
        guard !pairing else { return }
        let payload: PairingPayload
        do { payload = try PairingPayload.parse(input) } catch {
            self.error = error.localizedDescription
            return
        }
        pairing = true
        defer { pairing = false }
        do {
            try await model.pair(code: payload.code, url: payload.relayURL ?? AppModel.defaultRelayURL)
        } catch {
            self.error = Self.message(for: error)
        }
    }

    /// What `POST /api/pair` and the Keychain can throw, in words for the field.
    static func message(for error: any Error) -> String {
        switch error {
        case let e as RelayAPIError where e.code == .unauthorized: "Code expired or already used. Run pair again for a new one."
        case let e as RelayAPIError where e.code == .rateLimited: "Too many attempts. Wait a minute, then try again."
        case let e as RelayAPIError: e.message
        case is URLError: "Can't reach the relay. Check the network and the address."
        case is KeychainError: "Paired, but the token couldn't be saved to the Keychain."
        default: "Pairing failed."
        }
    }
}
