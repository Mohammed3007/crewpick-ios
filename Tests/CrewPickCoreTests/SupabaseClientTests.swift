import Foundation
#if canImport(Testing)
import Testing
@testable import CrewPickCore

@Suite("Supabase client configuration")
struct SupabaseClientTests {
    @Test("Accepts an HTTPS project URL and public anonymous key")
    func validConfiguration() throws {
        let url = try #require(URL(string: "https://project-ref.supabase.co"))
        let configuration = try SupabaseConfiguration(projectURL: url, anonymousKey: "public-anon-key")
        #expect(configuration.projectURL == url)
        #expect(configuration.anonymousKey == "public-anon-key")
    }

    @Test("Rejects placeholders, HTTP, and empty keys", arguments: [
        ("https://YOUR_PROJECT.supabase.co", "key"),
        ("http://project-ref.supabase.co", "key"),
        ("https://project-ref.supabase.co", "")
    ])
    func invalidConfiguration(urlString: String, key: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(throws: SupabaseClientError.invalidConfiguration) {
            try SupabaseConfiguration(projectURL: url, anonymousKey: key)
        }
    }

    @Test("Mutable access tokens support session restoration")
    func mutableToken() async {
        let provider = MutableAccessTokenProvider()
        #expect(await provider.accessToken() == nil)
        await provider.update(token: "session-token")
        #expect(await provider.accessToken() == "session-token")
    }
}
#endif
