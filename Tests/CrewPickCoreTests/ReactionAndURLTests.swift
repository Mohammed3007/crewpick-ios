import Foundation
#if canImport(Testing)
import Testing
@testable import CrewPickCore

@Suite("Reactions and URL import")
struct ReactionAndURLTests {
    @Test("Changing a reaction keeps exactly one per member")
    func reactionChange() {
        let original = SampleData.ideas[0]
        let changed = ReactionRules.applying(.pass, by: SampleData.sam.id, to: original)
        #expect(changed.reaction(from: SampleData.sam.id) == .pass)
        #expect(changed.reactions.filter { $0.userID == SampleData.sam.id }.count == 1)
    }

    @Test("Selecting the current reaction toggles it off")
    func reactionToggle() {
        let original = SampleData.ideas[0]
        let changed = ReactionRules.applying(.maybe, by: SampleData.sam.id, to: original)
        #expect(changed.reaction(from: SampleData.sam.id) == nil)
    }

    @Test("URL normalization removes tracking and cosmetic differences")
    func urlNormalization() throws {
        let first = try #require(URL(string: "https://www.Instagram.com/p/abc/?utm_source=chat&b=2&a=1#comments"))
        let second = try #require(URL(string: "https://instagram.com/p/abc?a=1&b=2"))
        #expect(URLNormalizer.normalize(first) == URLNormalizer.normalize(second))
    }

    @Test("Invite codes ignore punctuation but enforce useful length")
    func invitationRules() {
        #expect(InviteCode.normalize(" triv-88 ") == "TRIV88")
        #expect(InviteCode.isValid("triv-88"))
        #expect(!InviteCode.isValid("abc"))
    }

    @Test("Local repository blocks normalized duplicates")
    func duplicateDetection() async throws {
        let store = SampleData.store()
        let draft = IdeaDraft(title: "Bar Raval again", sourceURL: URL(string: "https://www.instagram.com/p/barraval/?utm_source=share"))
        await #expect(throws: RepositoryError.duplicateIdea(existingIdeaID: SampleData.ideas[0].id)) {
            try await store.add(draft, to: SampleData.weekendCrewID, creator: SampleData.alex)
        }
    }
}
#endif
