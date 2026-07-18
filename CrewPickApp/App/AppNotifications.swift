import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    enum PermissionState: Equatable {
        case unknown
        case notRequested
        case denied
        case authorized

        var label: String {
            switch self {
            case .unknown: "Checking…"
            case .notRequested: "Not enabled"
            case .denied: "Disabled in Settings"
            case .authorized: "Enabled"
            }
        }
    }

    static let shared = NotificationManager()

    @Published private(set) var permissionState: PermissionState = .unknown
    @Published private(set) var deviceToken: Data?
    @Published private(set) var registrationError: String?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: permissionState = .notRequested
        case .denied: permissionState = .denied
        case .authorized, .provisional, .ephemeral: permissionState = .authorized
        @unknown default: permissionState = .unknown
        }
    }

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshPermission()
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        } catch {
            registrationError = "CrewPick couldn't request notification permission."
        }
    }

    func registerIfAuthorized() async {
        await refreshPermission()
        if permissionState == .authorized { UIApplication.shared.registerForRemoteNotifications() }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func received(deviceToken: Data) {
        self.deviceToken = deviceToken
        registrationError = nil
    }

    func failedToRegister(_ error: Error) {
        registrationError = "Push registration is unavailable on this device."
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}

@MainActor
final class CrewPickAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationManager.shared.received(deviceToken: deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationManager.shared.failedToRegister(error)
    }
}
