import SwiftUI

struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainTabView { hasCompletedOnboarding = false }
            } else {
                OnboardingView { hasCompletedOnboarding = true }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: hasCompletedOnboarding)
        .alert("CrewPick", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }
}

private struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var page = 0
    @State private var email = "alex.chen@hey.com"

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: page == 0 ? "sparkles" : "person.3.fill")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 82, height: 82)
                .background(LinearGradient(colors: [CrewPickTheme.accent, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
                .accessibilityHidden(true)
            Text(page == 0 ? "CrewPick" : "Your groups are waiting")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(page == 0 ? "Save everything your friends want to try, then quickly decide what to do together." : "Sign in to keep private boards shared only with the friends you invite.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if page == 0 {
                HStack {
                    Label("Private groups", systemImage: "lock.fill")
                    Label("No public feed", systemImage: "eye.slash.fill")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    Button("Continue with Apple", systemImage: "apple.logo", action: onComplete)
                        .buttonStyle(.borderedProminent).tint(.primary).controlSize(.large)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    Button("Email me a sign-in link", action: onComplete)
                        .buttonStyle(.bordered).controlSize(.large)
                    Text("Local preview: either option signs in as Alex Chen.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 24)
            }
            Spacer()
            if page == 0 {
                Button("Get started") { page = 1 }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .frame(maxWidth: .infinity).padding(.horizontal, 24)
            }
        }
        .padding(.vertical, 32)
    }
}

private struct MainTabView: View {
    @EnvironmentObject private var model: AppModel
    let onSignOut: () -> Void
    @State private var selectedTab = 0
    @State private var groupPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $groupPath) { GroupListView() }
                .tabItem { Label("Groups", systemImage: "person.3.fill") }
                .tag(0)

            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "bell.fill") }
                .tag(1)

            NavigationStack { ProfileView(onSignOut: onSignOut) }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(2)
        }
        .task { if model.state == .idle { await model.loadGroups() } }
        .onChange(of: model.deepLinkDestination) { _, destination in
            guard let destination else { return }
            Task { await route(destination) }
        }
        .sheet(item: $model.incomingImport) { pending in
            if let group = pending.destinationGroupID.flatMap({ model.group(id: $0) }) ?? model.groups.first {
                AddIdeaView(group: group, initialURL: pending.sourceURL) {
                    model.completeIncomingImport(pending.id)
                } onOpenDuplicate: { ideaID in
                    model.completeIncomingImport(pending.id)
                    model.deepLinkDestination = .idea(groupID: group.id, ideaID: ideaID)
                }
            } else {
                ContentUnavailableView("Join a group first", systemImage: "person.3", description: Text("Your shared link is safely queued until a destination group is available."))
            }
        }
    }

    private func route(_ destination: DeepLinkDestination) async {
        selectedTab = 0
        groupPath = NavigationPath()
        let groupID: UUID
        switch destination {
        case .group(let id): groupID = id
        case .idea(let id, _): groupID = id
        case .plan(let id, _): groupID = id
        case .invitation: return
        }
        guard let group = model.group(id: groupID) else {
            model.alertMessage = "You don't have access to that private group."
            model.deepLinkDestination = nil
            return
        }
        groupPath.append(group)
        await model.loadIdeas(groupID: groupID)
        if case .idea(_, let ideaID) = destination,
           let idea = model.ideasByGroup[groupID]?.first(where: { $0.id == ideaID }) {
            groupPath.append(idea)
        }
        model.deepLinkDestination = nil
    }
}

private struct GroupListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewGroup = false

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView("Loading groups…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load groups", systemImage: "exclamationmark.triangle")
                } description: { Text(message) } actions: {
                    Button("Try again") { Task { await model.loadGroups() } }
                }
            case .loaded:
                if model.groups.isEmpty {
                    EmptyState(title: "No groups yet", message: "Create a private group or join with an invite.", actionTitle: "Create or join", action: { showingNewGroup = true })
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if model.isOffline { OfflineBanner(message: "You're offline — showing saved groups.") }
                            ForEach(model.groups) { group in
                                NavigationLink(value: group) { GroupCard(group: group, ideaCount: model.ideasByGroup[group.id]?.count) }
                                    .buttonStyle(.plain)
                            }
                            Text("Groups are private. Only invited friends can see ideas.")
                                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center).padding(.top, 8)
                        }
                        .padding(CrewPickTheme.screenPadding)
                    }
                    .refreshable { await model.loadGroups() }
                }
            }
        }
        .navigationTitle("Groups")
        .toolbar { Button("New group", systemImage: "plus") { showingNewGroup = true } }
        .navigationDestination(for: FriendGroup.self) { GroupBoardView(group: $0) }
        .sheet(isPresented: $showingNewGroup) { CreateJoinGroupView() }
    }
}

