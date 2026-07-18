import Foundation

public enum BoardSort: Equatable, Sendable { case topRanked, newest }

public struct BoardFilter: Equatable, Sendable {
    public var category: IdeaCategory?
    public var unvotedByUserID: UUID?
    public var maximumPrice: Int?
    public var maximumDistanceKilometres: Double?

    public init(category: IdeaCategory? = nil, unvotedByUserID: UUID? = nil, maximumPrice: Int? = nil, maximumDistanceKilometres: Double? = nil) {
        self.category = category
        self.unvotedByUserID = unvotedByUserID
        self.maximumPrice = maximumPrice
        self.maximumDistanceKilometres = maximumDistanceKilometres
    }
}

public enum BoardEngine {
    public static func ranked(_ ideas: [Idea], filter: BoardFilter = .init(), sort: BoardSort = .topRanked) -> [Idea] {
        ideas
            .filter { $0.status == .board }
            .filter { filter.category == nil || $0.category == filter.category }
            .filter { filter.unvotedByUserID == nil || $0.reaction(from: filter.unvotedByUserID!) == nil }
            .filter { filter.maximumPrice == nil || ($0.priceLevel.map { $0 <= filter.maximumPrice! } ?? false) }
            .filter { filter.maximumDistanceKilometres == nil || ($0.distanceKilometres.map { $0 <= filter.maximumDistanceKilometres! } ?? false) }
            .sorted { lhs, rhs in
                switch sort {
                case .newest:
                    return lhs.createdAt > rhs.createdAt
                case .topRanked:
                    let left = (lhs.count(.inForIt), lhs.count(.maybe), lhs.createdAt)
                    let right = (rhs.count(.inForIt), rhs.count(.maybe), rhs.createdAt)
                    if left.0 != right.0 { return left.0 > right.0 }
                    if left.1 != right.1 { return left.1 > right.1 }
                    return left.2 > right.2
                }
            }
    }

    public static func finalists(from ideas: [Idea], filter: BoardFilter = .init()) -> [Idea] {
        Array(ranked(ideas, filter: filter).prefix(3))
    }

    public static func similarlyRankedFinalists(_ finalists: [Idea]) -> [Idea] {
        guard let leader = finalists.first else { return [] }
        return finalists.filter {
            abs($0.count(.inForIt) - leader.count(.inForIt)) <= 1 &&
            abs($0.count(.maybe) - leader.count(.maybe)) <= 1
        }
    }

    public static func pickForUs(from finalists: [Idea], randomIndex: (Int) -> Int) -> Idea? {
        let candidates = similarlyRankedFinalists(finalists)
        guard !candidates.isEmpty else { return nil }
        let index = min(max(randomIndex(candidates.count), 0), candidates.count - 1)
        return candidates[index]
    }
}

public enum ReactionRules {
    public static func applying(_ selected: ReactionKind, by userID: UUID, to idea: Idea) -> Idea {
        var updated = idea
        let current = updated.reaction(from: userID)
        updated.reactions.removeAll { $0.userID == userID }
        if current != selected {
            updated.reactions.append(Reaction(userID: userID, kind: selected))
        }
        return updated
    }
}
