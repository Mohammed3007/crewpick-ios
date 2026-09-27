import Foundation
import Supabase

actor SupabaseRemoteStore: GroupRepository, IdeaRepository, NotificationRegistering, ActivityRepository, NotificationPreferenceRepository {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func groups(for userID: UUID) async throws -> [FriendGroup] {
        let rows: [RemoteGroup] = try await client
            .from("groups")
            .select(Self.groupSelection)
            .order("created_at", ascending: true)
            .execute()
            .value
        return rows.map { $0.domain(currentUserID: userID) }
    }

    func createGroup(name: String, emoji: String, owner: User) async throws -> FriendGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalidTitle }
        let created: RemoteID = try await client
            .rpc("create_group", params: CreateGroupArguments(groupName: trimmed, groupEmoji: emoji))
            .select("id")
            .single()
            .execute()
            .value
        return try await fetchGroup(id: created.id, currentUserID: owner.id)
    }

    func joinGroup(code: String, user: User) async throws -> FriendGroup {
        let normalized = InviteCode.normalize(code)
        guard InviteCode.isValid(normalized) else { throw RepositoryError.invalidInvite }
        do {
            let groupID: UUID = try await client
                .rpc("accept_group_invite", params: AcceptInviteArguments(inviteCode: normalized))
                .execute()
                .value
            return try await fetchGroup(id: groupID, currentUserID: user.id)
        } catch {
            throw RepositoryError.invalidInvite
        }
    }

    func removeMember(_ userID: UUID, from groupID: UUID, requestedBy: UUID) async throws -> FriendGroup {
        do {
            try await client.from("group_members")
                .delete()
                .eq("group_id", value: groupID)
                .eq("user_id", value: userID)
                .execute()
            return try await fetchGroup(id: groupID, currentUserID: requestedBy)
        } catch {
            throw RepositoryError.permissionDenied
        }
    }

    func createInvitation(for groupID: UUID, requestedBy: UUID) async throws -> GroupInvitation {
        do {
            let rows: [RemoteInvitation] = try await client
                .rpc("create_group_invite", params: CreateInviteArguments(targetGroup: groupID))
                .execute()
                .value
            guard let invitation = rows.first else { throw RepositoryError.invalidInvite }
            return GroupInvitation(code: invitation.code, expiresAt: invitation.expiresAt)
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.permissionDenied
        }
    }

    func ideas(in groupID: UUID) async throws -> [Idea] {
        let rows: [RemoteIdea] = try await client
            .from("ideas")
            .select(Self.ideaSelection)
            .eq("group_id", value: groupID)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map(\.domain)
    }

    func add(_ draft: IdeaDraft, to groupID: UUID, creator: User) async throws -> Idea {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw RepositoryError.invalidTitle }
        let payload = InsertIdea(
            groupID: groupID,
            title: title,
            category: draft.category.remoteValue,
            location: draft.location.nilIfBlank,
            priceLevel: draft.priceLevel,
            note: draft.note.nilIfBlank,
            sourceURL: draft.sourceURL?.absoluteString,
            normalizedURL: draft.sourceURL.flatMap(URLNormalizer.normalize),
            createdBy: creator.id
        )
        do {
            let created: RemoteID = try await client.from("ideas")
                .insert(payload, returning: .representation)
                .select("id")
                .single()
                .execute()
                .value
            return try await fetchIdea(id: created.id)
        } catch let error as PostgrestError where error.code == "23505" {
            if let duplicate = try? await duplicateIdea(groupID: groupID, normalizedURL: payload.normalizedURL) {
                throw RepositoryError.duplicateIdea(existingIdeaID: duplicate)
            }
            throw error
        }
    }

    func update(_ draft: IdeaDraft, ideaID: UUID, requestedBy userID: UUID) async throws -> Idea {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw RepositoryError.invalidTitle }
        let payload = UpdateIdea(
            title: title,
            category: draft.category.remoteValue,
            location: draft.location.nilIfBlank,
            priceLevel: draft.priceLevel,
            note: draft.note.nilIfBlank,
            sourceURL: draft.sourceURL?.absoluteString,
            normalizedURL: draft.sourceURL.flatMap(URLNormalizer.normalize)
        )
        do {
            try await client.from("ideas").update(payload).eq("id", value: ideaID).execute()
            return try await fetchIdea(id: ideaID)
        } catch let error as PostgrestError where error.code == "23505" {
            let current = try await fetchIdea(id: ideaID)
            if let duplicate = try? await duplicateIdea(groupID: current.groupID, normalizedURL: payload.normalizedURL, excluding: ideaID) {
                throw RepositoryError.duplicateIdea(existingIdeaID: duplicate)
            }
            throw error
        } catch {
            throw RepositoryError.permissionDenied
        }
    }

    func delete(ideaID: UUID, requestedBy userID: UUID) async throws {
        do {
            try await client.from("ideas").delete().eq("id", value: ideaID).execute()
        } catch {
            throw RepositoryError.permissionDenied
        }
    }

    func setReaction(_ reaction: ReactionKind, ideaID: UUID, userID: UUID) async throws -> Idea {
        try await client.rpc("set_reaction", params: ReactionArguments(
            targetIdea: ideaID,
            newKind: reaction.remoteValue
        )).execute()
        return try await fetchIdea(id: ideaID)
    }

    func addComment(_ body: String, ideaID: UUID, author: User) async throws -> Idea {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RepositoryError.invalidTitle }
        try await client.from("comments").insert(InsertComment(ideaID: ideaID, authorID: author.id, body: trimmed)).execute()
        return try await fetchIdea(id: ideaID)
    }

    func setStatus(_ status: IdeaStatus, ideaID: UUID) async throws -> Idea {
        try await client.rpc("set_idea_status", params: StatusArguments(
            targetIdea: ideaID,
            newStatus: status.rawValue
        )).execute()
        return try await fetchIdea(id: ideaID)
    }

    func register(deviceToken: Data) async throws {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try await client.rpc("register_device_token", params: RegisterTokenArguments(
            rawToken: token,
            apnsEnvironment: environment
        )).execute()
    }

    func setPreference(_ frequency: NotificationFrequency, groupID: UUID) async throws {
        try await client.rpc("set_notification_preference", params: PreferenceArguments(
            targetGroup: groupID,
            newFrequency: frequency.remoteValue
        )).execute()
    }

    func activity(for userID: UUID) async throws -> [ActivityEvent] {
        let rows: [RemoteActivity] = try await client
            .from("activity_events")
            .select("id,group_id,kind,idea_id,metadata,created_at,actor:profiles!activity_events_actor_id_fkey(id,display_name)")
            .order("created_at", ascending: false)
            .limit(100)
            .execute()
            .value
        return rows.compactMap(\.domain)
    }

    func notificationPreferences(for userID: UUID) async throws -> [UUID: NotificationFrequency] {
        let rows: [RemotePreference] = try await client
            .from("notification_preferences")
            .select("group_id,frequency")
            .eq("user_id", value: userID)
            .execute()
            .value
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard let value = NotificationFrequency(remoteValue: row.frequency) else { return nil }
            return (row.groupID, value)
        })
    }

    private func fetchGroup(id: UUID, currentUserID: UUID) async throws -> FriendGroup {
        let row: RemoteGroup = try await client.from("groups")
            .select(Self.groupSelection)
            .eq("id", value: id)
            .single()
            .execute()
            .value
        return row.domain(currentUserID: currentUserID)
    }

    private func fetchIdea(id: UUID) async throws -> Idea {
        do {
            let row: RemoteIdea = try await client.from("ideas")
                .select(Self.ideaSelection)
                .eq("id", value: id)
                .single()
                .execute()
                .value
            return row.domain
        } catch {
            throw RepositoryError.ideaNotFound
        }
    }

    private func duplicateIdea(groupID: UUID, normalizedURL: String?, excluding: UUID? = nil) async throws -> UUID? {
        guard let normalizedURL else { return nil }
        var query = client.from("ideas").select("id")
            .eq("group_id", value: groupID)
            .eq("normalized_url", value: normalizedURL)
        if let excluding { query = query.neq("id", value: excluding) }
        let rows: [RemoteID] = try await query.limit(1).execute().value
        return rows.first?.id
    }

    private static let groupSelection = "id,name,emoji,group_members(role,profiles(id,display_name)),plans(id,completed_at)"
    private static let ideaSelection = "id,group_id,title,category,location,distance_km,price_level,note,source_url,image_path,created_at,status,creator:profiles!ideas_created_by_fkey(id,display_name),reactions(user_id,kind),comments(id,body,created_at,author:profiles!comments_author_id_fkey(id,display_name))"
}

