import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SupabaseConfiguration: Equatable, Sendable {
    public let projectURL: URL
    public let anonymousKey: String

    public init(projectURL: URL, anonymousKey: String) throws {
        guard projectURL.scheme == "https", projectURL.host != nil,
              !anonymousKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !projectURL.absoluteString.contains("YOUR_PROJECT") else {
            throw SupabaseClientError.invalidConfiguration
        }
        self.projectURL = projectURL
        self.anonymousKey = anonymousKey
    }
}

public protocol AccessTokenProviding: Sendable {
    func accessToken() async -> String?
}

public actor MutableAccessTokenProvider: AccessTokenProviding {
    private var token: String?

    public init(token: String? = nil) { self.token = token }
    public func accessToken() -> String? { token }
    public func update(token: String?) { self.token = token }
}

public enum SupabaseClientError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidResponse
    case server(status: Int, message: String)
    case decodingFailed
}

public struct SupabaseRESTClient: Sendable {
    private let configuration: SupabaseConfiguration
    private let tokenProvider: any AccessTokenProviding
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        configuration: SupabaseConfiguration,
        tokenProvider: any AccessTokenProviding,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    public func rpc<Arguments: Encodable, Response: Decodable>(
        _ function: String,
        arguments: Arguments,
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await send(path: "rest/v1/rpc/\(function)", method: "POST", body: encoder.encode(arguments))
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw SupabaseClientError.decodingFailed }
    }

    public func rpc<Arguments: Encodable>(_ function: String, arguments: Arguments) async throws {
        _ = try await send(path: "rest/v1/rpc/\(function)", method: "POST", body: encoder.encode(arguments))
    }

    public func get<Response: Decodable>(
        _ table: String,
        queryItems: [URLQueryItem],
        as responseType: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await send(path: "rest/v1/\(table)", method: "GET", queryItems: queryItems)
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw SupabaseClientError.decodingFailed }
    }

    private func send(path: String, method: String, queryItems: [URLQueryItem] = [], body: Data? = nil) async throws -> Data {
        var components = URLComponents(url: configuration.projectURL.appending(path: path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw SupabaseClientError.invalidConfiguration }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.anonymousKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(await tokenProvider.accessToken() ?? configuration.anonymousKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupabaseClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorPayload.self, from: data).message)
                ?? String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw SupabaseClientError.server(status: http.statusCode, message: message)
        }
        return data
    }
}

public struct SupabaseNotificationRegistrar: NotificationRegistering, Sendable {
    private let client: SupabaseRESTClient
    private let environment: String

    public init(client: SupabaseRESTClient, production: Bool) {
        self.client = client
        self.environment = production ? "production" : "sandbox"
    }

    public func register(deviceToken: Data) async throws {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        try await client.rpc("register_device_token", arguments: RegisterTokenArguments(rawToken: token, apnsEnvironment: environment))
    }

    public func setPreference(_ frequency: NotificationFrequency, groupID: UUID) async throws {
        let remoteValue = switch frequency {
        case .instant: "instant"
        case .dailyDigest: "daily_digest"
        case .off: "off"
        }
        try await client.rpc("set_notification_preference", arguments: PreferenceArguments(targetGroup: groupID, newFrequency: remoteValue))
    }
}

private struct ErrorPayload: Decodable { let message: String }

private struct RegisterTokenArguments: Encodable {
    let rawToken: String
    let apnsEnvironment: String
    enum CodingKeys: String, CodingKey { case rawToken = "raw_token", apnsEnvironment = "apns_environment" }
}

private struct PreferenceArguments: Encodable {
    let targetGroup: UUID
    let newFrequency: String
    enum CodingKeys: String, CodingKey { case targetGroup = "target_group", newFrequency = "new_frequency" }
}
