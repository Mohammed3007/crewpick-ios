import Foundation
import Supabase

actor SupabaseLinkMetadataProvider: LinkMetadataProviding {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func metadata(for url: URL) async throws -> IdeaDraft {
        let response: MetadataResponse = try await client.functions.invoke(
            "metadata-preview",
            options: FunctionInvokeOptions(body: MetadataRequest(url: url.absoluteString))
        )
        let combined = "\(response.title) \(response.description)".lowercased()
        return IdeaDraft(
            title: response.title,
            category: Self.category(for: combined),
            location: response.siteName,
            priceLevel: nil,
            note: response.description,
            sourceURL: URL(string: response.canonicalURL) ?? url
        )
    }

    private static func category(for text: String) -> IdeaCategory {
        if text.contains("restaurant") || text.contains("menu") || text.contains("food") || text.contains("bar ") { return .food }
        if text.contains("concert") || text.contains("tickets") || text.contains("festival") || text.contains("show ") { return .event }
        if text.contains("hotel") || text.contains("flight") || text.contains("travel") || text.contains("resort") { return .trip }
        if text.contains("class") || text.contains("tour") || text.contains("experience") || text.contains("activity") { return .activity }
        return .other
    }
}

private struct MetadataRequest: Encodable { let url: String }

private struct MetadataResponse: Decodable {
    let title: String
    let description: String
    let siteName: String
    let canonicalURL: String

    enum CodingKeys: String, CodingKey {
        case title, description
        case siteName = "site_name"
        case canonicalURL = "canonical_url"
    }
}
