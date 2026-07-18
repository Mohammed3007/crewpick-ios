import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var groups: [FriendGroup] = []
    @Published private(set) var ideasByGroup: [UUID: [Idea]] = [:]
    @Published private(set) var activity: [ActivityEvent] = []
    @Published var notificationPreferences: [UUID: NotificationFrequency] = [:]
    @Published var state: LoadState = .idle
    @Published var isOffline = false
    @Published var alertMessage: String?
    @Published var deepLinkDestination: DeepLinkDestination?
    @Published var incomingImport: PendingImport?

    let currentUser: User
    private let groupRepository: any GroupRepository
    private let ideaRepository: any IdeaRepository
    private let metadataProvider: any LinkMetadataProviding
    private let notificationRegistrar: any NotificationRegistering

    init(store: LocalStore, currentUser: User) {
        self.groupRepository = store
        self.ideaRepository = store
        self.metadataProvider = LocalLinkMetadataProvider()
        self.notificationRegistrar = store
        self.currentUser = currentUser
        self.activity = [
            ActivityEvent(groupID: SampleData.weekendCrewID, actor: SampleData.priya, kind: .ideaAdded, message: "Priya added Blue Jays vs. Red Sox", createdAt: .now.addingTimeInterval(-86_400), ideaID: SampleData.ideas[2].id),
            ActivityEvent(groupID: SampleData.weekendCrewID, actor: SampleData.maya, kind: .ideaAdded, message: "Maya added Bar Raval", createdAt: .now.addingTimeInterval(-172_800), ideaID: SampleData.ideas[0].id)
        ]
        self.notificationPreferences = [SampleData.weekendCrewID: .instant, SampleData.cottageCrewID: .dailyDigest]
    }

    func loadGroups() async {
        state = .loading
        do {
            groups = try await groupRepository.groups(for: currentUser.id)
            cacheGroupsForExtension()
            incomingImport = SharedImportStore()?.pendingImports().first
            state = .loaded
        } catch {
            state = .failed("We couldn't load your groups. Pull to try again.")
        }
    }

    func loadIdeas(groupID: UUID) async {
        do {
            ideasByGroup[groupID] = try await ideaRepository.ideas(in: groupID)
        } catch {
            state = .failed("We couldn't load this board.")
        }
    }

    func react(_ kind: ReactionKind, to ideaID: UUID, in groupID: UUID) async {
        do {
            let updated = try await ideaRepository.setReaction(kind, ideaID: ideaID, userID: currentUser.id)
            replace(updated, in: groupID)
            activity.insert(.init(groupID: groupID, actor: currentUser, kind: .reactionChanged, message: "You reacted \(kind.rawValue.lowercased()) to \(updated.title)", ideaID: updated.id), at: 0)
        } catch {
            alertMessage = "Your reaction wasn't saved. Try again."
        }
    }

    func add(_ draft: IdeaDraft, to groupID: UUID) async throws {
        let idea = try await ideaRepository.add(draft, to: groupID, creator: currentUser)
        ideasByGroup[groupID, default: []].append(idea)
        activity.insert(.init(groupID: groupID, actor: currentUser, kind: .ideaAdded, message: "You added \(idea.title)", ideaID: idea.id), at: 0)
    }

    func importPreview(for url: URL) async throws -> IdeaDraft {
        try await metadataProvider.metadata(for: url)
    }

    func createGroup(name: String, emoji: String) async throws -> FriendGroup {
        let group = try await groupRepository.createGroup(name: name, emoji: emoji, owner: currentUser)
        groups.append(group)
        cacheGroupsForExtension()
        ideasByGroup[group.id] = []
        notificationPreferences[group.id] = .instant
        return group
    }

    func joinGroup(code: String) async throws -> FriendGroup {
        let group = try await groupRepository.joinGroup(code: code, user: currentUser)
        if !groups.contains(where: { $0.id == group.id }) { groups.append(group) }
        cacheGroupsForExtension()
        notificationPreferences[group.id] = .instant
        activity.insert(.init(groupID: group.id, actor: currentUser, kind: .memberJoined, message: "You joined \(group.name)"), at: 0)
        return group
    }

    func removeMember(_ memberID: UUID, from groupID: UUID) async {
        do {
            let updated = try await groupRepository.removeMember(memberID, from: groupID, requestedBy: currentUser.id)
            replace(updated)
        } catch RepositoryError.cannotRemoveLastAdmin {
            alertMessage = "Promote another admin before removing the last administrator."
        } catch {
            alertMessage = "That member couldn't be removed."
        }
    }

    func addComment(_ body: String, to ideaID: UUID, in groupID: UUID) async {
        do {
            let updated = try await ideaRepository.addComment(body, ideaID: ideaID, author: currentUser)
            replace(updated, in: groupID)
            activity.insert(.init(groupID: groupID, actor: currentUser, kind: .commentAdded, message: "You commented on \(updated.title)", ideaID: updated.id), at: 0)
        } catch {
            alertMessage = "Your comment couldn't be posted."
        }
    }

    func markPlanned(_ idea: Idea, in groupID: UUID) async {
        do {
            let updated = try await ideaRepository.setStatus(.planned, ideaID: idea.id)
            await loadIdeas(groupID: groupID)
            activity.insert(.init(groupID: groupID, actor: currentUser, kind: .planCreated, message: "You planned \(updated.title)", ideaID: updated.id), at: 0)
        } catch { alertMessage = "The plan couldn't be saved." }
    }

    func markCompleted(_ idea: Idea, in groupID: UUID) async {
        do {
            let updated = try await ideaRepository.setStatus(.completed, ideaID: idea.id)
            replace(updated, in: groupID)
            activity.insert(.init(groupID: groupID, actor: currentUser, kind: .planCompleted, message: "You completed \(updated.title)", ideaID: updated.id), at: 0)
        } catch { alertMessage = "The plan couldn't be completed." }
    }

    func group(id: UUID) -> FriendGroup? { groups.first { $0.id == id } }

    func setNotificationPreference(_ value: NotificationFrequency, for groupID: UUID) {
        let previous = notificationPreferences[groupID]
        notificationPreferences[groupID] = value
        Task {
            do { try await notificationRegistrar.setPreference(value, groupID: groupID) }
            catch {
                notificationPreferences[groupID] = previous
                alertMessage = "That notification preference couldn't be saved."
            }
        }
    }

    func registerDeviceToken(_ token: Data) async {
        do { try await notificationRegistrar.register(deviceToken: token) }
        catch { alertMessage = "Push notifications couldn't be connected to your account." }
    }

    func handle(url: URL) async {
        guard let destination = DeepLinkDestination(url: url) else {
            alertMessage = "That CrewPick link isn't valid."
            return
        }
        if case .invitation(let code) = destination {
            do { _ = try await joinGroup(code: code) }
            catch { alertMessage = "That invitation is invalid or expired." }
        } else {
            deepLinkDestination = destination
        }
    }

    func completeIncomingImport(_ id: UUID) {
        try? SharedImportStore()?.remove(id: id)
        incomingImport = SharedImportStore()?.pendingImports().first
    }

    private func cacheGroupsForExtension() {
        let summaries = groups.map { SharedGroupSummary(id: $0.id, name: $0.name, emoji: $0.emoji) }
        try? SharedImportStore()?.saveGroups(summaries)
    }

    private func replace(_ idea: Idea, in groupID: UUID) {
        guard let index = ideasByGroup[groupID]?.firstIndex(where: { $0.id == idea.id }) else { return }
        ideasByGroup[groupID]?[index] = idea
    }

    private func replace(_ group: FriendGroup) {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else { return }
        groups[index] = group
    }
}
