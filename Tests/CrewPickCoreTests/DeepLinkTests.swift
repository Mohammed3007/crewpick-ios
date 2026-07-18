import Foundation
#if canImport(Testing)
import Testing
@testable import CrewPickCore

@Suite("Deep links")
struct DeepLinkTests {
    @Test("Parses universal idea links")
    func universalIdea() throws {
        let group = SampleData.weekendCrewID
        let idea = SampleData.ideas[0].id
        let url = try #require(URL(string: "https://crewpick.app/groups/\(group)/ideas/\(idea)"))
        #expect(DeepLinkDestination(url: url) == .idea(groupID: group, ideaID: idea))
    }

    @Test("Parses custom invitation links")
    func customInvite() throws {
        let url = try #require(URL(string: "crewpick://join/triv-88"))
        #expect(DeepLinkDestination(url: url) == .invitation(code: "TRIV88"))
    }

    @Test("Rejects untrusted hosts")
    func rejectsHost() throws {
        let url = try #require(URL(string: "https://example.com/join/TRIV88"))
        #expect(DeepLinkDestination(url: url) == nil)
    }
}
#endif
