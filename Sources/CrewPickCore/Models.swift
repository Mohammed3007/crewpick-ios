import Foundation

public struct User: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var displayName: String
    public var email: String?

    public init(id: UUID = UUID(), displayName: String, email: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.email = email
    }
}

public enum GroupRole: String, Codable, Sendable { case admin, member }

public struct GroupMember: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID { user.id }
    public let user: User
    public var role: GroupRole

    public init(user: User, role: GroupRole) {
        self.user = user
        self.role = role
    }
}

public struct FriendGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var emoji: String
    public var members: [GroupMember]
    public var activePlanID: UUID?

    public init(id: UUID = UUID(), name: String, emoji: String, members: [GroupMember], activePlanID: UUID? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.members = members
        self.activePlanID = activePlanID
    }
}

public enum IdeaCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case food = "Food"
    case activity = "Activity"
    case event = "Event"
    case trip = "Trip"
    case other = "Other"
    public var id: Self { self }
}

public enum ReactionKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case inForIt = "I'm in"
    case maybe = "Maybe"
    case pass = "Pass"
    public var id: Self { self }
}

public struct Reaction: Codable, Hashable, Identifiable, Sendable {
    public let userID: UUID
    public var kind: ReactionKind
    public var id: UUID { userID }

    public init(userID: UUID, kind: ReactionKind) {
        self.userID = userID
        self.kind = kind
    }
}

public struct Comment: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let author: User
    public var body: String
    public let createdAt: Date

    public init(id: UUID = UUID(), author: User, body: String, createdAt: Date = .now) {
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
    }
}

public enum IdeaStatus: String, Codable, Sendable { case board, planned, completed }

public struct Idea: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let groupID: UUID
    public var title: String
    public var category: IdeaCategory
    public var location: String?
    public var distanceKilometres: Double?
    public var priceLevel: Int?
    public var note: String?
    public var sourceURL: URL?
    public var imageURL: URL?
    public let creator: User
    public let createdAt: Date
    public var status: IdeaStatus
    public var reactions: [Reaction]
    public var comments: [Comment]

    public init(
        id: UUID = UUID(), groupID: UUID, title: String, category: IdeaCategory,
        location: String? = nil, distanceKilometres: Double? = nil, priceLevel: Int? = nil,
        note: String? = nil, sourceURL: URL? = nil, imageURL: URL? = nil,
        creator: User, createdAt: Date = .now, status: IdeaStatus = .board,
        reactions: [Reaction] = [], comments: [Comment] = []
    ) {
        self.id = id
        self.groupID = groupID
        self.title = title
        self.category = category
        self.location = location
        self.distanceKilometres = distanceKilometres
        self.priceLevel = priceLevel
        self.note = note
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.creator = creator
        self.createdAt = createdAt
        self.status = status
        self.reactions = reactions
        self.comments = comments
    }

    public func reaction(from userID: UUID) -> ReactionKind? {
        reactions.first(where: { $0.userID == userID })?.kind
    }

    public func count(_ kind: ReactionKind) -> Int {
        reactions.lazy.filter { $0.kind == kind }.count
    }
}

public struct Plan: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let groupID: UUID
    public let ideaID: UUID
    public let createdBy: UUID
    public let createdAt: Date
    public var completedAt: Date?

    public init(id: UUID = UUID(), groupID: UUID, ideaID: UUID, createdBy: UUID, createdAt: Date = .now, completedAt: Date? = nil) {
        self.id = id
        self.groupID = groupID
        self.ideaID = ideaID
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public enum NotificationFrequency: String, CaseIterable, Codable, Sendable {
    case instant = "Instant"
    case dailyDigest = "Daily digest"
    case off = "Off"
}

public struct IdeaDraft: Hashable, Sendable {
    public var title: String
    public var category: IdeaCategory
    public var location: String
    public var priceLevel: Int?
    public var note: String
    public var sourceURL: URL?

    public init(title: String = "", category: IdeaCategory = .food, location: String = "", priceLevel: Int? = 2, note: String = "", sourceURL: URL? = nil) {
        self.title = title
        self.category = category
        self.location = location
        self.priceLevel = priceLevel
        self.note = note
        self.sourceURL = sourceURL
    }
}