private struct RemoteID: Decodable { let id: UUID }

private struct RemoteInvitation: Decodable {
    let code: String
    let expiresAt: Date
    enum CodingKeys: String, CodingKey { case code, expiresAt = "expires_at" }
}

private struct RemotePreference: Decodable {
    let groupID: UUID
    let frequency: String
    enum CodingKeys: String, CodingKey { case groupID = "group_id", frequency }
}

private struct RemoteActivityMetadata: Decodable {
    let title: String?
    let groupName: String?
    enum CodingKeys: String, CodingKey { case title, groupName = "group_name" }
}

private struct RemoteActivity: Decodable {
    let id: UUID
    let groupID: UUID
    let kind: String
    let ideaID: UUID?
    let metadata: RemoteActivityMetadata
    let createdAt: Date
    let actor: RemoteProfile
    enum CodingKeys: String, CodingKey {
        case id, kind, metadata, actor
        case groupID = "group_id", ideaID = "idea_id", createdAt = "created_at"
    }
    var domain: ActivityEvent? {
        guard let activityKind = ActivityKind(rawValue: kind) else { return nil }
        let subject = metadata.title ?? metadata.groupName ?? "the group"
        let message = switch activityKind {
        case .ideaAdded: "\(actor.displayName) added \(subject)"
        case .reactionChanged: "\(actor.displayName) reacted to \(subject)"
        case .commentAdded: "\(actor.displayName) commented on \(subject)"
        case .planCreated: "\(actor.displayName) planned \(subject)"
        case .planCompleted: "\(actor.displayName) completed \(subject)"
        case .memberJoined: "\(actor.displayName) joined \(subject)"
        }
        return ActivityEvent(id: id, groupID: groupID, actor: actor.domain, kind: activityKind, message: message, createdAt: createdAt, ideaID: ideaID)
    }
}

