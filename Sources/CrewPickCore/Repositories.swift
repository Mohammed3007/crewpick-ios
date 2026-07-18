import Foundation

public enum RepositoryError: Error, Equatable, Sendable {
    case groupNotFound
    case ideaNotFound
    case duplicateIdea(existingIdeaID: UUID)
    case invalidTitle
    case permissionDenied
    case invalidInvite
    case cannotRemoveLastAdmin
}

public protocol GroupRepository: Sendable {
    func groups(for userID: UUID) async throws -> [FriendGroup]
    func createGroup(name: String, emoji: String, owner: User) async throws -> FriendGroup
    func joinGroup(code: String, user: User) async throws -> FriendGroup
    func removeMember(_ userID: UUID, from groupID: UUID, requestedBy: UUID) async throws -> FriendGroup
}

public protocol IdeaRepository: Sendable {
    func ideas(in groupID: UUID) async throws -> [Idea]
    func add(_ draft: IdeaDraft, to groupID: UUID, creator: User) async throws -> Idea
    func update(_ draft: IdeaDraft, ideaID: UUID, requestedBy userID: UUID) async throws -> Idea
    func delete(ideaID: UUID, requestedBy userID: UUID) async throws
    func setReaction(_ reaction: ReactionKind, ideaID: UUID, userID: UUID) async throws -> Idea
    func addComment(_ body: String, ideaID: UUID, author: User) async throws -> Idea
    func setStatus(_ status: IdeaStatus, ideaID: UUID) async throws -> Idea
}

public protocol LinkMetadataProviding: Sendable {
    func metadata(for url: URL) async throws -> IdeaDraft
}

public protocol AuthenticationProviding: Sendable {
    func currentUser() async -> User?
    func signInWithApple() async throws -> User
    func sendMagicLink(to email: String) async throws
}

public protocol PlanRepository: Sendable {
    func createPlan(groupID: UUID, ideaID: UUID, userID: UUID) async throws -> Plan
    func completePlan(_ planID: UUID) async throws -> Plan
}

public protocol NotificationRegistering: Sendable {
    func register(deviceToken: Data) async throws
    func setPreference(_ frequency: NotificationFrequency, groupID: UUID) async throws
}
