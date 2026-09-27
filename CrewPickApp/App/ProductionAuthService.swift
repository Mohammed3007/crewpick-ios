import AuthenticationServices
import CryptoKit
import Foundation
import Supabase

struct AuthenticatedIdentity: Equatable, Sendable {
    let id: UUID
    let displayName: String
    let email: String?
    let accessToken: String
}

@MainActor
final class ProductionAuthService: ObservableObject {
    enum State: Equatable {
        case unavailable
        case signedOut
        case working
        case magicLinkSent(String)
        case signedIn(AuthenticatedIdentity)
        case failed(String)
    }

    @Published private(set) var state: State
    let client: SupabaseClient?
    private var appleNonce: String?

    init(bundle: Bundle = .main) {
        guard
            let value = bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String,
            let url = URL(string: value), url.scheme == "https", url.host != nil,
            let key = bundle.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            client = nil
            state = .unavailable
            return
        }
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: .init(auth: .init(redirectToURL: URL(string: "crewpick://auth-callback"), flowType: .pkce))
        )
        state = .signedOut
    }

    var isConfigured: Bool { client != nil }

    func restoreSession() async {
        guard let client else { return }
        do {
            let session = try await client.auth.session
            state = .signedIn(identity(from: session))
        } catch {
            state = .signedOut
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func completeAppleAuthorization(_ result: Result<ASAuthorization, Error>) async -> AuthenticatedIdentity? {
        guard let client else { return nil }
        state = .working
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                throw ProductionAuthError.missingAppleCredential
            }
            appleNonce = nil
            let session = try await client.auth.signInWithIdToken(credentials: .init(
                provider: .apple,
                idToken: idToken,
                nonce: nonce
            ))
            if let name = PersonNameComponentsFormatter().string(from: credential.fullName ?? .init()).nilIfBlank {
                _ = try await client.auth.update(user: .init(data: ["full_name": .string(name)]))
            }
            let authenticated = identity(from: session, fallbackName: credential.fullName)
            state = .signedIn(authenticated)
            return authenticated
        } catch {
            appleNonce = nil
            if (error as? ASAuthorizationError)?.code == .canceled {
                state = .signedOut
            } else {
                state = .failed("Sign in with Apple couldn't be completed. Please try again.")
            }
            return nil
        }
    }

    func sendMagicLink(to email: String) async throws {
        guard let client else { throw ProductionAuthError.notConfigured }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.contains("@"), normalized.contains(".") else {
            state = .failed("Enter a valid email address.")
            throw ProductionAuthError.invalidEmail
        }
        state = .working
        do {
            try await client.auth.signInWithOTP(
                email: normalized,
                redirectTo: URL(string: "crewpick://auth-callback"),
                shouldCreateUser: true
            )
            state = .magicLinkSent(normalized)
        } catch {
            state = .failed("The sign-in email couldn't be sent. Check your connection and try again.")
            throw error
        }
    }

    func handleCallback(_ url: URL) async -> AuthenticatedIdentity? {
        guard url.scheme?.lowercased() == "crewpick", url.host?.lowercased() == "auth-callback", let client else { return nil }
        state = .working
        do {
            let session = try await client.auth.session(from: url)
            let authenticated = identity(from: session)
            state = .signedIn(authenticated)
            return authenticated
        } catch {
            state = .failed("That sign-in link is invalid or expired. Request a new one.")
            return nil
        }
    }

    func signOut() async {
        guard let client else { return }
        do {
            try await client.auth.signOut()
            state = .signedOut
        } catch {
            state = .failed("CrewPick couldn't sign out. Please try again.")
        }
    }

    private func identity(from session: Session, fallbackName: PersonNameComponents? = nil) -> AuthenticatedIdentity {
        let metadataName = session.user.userMetadata["full_name"]?.stringValue?.nilIfBlank
        let appleName = fallbackName.map(PersonNameComponentsFormatter().string(from:))?.nilIfBlank
        let emailName = session.user.email?.split(separator: "@").first.map(String.init)
        return AuthenticatedIdentity(
            id: session.user.id,
            displayName: metadataName ?? appleName ?? emailName ?? "CrewPick member",
            email: session.user.email,
            accessToken: session.accessToken
        )
    }

    static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var random = [UInt8](repeating: 0, count: 16)
        while result.count < length {
            guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else {
                preconditionFailure("Unable to generate a secure nonce")
            }
            for byte in random where result.count < length && byte < alphabet.count * (256 / alphabet.count) {
                result.append(alphabet[Int(byte) % alphabet.count])
            }
        }
        return result
    }
}

enum ProductionAuthError: Error, Equatable { case notConfigured, invalidEmail, missingAppleCredential }

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
