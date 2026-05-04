import Foundation
import AuthenticationServices

enum GoogleDriveAuthManager {

    private static let tokenKey = "google_drive_token"
    private static let refreshTokenKey = "google_drive_refresh_token"
    private static let emailKey = "google_drive_email"

    struct TokenInfo: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date
        let email: String
    }

    // MARK: - Sign In

    static func signIn(
        presentingWindow: ASPresentationAnchor
    ) async -> Result<TokenInfo, Error> {
        let clientID = GoogleDriveAuthConfig.clientID
        let redirectURI = "\(GoogleDriveAuthConfig.reversedClientID):/oauth2callback"
        let scope = GoogleDriveAuthConfig.driveFileScope
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "\(scope) email profile"),
            .init(name: "state", value: state),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]

        guard let authURL = components.url else {
            return .failure(makeError("Failed to build Google auth URL."))
        }

        guard let callbackScheme = URL(string: redirectURI)?.scheme else {
            return .failure(makeError("Invalid redirect URI scheme."))
        }

        return await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error {
                    continuation.resume(returning: .failure(error))
                    return
                }

                guard let callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value
                else {
                    continuation.resume(returning: .failure(makeError("No authorization code returned.")))
                    return
                }

                Task {
                    let result = await exchangeCodeForToken(code: code, redirectURI: redirectURI)
                    continuation.resume(returning: result)
                }
            }

            let provider = WindowAnchorProvider(window: presentingWindow)
            session.presentationContextProvider = provider
            session.prefersEphemeralWebBrowserSession = false
            _ = provider // keep alive
            session.start()
        }
    }

    // MARK: - Token Exchange

    private static func exchangeCodeForToken(
        code: String,
        redirectURI: String
    ) async -> Result<TokenInfo, Error> {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            return .failure(makeError("Invalid token endpoint."))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "code": code,
            "client_id": GoogleDriveAuthConfig.clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try await parseTokenResponse(data: data)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Token Refresh

    static func refreshTokenIfNeeded(_ token: TokenInfo) async -> Result<TokenInfo, Error> {
        guard Date() >= token.expiresAt.addingTimeInterval(-60) else {
            return .success(token)
        }

        guard let refreshToken = token.refreshToken else {
            return .failure(makeError("No refresh token available. Please sign in again."))
        }

        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            return .failure(makeError("Invalid token endpoint."))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "refresh_token": refreshToken,
            "client_id": GoogleDriveAuthConfig.clientID,
            "grant_type": "refresh_token"
        ]
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            var refreshed = try await parseTokenResponse(data: data).get()
            // Preserve original refresh token if new one not returned
            if refreshed.refreshToken == nil {
                refreshed = TokenInfo(
                    accessToken: refreshed.accessToken,
                    refreshToken: refreshToken,
                    expiresAt: refreshed.expiresAt,
                    email: token.email
                )
            }
            saveToken(refreshed)
            return .success(refreshed)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Token Parsing

    private static func parseTokenResponse(data: Data) async throws -> Result<TokenInfo, Error> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(makeError("Invalid token response."))
        }

        if let errorDesc = json["error_description"] as? String {
            return .failure(makeError(errorDesc))
        }

        guard let accessToken = json["access_token"] as? String else {
            return .failure(makeError("No access token in response."))
        }

        let expiresIn = json["expires_in"] as? TimeInterval ?? 3600
        let refreshToken = json["refresh_token"] as? String

        // Fetch email from userinfo
        let email = await fetchEmail(accessToken: accessToken) ?? ""

        let tokenInfo = TokenInfo(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            email: email
        )

        saveToken(tokenInfo)
        return .success(tokenInfo)
    }

    private static func fetchEmail(accessToken: String) async -> String? {
        guard let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else { return nil }
        return email
    }

    // MARK: - Storage

    static func saveToken(_ token: TokenInfo) {
        if let data = try? JSONEncoder().encode(token) {
            UserDefaults.standard.set(data, forKey: tokenKey)
        }
    }

    static func loadToken() -> TokenInfo? {
        guard let data = UserDefaults.standard.data(forKey: tokenKey),
              let token = try? JSONDecoder().decode(TokenInfo.self, from: data) else { return nil }
        return token
    }

    static func clearToken() {
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }

    static func isSignedIn() -> Bool {
        loadToken() != nil
    }

    static func signedInEmail() -> String? {
        loadToken()?.email
    }

    // MARK: - Helpers

    private static func makeError(_ message: String) -> NSError {
        NSError(domain: "GoogleDriveAuth", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

// MARK: - Window Anchor Provider

private class WindowAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: ASPresentationAnchor
    init(window: ASPresentationAnchor) { self.window = window }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}
