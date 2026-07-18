import SwiftUI

struct GroupBoardView: View {
    @EnvironmentObject private var model: AppModel
    let group: FriendGroup
    @State private var category: IdeaCategory?
    @State private var unvoted = false
    @State private var sort: BoardSort = .topRanked
    @State private var showingAdd = false
    @State private var showingDecide = false
    @State private var showingMembers = false
    @State private var duplicateIdeaID: UUID?

    private var currentGroup: FriendGroup { model.group(id: group.id) ?? group }

    private var ideas: [Idea] {
        BoardEngine.ranked(
            model.ideasByGroup[group.id] ?? [],
            filter: .init(category: category, unvotedByUserID: unvoted ? model.currentUser.id : nil),
            sort: sort
        )
    }

    private var plannedIdea: Idea? {
        model.ideasByGroup[group.id]?.first(where: { $0.status == .planned })
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.isOffline { OfflineBanner(message: "You're offline — changes sync when you're back.") }
                if let plannedIdea { ActivePlanCard(idea: plannedIdea) { Task { await model.markCompleted(plannedIdea, in: group.id) } } }
                filters
                if ideas.isEmpty {
                    EmptyState(
                        title: category == nil && !unvoted ? "Nothing saved yet" : "No matching ideas",
                        message: category == nil && !unvoted ? "Share a restaurant, event, or activity your group should try." : "Try another filter.",
                        actionTitle: category == nil && !unvoted ? "Add the first idea" : nil,
                        action: category == nil && !unvoted ? { showingAdd = true } : nil
                    )
                    .frame(minHeight: 360)
                } else {
                    ForEach(ideas) { idea in
                        IdeaCard(idea: idea, userID: model.currentUser.id) { kind in
                            Task { await model.react(kind, to: idea.id, in: group.id) }
                        }
                    }
                }
            }
            .padding(CrewPickTheme.screenPadding)
            .padding(.bottom, 72)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Add idea", systemImage: "plus") { showingAdd = true }
                    .buttonStyle(.borderedProminent)
                Button("Decide for us", systemImage: "sparkles") { showingDecide = true }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("\(currentGroup.emoji) \(currentGroup.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Members", systemImage: "person.3") { showingMembers = true } }
        .navigationDestination(for: Idea.self) { IdeaDetailView(ideaID: $0.id, group: group) }
        .navigationDestination(isPresented: Binding(get: { duplicateIdeaID != nil }, set: { if !$0 { duplicateIdeaID = nil } })) {
            if let duplicateIdeaID { IdeaDetailView(ideaID: duplicateIdeaID, group: group) }
        }
        .task { await model.loadIdeas(groupID: group.id) }
        .sheet(isPresented: $showingAdd) {
            AddIdeaView(group: group) { } onOpenDuplicate: { duplicateIdeaID = $0 }
        }
        .sheet(isPresented: $showingDecide) { DecideView(group: group) }
        .sheet(isPresented: $showingMembers) { GroupMembersView(groupID: group.id) }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", selected: category == nil && !unvoted) { category = nil; unvoted = false }
                ForEach([IdeaCategory.food, .activity, .event]) { value in
                    FilterChip(title: value.rawValue, selected: category == value) { category = value; unvoted = false }
                }
                FilterChip(title: "Unvoted by me", selected: unvoted) { unvoted.toggle(); category = nil }
                Button(sort == .topRanked ? "Top ranked" : "Newest", systemImage: "arrow.up.arrow.down") {
                    sort = sort == .topRanked ? .newest : .topRanked
                }
                .buttonStyle(.bordered)
                .clipShape(Capsule())
            }
        }
    }
}

private struct IdeaCard: View {
    let idea: Idea
    let userID: UUID
    let onReaction: (ReactionKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NavigationLink(value: idea) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(height: 130)
                        Text(idea.category.rawValue)
                            .font(.caption.bold())
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .padding(12)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(idea.title).font(.headline)
                        Text(metadata).font(.subheadline).foregroundStyle(.secondary)
                        Text("Added by \(idea.creator.displayName)").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens idea details")
            .accessibilityIdentifier("idea-card-\(idea.id.uuidString)")
            ReactionControl(idea: idea, userID: userID, onSelect: onReaction)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .warmCard()
        .contentShape(Rectangle())
    }

    private var metadata: String {
        [idea.location, idea.distanceKilometres.map { String(format: "%.1f km", $0) }, idea.priceLevel.map { String(repeating: "$", count: $0) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var gradient: [Color] {
        switch idea.category {
        case .food: [.orange.opacity(0.85), .red.opacity(0.55)]
        case .activity: [.green.opacity(0.75), .mint.opacity(0.55)]
        case .event: [.blue.opacity(0.75), .purple.opacity(0.55)]
        case .trip: [.cyan.opacity(0.75), .blue.opacity(0.55)]
        case .other: [.gray.opacity(0.65), .brown.opacity(0.55)]
        }
    }
}

private struct ActivePlanCard: View {
    let idea: Idea
    let onComplete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVE PLAN").font(.caption2.bold()).tracking(1.2).opacity(0.85)
            Text(idea.title).font(.title3.bold())
            Text(idea.location ?? "Location to be decided").font(.subheadline)
            Button("Mark Completed", systemImage: "checkmark.circle", action: onComplete)
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(LinearGradient(colors: [CrewPickTheme.accent, .orange], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: CrewPickTheme.cardRadius))
    }
}
