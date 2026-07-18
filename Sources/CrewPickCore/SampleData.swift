import Foundation

public enum SampleData {
    public static let alex = User(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, displayName: "Alex Chen", email: "alex.chen@hey.com")
    public static let maya = User(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, displayName: "Maya")
    public static let sam = User(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, displayName: "Sam")
    public static let priya = User(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, displayName: "Priya")
    public static let jordan = User(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, displayName: "Jordan")

    public static let weekendCrewID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    public static let cottageCrewID = UUID(uuidString: "10000000-0000-0000-0000-000000000002")!

    public static let groups: [FriendGroup] = [
        FriendGroup(id: weekendCrewID, name: "Weekend Crew", emoji: "🎉", members: [
            .init(user: alex, role: .admin), .init(user: maya, role: .member),
            .init(user: sam, role: .member), .init(user: priya, role: .member),
            .init(user: jordan, role: .member)
        ]),
        FriendGroup(id: cottageCrewID, name: "Cottage Crew", emoji: "🌲", members: [
            .init(user: alex, role: .admin), .init(user: sam, role: .member), .init(user: maya, role: .member)
        ])
    ]

    public static let ideas: [Idea] = {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func reactions(_ ins: [User], _ maybes: [User] = [], _ passes: [User] = []) -> [Reaction] {
            ins.map { .init(userID: $0.id, kind: .inForIt) } + maybes.map { .init(userID: $0.id, kind: .maybe) } + passes.map { .init(userID: $0.id, kind: .pass) }
        }
        return [
            Idea(groupID: weekendCrewID, title: "Bar Raval", category: .food, location: "Little Italy", distanceKilometres: 2.1, priceLevel: 3, note: "Standing-room pintxos and vermouth. Go before 6 or after 10.", sourceURL: URL(string: "https://instagram.com/p/barraval"), creator: maya, createdAt: now - 2 * day, reactions: reactions([maya, priya, jordan], [sam])),
            Idea(groupID: weekendCrewID, title: "Kensington Market food crawl", category: .food, location: "Kensington Market", distanceKilometres: 1.4, priceLevel: 2, note: "Tacos at Seven Lives, cheese shop, then Moonbean.", creator: sam, createdAt: now - 3 * day, reactions: reactions([sam, maya, jordan], [priya])),
            Idea(groupID: weekendCrewID, title: "Blue Jays vs. Red Sox", category: .event, location: "Rogers Centre", distanceKilometres: 3, priceLevel: 2, note: "Friday game has fireworks.", creator: priya, createdAt: now - day, reactions: reactions([priya, jordan], [maya, sam])),
            Idea(groupID: weekendCrewID, title: "Toronto Island bike loop", category: .activity, location: "Centre Island", distanceKilometres: 4.2, priceLevel: 1, note: "Rent at the pier and picnic on the way back.", creator: alex, createdAt: now - 5 * day, reactions: reactions([alex, sam], [maya])),
            Idea(groupID: weekendCrewID, title: "Pai Northern Thai Kitchen", category: .food, location: "Entertainment District", distanceKilometres: 2.6, priceLevel: 2, note: "Khao soi. That is all.", sourceURL: URL(string: "https://paitoronto.com"), creator: maya, createdAt: now - 6 * day, reactions: reactions([maya], [jordan, priya])),
            Idea(groupID: weekendCrewID, title: "Axe throwing at BATL", category: .activity, location: "Port Lands", distanceKilometres: 5.1, priceLevel: 2, note: "Loser buys wings.", creator: jordan, createdAt: now - 4 * day, reactions: reactions([jordan], [sam], [alex]))
        ]
    }()

    public static func store() -> LocalStore { LocalStore(groups: groups, ideas: ideas) }
}

