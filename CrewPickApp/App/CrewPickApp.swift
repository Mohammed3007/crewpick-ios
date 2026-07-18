import SwiftUI

@main
struct CrewPickApp: App {
    @StateObject private var model = AppModel(store: SampleData.store(), currentUser: SampleData.alex)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(CrewPickTheme.accent)
        }
    }
}

