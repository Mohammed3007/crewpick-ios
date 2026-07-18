import Foundation

public actor LocalStore: GroupRepository, IdeaRepository {
    private var storedGroups: [FriendGroup]
    private var storedIdeas: [Idea]

    public init(groups: [FriendGroup], ideas: [Idea]) {
        self.storedGroups = groups
        self.storedIdeas = ideas
    }

    public func groups(for userID: UUID) async throws -> [FriendGroup] {
        storedGroups.filter { group in group.members.contains { $0.user.id == userID } }
    }

    public func createGroup(name: String, emoji: String, owner: User) async throws -> FriendGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalidTitle }
        let group = FriendGroup(name: trimmed, emoji: emoji, members: [.init(user: owner, role: .admin)])
        storedGroups.append(group)
        return group
    }

    public func ideas(in groupID: UUID) async throws -> [Idea] {
        guard storedGroups.contains(where: { $0.id == groupID }) else { throw RepositoryError.groupNotFound }
        return storedIdeas.filter { $0.groupID == groupID }
    }

    public func add(_ draft: IdeaDraft, to groupID: UUID, creator: User) async throws -> Idea {
        guard storedGroups.contains(where: { $0.id == groupID }) else { throw RepositoryError.groupNotFound }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw RepositoryError.invalidTitle }
        if let sourceURL = draft.sourceURL,
           let normalized = URLNormalizer.normalize(sourceURL),
           let duplicate = storedIdeas.first(where: { $0.groupID == groupID && $0.sourceURL.flatMap(URLNormalizer.normalize) == normalized }) {
            throw RepositoryError.duplicateIdea(existingIdeaID: duplicate.id)
        }
        let idea = Idea(
            groupID: groupID, title: title, category: draft.category,
            location: draft.location.nilIfBlank, priceLevel: draft.priceLevel,
            note: draft.note.nilIfBlank, sourceURL: draft.sourceURL, creator: creator
        )
        storedIdeas.append(idea)
        return idea
    }

    public func setReaction(_ reaction: ReactionKind, ideaID: UUID, userID: UUID) async throws -> Idea {
        guard let index = storedIdeas.firstIndex(where: { $0.id == ideaID }) else { throw RepositoryError.ideaNotFound }
        storedIdeas[index] = ReactionRules.applying(reaction, by: userID, to: storedIdeas[index])
        return storedIdeas[index]
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

