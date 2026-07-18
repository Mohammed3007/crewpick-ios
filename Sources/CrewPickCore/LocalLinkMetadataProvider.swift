import Foundation

public struct LocalLinkMetadataProvider: LinkMetadataProviding {
    public init() {}

    public func metadata(for url: URL) async throws -> IdeaDraft {
        guard let host = url.host?.lowercased() else { throw LinkMetadataError.unsupportedURL }
        if host.contains("instagram.com") && url.path.lowercased().contains("greygardens") {
            return IdeaDraft(title: "Grey Gardens", category: .food, location: "Kensington Market", priceLevel: 2, note: "Natural wine bar — confirm the details before posting.", sourceURL: url)
        }
        let pathName = url.pathComponents.last?.removingPercentEncoding?
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = host.replacingOccurrences(of: "www.", with: "").components(separatedBy: ".").first?.capitalized
        guard let title = [pathName, fallback].compactMap({ $0 }).first(where: { !$0.isEmpty }) else {
            throw LinkMetadataError.metadataUnavailable
        }
        return IdeaDraft(title: title, category: .other, sourceURL: url)
    }
}

public enum LinkMetadataError: Error, Equatable, Sendable { case unsupportedURL, metadataUnavailable }