private struct CreateJoinGroupView: View {
    enum Mode: String, CaseIterable, Identifiable { case create = "Create", join = "Join"; var id: Self { self } }
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .create
    @State private var name = ""
    @State private var emoji = "🎉"
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    private let emojis = ["🎉", "🌲", "🍜", "🎳", "⭐️"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Action", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                if mode == .create {
                    Section("Group details") {
                        TextField("Group name", text: $name)
                        Picker("Emoji", selection: $emoji) { ForEach(emojis, id: \.self) { Text($0).tag($0) } }
                            .pickerStyle(.segmented)
                    }
                    Section { Text("You will be the group admin and can invite or remove members.").foregroundStyle(.secondary) }
                } else {
                    Section("Invite code") {
                        TextField("e.g. TRIV-88", text: $code).textInputAutocapitalization(.characters).autocorrectionDisabled()
                        Text("For this local preview, try TRIV-88.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(mode == .create ? "New group" : "Join group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.rawValue) { Task { await submit() } }
                        .disabled(isWorking || (mode == .create ? name.trimmingCharacters(in: .whitespaces).isEmpty : !InviteCode.isValid(code)))
                }
            }
        }
    }

    private func submit() async {
        isWorking = true; defer { isWorking = false }
        do {
            if mode == .create { _ = try await model.createGroup(name: name, emoji: emoji) }
            else { _ = try await model.joinGroup(code: code) }
            dismiss()
        } catch RepositoryError.invalidInvite { errorMessage = "That invitation is invalid or expired." }
        catch { errorMessage = "We couldn't complete that request." }
    }
}

private struct ActivityView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.activity.isEmpty {
                ContentUnavailableView("No new activity", systemImage: "bell", description: Text("Ideas, reactions, comments, and plan updates will appear here."))
            } else {
                List(model.activity) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon(event.kind)).foregroundStyle(CrewPickTheme.accent).frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.message)
                            Text(event.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Activity")
    }

    private func icon(_ kind: ActivityKind) -> String {
        switch kind {
        case .ideaAdded: "plus.circle.fill"
        case .reactionChanged: "hand.thumbsup.fill"
        case .commentAdded: "bubble.left.fill"
        case .planCreated: "calendar.badge.checkmark"
        case .planCompleted: "checkmark.circle.fill"
        case .memberJoined: "person.badge.plus"
        }
    }
}

private struct ProfileView: View {
    @EnvironmentObject private var model: AppModel
    let onSignOut: () -> Void

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("Signed in as", value: model.currentUser.displayName)
                if let email = model.currentUser.email { LabeledContent("Email", value: email) }
            }
            Section {
                ForEach(model.groups) { group in
                    Picker("\(group.emoji) \(group.name)", selection: Binding(
                        get: { model.notificationPreferences[group.id] ?? .instant },
                        set: { model.setNotificationPreference($0, for: group.id) }
                    )) {
                        ForEach(NotificationFrequency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            } header: {
                Text("Group notifications")
            } footer: {
                Text("New ideas notify everyone except the contributor. Reaction notifications are off in v1.")
            }
            Section("Developer preview") { Toggle("Simulate offline", isOn: $model.isOffline) }
            Section { Button("Sign out", role: .destructive, action: onSignOut) }
        }
        .navigationTitle("Profile")
    }
}

private struct GroupCard: View {
    let group: FriendGroup
    let ideaCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            Text(group.emoji).font(.title).frame(width: 52, height: 52)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name).font(.headline)
                Text("\(group.members.count) members · \(ideaCount.map { String($0) } ?? "—") ideas").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(); MemberAvatarStack(members: group.members)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16).warmCard().accessibilityElement(children: .combine)
    }
}

struct OfflineBanner: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "wifi.slash")
            .font(.subheadline.weight(.semibold)).foregroundStyle(CrewPickTheme.warning)
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(CrewPickTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }
}
