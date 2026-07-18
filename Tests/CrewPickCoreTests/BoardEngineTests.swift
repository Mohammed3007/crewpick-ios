import Foundation
#if canImport(Testing)
import Testing
@testable import CrewPickCore

@Suite("Board ranking and decision mode")
struct BoardEngineTests {
    @Test("Ranks by I'm in, then Maybe, then recency")
    func rankingOrder() {
        let ideas = SampleData.ideas
        let result = BoardEngine.ranked(ideas)
        #expect(result.map(\.title).prefix(3) == ["Bar Raval", "Kensington Market food crawl", "Blue Jays vs. Red Sox"])
    }

    @Test("Filters category, price and distance together")
    func filters() {
        let filter = BoardFilter(category: .food, maximumPrice: 2, maximumDistanceKilometres: 2)
        let result = BoardEngine.ranked(SampleData.ideas, filter: filter)
        #expect(result.map(\.title) == ["Kensington Market food crawl"])
    }

    @Test("Unvoted excludes every reaction kind")
    func unvoted() {
        let filter = BoardFilter(unvotedByUserID: SampleData.alex.id)
        let result = BoardEngine.ranked(SampleData.ideas, filter: filter)
        #expect(!result.contains(where: { $0.title == "Toronto Island bike loop" }))
        #expect(!result.contains(where: { $0.title == "Axe throwing at BATL" }))
    }

    @Test("Decision mode returns at most three")
    func finalists() {
        let result = BoardEngine.finalists(from: SampleData.ideas, filter: .init(category: .food, maximumPrice: 2))
        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.category == .food && ($0.priceLevel ?? 99) <= 2 })
    }

    @Test("Random selection is injectable and limited to similar finalists")
    func pickForUs() {
        let finalists = BoardEngine.finalists(from: SampleData.ideas)
        let selected = BoardEngine.pickForUs(from: finalists) { count in count - 1 }
        #expect(selected?.title == "Blue Jays vs. Red Sox")
    }
}
#endif
