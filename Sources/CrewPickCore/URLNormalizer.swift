import Foundation

public enum URLNormalizer {
    private static let trackingNames: Set<String> = [
        "fbclid", "gclid", "igshid", "mc_cid", "mc_eid", "ref", "source"
    ]

    public static func normalize(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return nil }
        components.scheme = (components.scheme ?? "https").lowercased()
        components.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        components.fragment = nil
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        components.queryItems = components.queryItems?
            .filter { item in
                let name = item.name.lowercased()
                return !name.hasPrefix("utm_") && !trackingNames.contains(name)
            }
            .sorted { $0.name == $1.name ? ($0.value ?? "") < ($1.value ?? "") : $0.name < $1.name }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        return components.string
    }
}

public enum InviteCode {
    public static func normalize(_ input: String) -> String {
        input.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func isValid(_ input: String) -> Bool {
        (6...10).contains(normalize(input).count)
    }
}

