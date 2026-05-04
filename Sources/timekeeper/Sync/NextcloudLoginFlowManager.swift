import Foundation
import UIKit

enum NextcloudLoginFlowManager {

    struct LoginInit {
        let loginUrl: String
        let pollEndpoint: String
        let pollToken: String
    }

    struct LoginResult {
        let server: String
        let loginName: String
        let appPassword: String
    }

    static func startLogin(serverUrl: String) async -> Result<LoginInit, Error> {
        do {
            let trimmed = normalizeServerUrl(serverUrl)
            let endpoint = "\(trimmed)/index.php/login/v2"

            guard let url = URL(string: endpoint) else {
                return .failure(makeError("Invalid server URL."))
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .failure(makeError("Nextcloud login init failed."))
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard
                let loginUrl = json?["login"] as? String,
                let poll = json?["poll"] as? [String: Any],
                let pollEndpoint = poll["endpoint"] as? String,
                let pollToken = poll["token"] as? String
            else {
                return .failure(makeError("Unexpected response from Nextcloud."))
            }

            return .success(LoginInit(
                loginUrl: loginUrl,
                pollEndpoint: pollEndpoint,
                pollToken: pollToken
            ))
        } catch {
            return .failure(error)
        }
    }

    static func pollForResult(
        init loginInit: LoginInit,
        timeoutSeconds: Double = 180
    ) async -> Result<LoginResult, Error> {
        let deadline = Date().addingTimeInterval(timeoutSeconds)

        while Date() < deadline {
            do {
                guard let url = URL(string: loginInit.pollEndpoint) else {
                    return .failure(makeError("Invalid poll endpoint."))
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 15

                let body = "token=\(loginInit.pollToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? loginInit.pollToken)"
                request.httpBody = body.data(using: .utf8)

                let (data, response) = try await URLSession.shared.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

                if statusCode == 404 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }

                guard (200...299).contains(statusCode) else {
                    return .failure(makeError("Nextcloud polling failed with HTTP \(statusCode)."))
                }

                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                guard
                    let server = json?["server"] as? String,
                    let loginName = json?["loginName"] as? String,
                    let appPassword = json?["appPassword"] as? String
                else {
                    return .failure(makeError("Unexpected poll response from Nextcloud."))
                }

                return .success(LoginResult(
                    server: server,
                    loginName: loginName,
                    appPassword: appPassword
                ))
            } catch {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        return .failure(makeError("Timed out waiting for Nextcloud sign-in."))
    }

    static func openInBrowser(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        Task { @MainActor in
            await UIApplication.shared.open(url)
        }
    }

    private static func normalizeServerUrl(_ serverUrl: String) -> String {
        var trimmed = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed = String(trimmed.dropLast()) }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "https://\(trimmed)"
        }
        return trimmed
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(
            domain: "TimekeeperNextcloud",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
