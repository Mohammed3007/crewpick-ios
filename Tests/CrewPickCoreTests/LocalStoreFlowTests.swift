import Foundation
#if canImport(Testing)
import Testing
@testable import CrewPickCore

@Suite("Local v1 workflows")
struct LocalStoreFlowTests {
    @Test("Creates a group with the owner as admin")
    func createGroup() async throws {
        let store = SampleData.store()
        let group = try await store.createGroup(name: "  Brunch Club  ", emoji: "🍳", owner: SampleData.alex)
        #expect(group.name == "Brunch Club")
        #expect(group.members == [.init(user: SampleData.alex, role: .admin)])
    }

    @Test("Joins the deterministic preview invite")
    func joinGroup() async throws {
        let store = SampleData.store()
        let group = try await store.joinGroup(code: "triv-88", user: SampleData.alex)
        #expect(group.name == "Trivia Squad")
        #expect(group.members.contains(where: { $0.user.id == SampleData.alex.id }))
    }

    @Test("Rejects invalid invites")
    func invalidInvite() async {
        let store = SampleData.store()
        await #expect(throws: RepositoryError.invalidInvite) {
            try await store.joinGroup(code: "wrong-code", user: SampleData.alex)
        }
    }

    @Test("Only an admin can remove a member")
    func memberRemovalPermission() async {
        let store = SampleData.store()
        await #expect(throws: RepositoryError.permissionDenied) {
            try await store.removeMember(SampleData.priya.id, from: SampleData.weekendCrewID, requestedBy: SampleData.sam.id)
        }
    }

    @Test("Comments trim whitespace and persist")
    func comment() async throws {
        let store = SampleData.store()
        let idea = try await store.addComment("  Let's do Friday  ", ideaID: SampleData.ideas[0].id, author: SampleData.alex)
        #expect(idea.comments.last?.body == "Let's do Friday")
        #expect(idea.comments.last?.author.id == SampleData.alex.id)
    }

    @Test("Only one idea can be planned per group")
    func oneActivePlan() async throws {
        let store = SampleData.store()
        _ = try await store.setStatus(.planned, ideaID: SampleData.ideas[0].id)
        _ = try await store.setStatus(.planned, ideaID: SampleData.ideas[1].id)
        let ideas = try await store.ideas(in: SampleData.weekendCrewID)
        #expect(ideas.first(where: { $0.id == SampleData.ideas[0].id })?.status == .board)
        #expect(ideas.first(where: { $0.id == SampleData.ideas[1].id })?.status == .planned)
    }
}
#endif
