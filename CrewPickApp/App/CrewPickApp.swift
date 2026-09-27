import AuthenticationServices
import SwiftUI
import Supabase

@main
struct CrewPickApp: App {
    @UIApplicationDelegateAdaptor(CrewPickAppDelegate.self) private var appDelegate
    @StateObject private var auth = ProductionAuthService()
    @StateObject private var previewModel = AppModel(store: SampleData.store(), currentUser: SampleData.alex)
    @StateObject private var notifications = NotificationManager.shared

    private var usesLocalPreview: Bool {
        !auth.isConfigured || ProcessInfo.processInfo.arguments.contains("-useLocalPreview")
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if usesLocalPreview {
                    PreviewAppRoot(model: previewModel, notifications: notifications)
                } else {
                    switch auth.state {
                    case .unavailable:
                        PreviewAppRoot(model: previewModel, notifications: notifications)
                    case .signedIn(let identity):
                        if let client = auth.client {
                            AuthenticatedAppRoot(
                                client: client,
                                identity: identity,
                                notifications: notifications,
                                onSignOut: { Task { await auth.signOut() } }
                            )
                            .id(identity.id)
                        }
                    case .signedOut, .working, .magicLinkSent, .failed:
                        ProductionSignInView(auth: auth)
                            .onOpenURL { url in Task { _ = await auth.handleCallback(url) } }
                    }
                }
            }
            .tint(CrewPickTheme.accent)
            .task {
                if !usesLocalPreview { await auth.restoreSession() }
            }
        }
    }
}

private struct PreviewAppRoot: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notifications: NotificationManager

    var body: some View {
        RootView()
            .environmentObject(model)
            .environmentObject(notifications)
            .onOpenURL { url in Task { await model.handle(url: url) } }
            .task { await notifications.registerIfAuthorized() }
            .onChange(of: notifications.deviceToken) { _, token in
                guard let token else { return }
                Task { await model.registerDeviceToken(token) }
            }
    }
}

private struct AuthenticatedAppRoot: View {
    @StateObject private var model: AppModel
    @ObservedObject var notifications: NotificationManager
    let onSignOut: () -> Void

    init(client: SupabaseClient, identity: AuthenticatedIdentity, notifications: NotificationManager, onSignOut: @escaping () -> Void) {
        let store = SupabaseRemoteStore(client: client)
        _model = StateObject(wrappedValue: AppModel(
            groupRepository: store,
            ideaRepository: store,
            notificationRegistrar: store,
            activityRepository: store,
            notificationPreferenceRepository: store,
            currentUser: User(id: identity.id, displayName: identity.displayName, email: identity.email)
        ))
        self.notifications = notifications
        self.onSignOut = onSignOut
    }

    var body: some View {
        RootView(requiresPreviewOnboarding: false, onSignOut: onSignOut)
            .environmentObject(model)
            .environmentObject(notifications)
            .onOpenURL { url in
                guard url.host?.lowercased() != "auth-callback" else { return }
                Task { await model.handle(url: url) }
            }
            .task { await notifications.registerIfAuthorized() }
            .onChange(of: notifications.deviceToken) { _, token in
                guard let token else { return }
                Task { await model.registerDeviceToken(token) }
            }
    }
}

private struct ProductionSignInView: View {
    @ObservedObject var auth: ProductionAuthService
    @State private var email = ""

    private var isWorking: Bool {
        if case .working = auth.state { return true }
        return false
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 56)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 82, height: 82)
                    .background(LinearGradient(colors: [CrewPickTheme.accent, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
                    .accessibilityHidden(true)
                Text("Welcome to CrewPick")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Sign in to keep private boards synced with the friends you invite.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                SignInWithAppleButton(.continue) { request in
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    Task { _ = await auth.completeAppleAuthorization(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .disabled(isWorking)
                .accessibilityIdentifier("production.appleSignIn")

                HStack {
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                    Text("or").font(.caption).foregroundStyle(.secondary)
                    Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                }

                TextField("Email address", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("production.email")

                Button {
                    Task { try? await auth.sendMagicLink(to: email) }
                } label: {
                    if isWorking { ProgressView().frame(maxWidth: .infinity) }
                    else { Text("Email me a sign-in link").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isWorking)
                .accessibilityIdentifier("production.magicLink")

                statusMessage

                Label("Groups are private and visible only to members.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 28)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch auth.state {
        case .magicLinkSent(let address):
            Label("Check \(address) for your sign-in link.", systemImage: "envelope.badge.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}
