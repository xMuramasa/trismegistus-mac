import SwiftUI
import TrismegistusKit

/// Placeholder: paste the code from `trismegistus-relay pair`.
struct PairingSheet: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var url = AppModel.defaultRelayURL.absoluteString
    @State private var error: String?
    @State private var pairing = false

    var body: some View {
        Form {
            TextField("Pairing code", text: $code)
            TextField("Relay URL", text: $url)
            if let message = error ?? model.keychainError {
                Text(message).foregroundStyle(.red)
            }
            Button("Pair", systemImage: "link") { Task { await pair() } }
                .disabled(pairing || code.isEmpty)
        }
        .padding()
        .frame(width: 320)
    }

    private func pair() async {
        guard let relay = URL(string: url.trimmingCharacters(in: .whitespaces)) else {
            error = "That isn't a URL."
            return
        }
        pairing = true
        defer { pairing = false }
        do {
            try await model.pair(code: code.trimmingCharacters(in: .whitespacesAndNewlines), url: relay)
            error = nil
        } catch {
            self.error = (error as? RelayAPIError)?.message ?? "Pairing failed."
        }
    }
}
