import Foundation

public actor LocalStore: GroupRepository, IdeaRepository, NotificationRegistering {
    private var storedGroups: [FriendGroup]
    private var storedIdeas: [Idea]
    private var deviceToken: Data?
    private var notificationPreferences: [UUID: NotificationFrequency] = [:]

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

    public func joinGroup(code: String, user: User) async throws -> FriendGroup {
        guard InviteCode.isValid(code) else { throw RepositoryError.invalidInvite }
        if InviteCode.normalize(code) == "TRIV88" {
            if let existing = storedGroups.first(where: { $0.name == "Trivia Squad" }) { return existing }
            let group = FriendGroup(name: "Trivia Squad", emoji: "🧠", members: [
                .init(user: user, role: .member), .init(user: SampleData.maya, role: .admin)
            ])
            storedGroups.append(group)
            return group
        }
        throw RepositoryError.invalidInvite
    }

    public func removeMember(_ userID: UUID, from groupID: UUID, requestedBy: UUID) async throws -> FriendGroup {
        guard let groupIndex = storedGroups.firstIndex(where: { $0.id == groupID }) else { throw RepositoryError.groupNotFound }
        guard storedGroups[groupIndex].members.contains(where: { $0.user.id == requestedBy && $0.role == .admin }) else {
            throw RepositoryError.permissionDenied
        }
        guard let member = storedGroups[groupIndex].members.first(where: { $0.user.id == userID }) else { throw RepositoryError.permissionDenied }
        if member.role == .admin && storedGroups[groupIndex].members.filter({ $0.role == .admin }).count == 1 {
            throw RepositoryError.cannotRemoveLastAdmin
        }
        storedGroups[groupIndex].members.removeAll { $0.user.id == userID }
        return storedGroups[groupIndex]
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

    public func update(_ draft: IdeaDraft, ideaID: UUID, requestedBy userID: UUID) async throws -> Idea {
        guard let index = storedIdeas.firstIndex(where: { $0.id == ideaID }) else { throw RepositoryError.ideaNotFound }
        let groupID = storedIdeas[index].groupID
        guard canManage(storedIdeas[index], requestedBy: userID, in: groupID) else { throw RepositoryError.permissionDenied }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw RepositoryError.invalidTitle }
        if let sourceURL = draft.sourceURL,
           let normalized = URLNormalizer.normalize(sourceURL),
           let duplicate = storedIdeas.first(where: { $0.id != ideaID && $0.groupID == groupID && $0.sourceURL.flatMap(URLNormalizer.normalize) == normalized }) {
            throw RepositoryError.duplicateIdea(existingIdeaID: duplicate.id)
        }
        storedIdeas[index].title = title
        storedIdeas[index].category = draft.category
        storedIdeas[index].location = draft.location.nilIfBlank
        storedIdeas[index].priceLevel = draft.priceLevel
        storedIdeas[index].note = draft.note.nilIfBlank
        storedIdeas[index].sourceURL = draft.sourceURL
        return storedIdeas[index]
    }

    public func delete(ideaID: UUID, requestedBy userID: UUID) async throws {
        guard let idea = storedIdeas.first(where: { $0.id == ideaID }) else { throw RepositoryError.ideaNotFound }
        guard canManage(idea, requestedBy: userID, in: idea.groupID) else { throw RepositoryError.permissionDenied }
        storedIdeas.removeAll { $0.id == ideaID }
    }

    public func setReaction(_ reaction: ReactionKind, ideaID: UUID, userID: UUID) async throws -> Idea {
        guard let index = storedIdeas.firstIndex(where: { $0.id == ideaID }) else { throw RepositoryError.ideaNotFound }
        storedIdeas[index] = ReactionRules.applying(reaction, by: userID, to: storedIdeas[index])
        return storedIdeas[index]
    }

    public func addComment(_ body: String, ideaID: UUID, author: User) async throws -> Idea {
        guard let index = storedIdeas.firstIndex(where: { $0.id == ideaID }) else { throw RepositoryError.ideaNotFound }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalidTitle }
        storedIdeas[index].comments.append(Comment(author: author, body: trimmed))
        return storedIdeas[index]
    }

    public func setStatus(_ status: IdeaStatus, ideaID: UUID) async throws -> Idea {
        guard let index = storedIdeas.firstIndex(where: { $0.id == ideaID }) else { throw RepositoryError.ideaNotFound }
        if status == .planned {
            let groupID = storedIdeas[index].groupID
            for candidate in storedIdeas.indices where storedIdeas[candidate].groupID == groupID && storedIdeas[candidate].status == .planned {
                storedIdeas[candidate].status = .board
            }
        }
        storedIdeas[index].status = status
        return storedIdeas[index]
    }

    public func register(deviceToken: Data) async throws {
        self.deviceToken = deviceToken
    }

    public func setPreference(_ frequency: NotificationFrequency, groupID: UUID) async throws {
        guard storedGroups.contains(where: { $0.id == groupID }) else { throw RepositoryError.groupNotFound }
        notificationPreferences[groupID] = frequency
    }

    private func canManage(_ idea: Idea, requestedBy userID: UUID, in groupID: UUID) -> Bool {
        idea.creator.id == userID || storedGroups.first(where: { $0.id == groupID })?.members.contains(where: {
            $0.user.id == userID && $0.role == .admin
        }) == true
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