private struct RemoteProfile: Decodable {
    let id: UUID
    let displayName: String
    enum CodingKeys: String, CodingKey { case id, displayName = "display_name" }
    var domain: User { User(id: id, displayName: displayName) }
}

private struct RemoteMember: Decodable {
    let role: String
    let profiles: RemoteProfile
    var domain: GroupMember { GroupMember(user: profiles.domain, role: role == "admin" ? .admin : .member) }
}

private struct RemotePlanSummary: Decodable {
    let id: UUID
    let completedAt: Date?
    enum CodingKeys: String, CodingKey { case id, completedAt = "completed_at" }
}

private struct RemoteGroup: Decodable {
    let id: UUID
    let name: String
    let emoji: String
    let groupMembers: [RemoteMember]
    let plans: [RemotePlanSummary]
    enum CodingKeys: String, CodingKey { case id, name, emoji, groupMembers = "group_members", plans }
    func domain(currentUserID: UUID) -> FriendGroup {
        FriendGroup(id: id, name: name, emoji: emoji, members: groupMembers.map(\.domain), activePlanID: plans.first(where: { $0.completedAt == nil })?.id)
    }
}

private struct RemoteReaction: Decodable {
    let userID: UUID
    let kind: String
    enum CodingKeys: String, CodingKey { case userID = "user_id", kind }
    var domain: Reaction? { ReactionKind(remoteValue: kind).map { Reaction(userID: userID, kind: $0) } }
}

private struct RemoteComment: Decodable {
    let id: UUID
    let body: String
    let createdAt: Date
    let author: RemoteProfile
    enum CodingKeys: String, CodingKey { case id, body, createdAt = "created_at", author }
    var domain: Comment { Comment(id: id, author: author.domain, body: body, createdAt: createdAt) }
}

