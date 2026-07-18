#if !canImport(Testing) && canImport(XCTest)
import Foundation
import XCTest
@testable import CrewPickCore

final class XCTestFallbackTests: XCTestCase {
    func testRankingOrder() {
        XCTAssertEqual(
            Array(BoardEngine.ranked(SampleData.ideas).map(\.title).prefix(3)),
            ["Bar Raval", "Kensington Market food crawl", "Blue Jays vs. Red Sox"]
        )
    }

    func testCombinedFilters() {
        let result = BoardEngine.ranked(
            SampleData.ideas,
            filter: .init(category: .food, maximumPrice: 2, maximumDistanceKilometres: 2)
        )
        XCTAssertEqual(result.map(\.title), ["Kensington Market food crawl"])
    }

    func testReactionChangeAndToggle() {
        let original = SampleData.ideas[0]
        let changed = ReactionRules.applying(.pass, by: SampleData.sam.id, to: original)
        XCTAssertEqual(changed.reaction(from: SampleData.sam.id), .pass)
        XCTAssertEqual(changed.reactions.filter { $0.userID == SampleData.sam.id }.count, 1)
        let toggled = ReactionRules.applying(.maybe, by: SampleData.sam.id, to: original)
        XCTAssertNil(toggled.reaction(from: SampleData.sam.id))
    }

    func testURLNormalization() throws {
        let first = try XCTUnwrap(URL(string: "https://www.Instagram.com/p/abc/?utm_source=chat&b=2&a=1#comments"))
        let second = try XCTUnwrap(URL(string: "https://instagram.com/p/abc?a=1&b=2"))
        XCTAssertEqual(URLNormalizer.normalize(first), URLNormalizer.normalize(second))
    }

    func testInviteRules() {
        XCTAssertEqual(InviteCode.normalize(" triv-88 "), "TRIV88")
        XCTAssertTrue(InviteCode.isValid("triv-88"))
        XCTAssertFalse(InviteCode.isValid("abc"))
    }

    func testDuplicateDetection() async throws {
        let store = SampleData.store()
        let draft = IdeaDraft(title: "Bar Raval again", sourceURL: URL(string: "https://www.instagram.com/p/barraval/?utm_source=share"))
        do {
            _ = try await store.add(draft, to: SampleData.weekendCrewID, creator: SampleData.alex)
            XCTFail("Expected a duplicate error")
        } catch let error as RepositoryError {
            XCTAssertEqual(error, .duplicateIdea(existingIdeaID: SampleData.ideas[0].id))
        }
    }
}
#endif
