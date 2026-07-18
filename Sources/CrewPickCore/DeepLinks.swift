import Foundation

public enum DeepLinkDestination: Equatable, Sendable {
    case group(UUID)
    case invitation(code: String)
    case idea(groupID: UUID, ideaID: UUID)
    case plan(groupID: UUID, planID: UUID)

    public init?(url: URL) {
        guard ["https", "crewpick"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        let route: [String]
        if url.scheme?.lowercased() == "crewpick", let host = url.host { route = [host] + components }
        else {
            guard url.host?.lowercased() == "crewpick.app" else { return nil }
            route = components
        }
        guard let first = route.first else { return nil }
        switch first {
        case "join" where route.count == 2:
            let code = InviteCode.normalize(route[1])
            guard InviteCode.isValid(code) else { return nil }
            self = .invitation(code: code)
        case "groups" where route.count == 2:
            guard let groupID = UUID(uuidString: route[1]) else { return nil }
            self = .group(groupID)
        case "groups" where route.count == 4 && route[2] == "ideas":
            guard let groupID = UUID(uuidString: route[1]), let ideaID = UUID(uuidString: route[3]) else { return nil }
            self = .idea(groupID: groupID, ideaID: ideaID)
        case "groups" where route.count == 4 && route[2] == "plans":
            guard let groupID = UUID(uuidString: route[1]), let planID = UUID(uuidString: route[3]) else { return nil }
            self = .plan(groupID: groupID, planID: planID)
        default: return nil
        }
    }
}

public enum PendingImportState: String, Codable, Sendable { case awaitingConfirmation, queuedOffline, importing, failed }

public struct PendingImport: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let sourceURL: URL
    public var destinationGroupID: UUID?
    public var state: PendingImportState
    public let createdAt: Date

    public init(id: UUID = UUID(), sourceURL: URL, destinationGroupID: UUID? = nil, state: PendingImportState = .awaitingConfirmation, createdAt: Date = .now) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationGroupID = destinationGroupID
        self.state = state
        self.createdAt = createdAt
    }
}

