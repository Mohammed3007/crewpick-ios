import CrewPickCore
import Foundation

@main
struct CrewPickCoreCheck {
    static func main() async throws {
        let ranked = BoardEngine.ranked(SampleData.ideas)
        precondition(Array(ranked.map(\.title).prefix(3)) == [
            "Bar Raval", "Kensington Market food crawl", "Blue Jays vs. Red Sox"
        ])

        let filtered = BoardEngine.ranked(
            SampleData.ideas,
            filter: .init(category: .food, maximumPrice: 2, maximumDistanceKilometres: 2)
        )
        precondition(filtered.map(\.title) == ["Kensington Market food crawl"])

        let changed = ReactionRules.applying(.pass, by: SampleData.sam.id, to: SampleData.ideas[0])
        precondition(changed.reaction(from: SampleData.sam.id) == .pass)
        precondition(changed.reactions.filter { $0.userID == SampleData.sam.id }.count == 1)

        let tracked = URL(string: "https://www.Instagram.com/p/abc/?utm_source=chat&b=2&a=1#comments")!
        let clean = URL(string: "https://instagram.com/p/abc?a=1&b=2")!
        precondition(URLNormalizer.normalize(tracked) == URLNormalizer.normalize(clean))
        precondition(InviteCode.isValid("triv-88"))

        let store = SampleData.store()
        let duplicate = IdeaDraft(
            title: "Bar Raval again",
            sourceURL: URL(string: "https://www.instagram.com/p/barraval/?utm_source=share")
        )
        do {
            _ = try await store.add(duplicate, to: SampleData.weekendCrewID, creator: SampleData.alex)
            preconditionFailure("Duplicate URL was accepted")
        } catch RepositoryError.duplicateIdea {
            // Expected.
        }

        print("CrewPickCoreCheck passed")
    }
}