private struct RemoteIdea: Decodable {
    let id: UUID
    let groupID: UUID
    let title: String
    let category: String
    let location: String?
    let distanceKilometres: Double?
    let priceLevel: Int?
    let note: String?
    let sourceURL: String?
    let imagePath: String?
    let createdAt: Date
    let status: String
    let creator: RemoteProfile
    let reactions: [RemoteReaction]
    let comments: [RemoteComment]
    enum CodingKeys: String, CodingKey {
        case id, title, category, location, note, status, creator, reactions, comments
        case groupID = "group_id", distanceKilometres = "distance_km", priceLevel = "price_level"
        case sourceURL = "source_url", imagePath = "image_path", createdAt = "created_at"
    }
    var domain: Idea {
        Idea(
            id: id, groupID: groupID, title: title,
            category: IdeaCategory(remoteValue: category) ?? .other,
            location: location, distanceKilometres: distanceKilometres, priceLevel: priceLevel,
            note: note, sourceURL: sourceURL.flatMap(URL.init(string:)), imageURL: imagePath.flatMap(URL.init(string:)),
            creator: creator.domain, createdAt: createdAt, status: IdeaStatus(rawValue: status) ?? .board,
            reactions: reactions.compactMap(\.domain), comments: comments.map(\.domain)
        )
    }
}

private struct CreateGroupArguments: Encodable {
    let groupName: String; let groupEmoji: String
    enum CodingKeys: String, CodingKey { case groupName = "group_name", groupEmoji = "group_emoji" }
}
private struct AcceptInviteArguments: Encodable {
    let inviteCode: String
    enum CodingKeys: String, CodingKey { case inviteCode = "invite_code" }
}
private struct CreateInviteArguments: Encodable {
    let targetGroup: UUID
    enum CodingKeys: String, CodingKey { case targetGroup = "target_group" }
}
private struct ReactionArguments: Encodable {
    let targetIdea: UUID; let newKind: String
    enum CodingKeys: String, CodingKey { case targetIdea = "target_idea", newKind = "new_kind" }
}
private struct StatusArguments: Encodable {
    let targetIdea: UUID; let newStatus: String
    enum CodingKeys: String, CodingKey { case targetIdea = "target_idea", newStatus = "new_status" }
}
private struct RegisterTokenArguments: Encodable {
    let rawToken: String; let apnsEnvironment: String
    enum CodingKeys: String, CodingKey { case rawToken = "raw_token", apnsEnvironment = "apns_environment" }
}
private struct PreferenceArguments: Encodable {
    let targetGroup: UUID; let newFrequency: String
    enum CodingKeys: String, CodingKey { case targetGroup = "target_group", newFrequency = "new_frequency" }
}
private struct InsertComment: Encodable {
    let ideaID: UUID; let authorID: UUID; let body: String
    enum CodingKeys: String, CodingKey { case ideaID = "idea_id", authorID = "author_id", body }
}
private struct InsertIdea: Encodable {
    let groupID: UUID; let title: String; let category: String; let location: String?; let priceLevel: Int?
    let note: String?; let sourceURL: String?; let normalizedURL: String?; let createdBy: UUID
    enum CodingKeys: String, CodingKey {
        case groupID = "group_id", title, category, location, priceLevel = "price_level", note
        case sourceURL = "source_url", normalizedURL = "normalized_url", createdBy = "created_by"
    }
}
private struct UpdateIdea: Encodable {
    let title: String; let category: String; let location: String?; let priceLevel: Int?
    let note: String?; let sourceURL: String?; let normalizedURL: String?
    enum CodingKeys: String, CodingKey {
        case title, category, location, priceLevel = "price_level", note
        case sourceURL = "source_url", normalizedURL = "normalized_url"
    }
}

private extension IdeaCategory {
    init?(remoteValue: String) { self.init(rawValue: remoteValue.capitalized) }
    var remoteValue: String { rawValue.lowercased() }
}
private extension ReactionKind {
    init?(remoteValue: String) {
        switch remoteValue {
        case "in": self = .inForIt
        case "maybe": self = .maybe
        case "pass": self = .pass
        default: return nil
        }
    }
    var remoteValue: String { switch self { case .inForIt: "in"; case .maybe: "maybe"; case .pass: "pass" } }
}
private extension NotificationFrequency {
    init?(remoteValue: String) {
        switch remoteValue {
        case "instant": self = .instant
        case "daily_digest": self = .dailyDigest
        case "off": self = .off
        default: return nil
        }
    }
    var remoteValue: String { switch self { case .instant: "instant"; case .dailyDigest: "daily_digest"; case .off: "off" } }
}
private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
