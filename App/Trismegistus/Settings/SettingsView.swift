import SwiftUI

/// Placeholder: relay, device, status, unpair.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var error: String?

    var body: some View {
        Form {
            LabeledContent("Relay", value: model.relayURL.absoluteString)
            LabeledContent("Device", value: model.deviceName ?? "Not paired")
            LabeledContent("Status", value: String(describing: model.connection))
            if let error { Text(error).foregroundStyle(.red) }
            Button("Unpair") {
                Task {
                    do { try await model.unpair() } catch { self.error = "Can't remove the token from the Keychain." }
                }
            }
            .disabled(model.store == nil)
        }
        .padding()
        .frame(width: 420)
    }
}
