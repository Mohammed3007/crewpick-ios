import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var groups: [FriendGroup] = []
    @Published private(set) var ideasByGroup: [UUID: [Idea]] = [:]
    @Published var state: LoadState = .idle
    @Published var isOffline = false

    let currentUser: User
    private let groupRepository: any GroupRepository
    private let ideaRepository: any IdeaRepository

    init(store: LocalStore, currentUser: User) {
        self.groupRepository = store
        self.ideaRepository = store
        self.currentUser = currentUser
    }

    func loadGroups() async {
        state = .loading
        do {
            groups = try await groupRepository.groups(for: currentUser.id)
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
        } catch {
            state = .failed("Your reaction wasn't saved. Try again.")
        }
    }

    func add(_ draft: IdeaDraft, to groupID: UUID) async throws {
        let idea = try await ideaRepository.add(draft, to: groupID, creator: currentUser)
        ideasByGroup[groupID, default: []].append(idea)
    }

    func markPlanned(_ idea: Idea, in groupID: UUID) {
        var updated = idea
        updated.status = .planned
        replace(updated, in: groupID)
    }

    func markCompleted(_ idea: Idea, in groupID: UUID) {
        var updated = idea
        updated.status = .completed
        replace(updated, in: groupID)
    }

    private func replace(_ idea: Idea, in groupID: UUID) {
        guard let index = ideasByGroup[groupID]?.firstIndex(where: { $0.id == idea.id }) else { return }
        ideasByGroup[groupID]?[index] = idea
    }
}

