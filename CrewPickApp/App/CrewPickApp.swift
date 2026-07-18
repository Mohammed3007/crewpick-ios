import SwiftUI

@main
struct CrewPickApp: App {
    @UIApplicationDelegateAdaptor(CrewPickAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel(store: SampleData.store(), currentUser: SampleData.alex)
    @StateObject private var notifications = NotificationManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(notifications)
                .tint(CrewPickTheme.accent)
                .onOpenURL { url in Task { await model.handle(url: url) } }
                .task { await notifications.registerIfAuthorized() }
                .onChange(of: notifications.deviceToken) { _, token in
                    guard let token else { return }
                    Task { await model.registerDeviceToken(token) }
                }
        }
    }
}
