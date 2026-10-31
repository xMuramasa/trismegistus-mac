import SwiftUI

extension View {
    /// For the menu bar label, the one view that is always there: opens the main window when a notification is
    /// clicked, even with the popover and the window closed.
    func opensChatFromNotifications(_ notifications: Notifications) -> some View {
        modifier(OpenWindowOnRequest(notifications: notifications))
    }

    /// For MainWindow: selects the chat of a clicked notification.
    func selectsChatFromNotifications(_ notifications: Notifications, selection: Binding<String?>) -> some View {
        modifier(SelectOnRequest(notifications: notifications, selection: selection))
    }
}

private struct OpenWindowOnRequest: ViewModifier {
    let notifications: Notifications
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onChange(of: notifications.openRequest) { _, id in
            guard id != nil else { return }
            openWindow(id: "main")
            NSApp.activate() // the window may already be open behind another app
        }
    }
}

private struct SelectOnRequest: ViewModifier {
    let notifications: Notifications
    @Binding var selection: String?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: take)
            .onChange(of: notifications.openRequest) { take() }
    }

    private func take() {
        guard let id = notifications.openRequest else { return }
        selection = id
        notifications.openRequest = nil
    }
}
