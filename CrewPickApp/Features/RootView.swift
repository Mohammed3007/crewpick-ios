import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            NavigationStack { GroupListView() }
                .tabItem { Label("Groups", systemImage: "person.3.fill") }

            NavigationStack {
                ContentUnavailableView("No new activity", systemImage: "bell", description: Text("Ideas, reactions, and plan updates will appear here."))
                    .navigationTitle("Activity")
            }
            .tabItem { Label("Activity", systemImage: "bell.fill") }

            NavigationStack {
                List {
                    Section("Account") { LabeledContent("Signed in as", value: model.currentUser.displayName) }
                    Section("Notifications") { Text("Choose Instant, Daily digest, or Off in each group's settings.") }
                }
                .navigationTitle("Profile")
            }
            .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .task { if model.state == .idle { await model.loadGroups() } }
    }
}

private struct GroupListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView("Loading groups…")
            case .failed(let message):
                ContentUnavailableView("Couldn't load groups", systemImage: "exclamationmark.triangle", description: Text(message))
            case .loaded:
                if model.groups.isEmpty {
                    EmptyState(title: "No groups yet", message: "Create a private group or join with an invite.", actionTitle: "Create group", action: {})
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if model.isOffline {
                                Label("You're offline — showing saved groups.", systemImage: "wifi.slash")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(CrewPickTheme.warning)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(CrewPickTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            }
                            ForEach(model.groups) { group in
                                NavigationLink(value: group) {
                                    GroupCard(group: group, ideaCount: model.ideasByGroup[group.id]?.count)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(CrewPickTheme.screenPadding)
                    }
                    .refreshable { await model.loadGroups() }
                }
            }
        }
        .navigationTitle("Groups")
        .toolbar { Button("New group", systemImage: "plus") {} }
        .navigationDestination(for: FriendGroup.self) { GroupBoardView(group: $0) }
    }
}

private struct GroupCard: View {
    let group: FriendGroup
    let ideaCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            Text(group.emoji)
                .font(.title)
                .frame(width: 52, height: 52)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 3) {
                Text(group.name).font(.headline)
                Text("\(group.members.count) members · \(ideaCount.map { String($0) } ?? "—") ideas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            MemberAvatarStack(members: group.members)
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .warmCard()
        .accessibilityElement(children: .combine)
    }
}
