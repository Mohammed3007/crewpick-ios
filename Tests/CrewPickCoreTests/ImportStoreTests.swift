import Foundation
#if canImport(Testing)
import Testing
@testable import CrewPickCore

@Suite("Shared imports and link previews")
struct ImportStoreTests {
    @Test("Pending imports survive a shared-defaults round trip")
    func pendingImportRoundTrip() throws {
        let suiteName = "CrewPickTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SharedImportStore(defaults: defaults)
        let item = PendingImport(
            sourceURL: try #require(URL(string: "https://example.com/weekend-brunch")),
            destinationGroupID: SampleData.weekendCrewID
        )

        try store.append(item)
        try store.append(item)
        #expect(store.pendingImports() == [item])

        try store.remove(id: item.id)
        #expect(store.pendingImports().isEmpty)
    }

    @Test("Group summaries are available to the share extension")
    func groupSummaryRoundTrip() throws {
        let suiteName = "CrewPickTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expected = [SharedGroupSummary(id: SampleData.weekendCrewID, name: "Weekend Crew", emoji: "🎉")]
        let store = SharedImportStore(defaults: defaults)
        try store.saveGroups(expected)

        #expect(store.groups() == expected)
    }

    @Test("Known links get a useful preview")
    func knownLinkPreview() async throws {
        let url = try #require(URL(string: "https://www.instagram.com/greygardens/"))
        let draft = try await LocalLinkMetadataProvider().metadata(for: url)

        #expect(draft.title == "Grey Gardens")
        #expect(draft.category == .food)
        #expect(draft.sourceURL == url)
    }

    @Test("Unknown links use readable URL metadata")
    func genericLinkPreview() async throws {
        let url = try #require(URL(string: "https://example.com/late-night-dessert"))
        let draft = try await LocalLinkMetadataProvider().metadata(for: url)

        #expect(draft.title == "late night dessert")
        #expect(draft.category == .other)
        #expect(draft.sourceURL == url)
    }
}
#endif
