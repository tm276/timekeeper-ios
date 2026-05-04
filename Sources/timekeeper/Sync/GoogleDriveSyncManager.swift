import Foundation

enum GoogleDriveSyncManager {

    private static let rootFolderName = "TimeKeeper"
    private static let folderMimeType = "application/vnd.google-apps.folder"

    // MARK: - Sync

    static func syncCurrentWindow(
        store: TimeLogStore,
        client: ClientProfile
    ) -> Result<String, Error> {
        guard var token = GoogleDriveAuthManager.loadToken() else {
            return .failure(makeError("Not signed in to Google Drive."))
        }

        // Refresh token synchronously if needed
        if Date() >= token.expiresAt.addingTimeInterval(-60) {
            guard let refreshToken = token.refreshToken else {
                return .failure(makeError("Token expired. Please sign in to Google Drive again."))
            }
            switch refreshAccessToken(refreshToken: refreshToken) {
            case .success(let refreshed): token = refreshed
            case .failure(let error): return .failure(error)
            }
        }

        do {
            let entries = store.getEntriesForClient(clientId: client.id)
            let urls = try CsvShareUtils.writeWindowedCSVs(
                entries: entries,
                client: client,
                settings: store.settings
            )

            guard let fileURL = urls.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else {
                return .failure(makeError("No CSV file generated."))
            }

            let folderPath = buildClientRemoteFolder(
                baseFolder: client.googleDriveFolder,
                clientName: client.clientName
            )

            let accessToken = token.accessToken
            let folderId = try ensureFolderPathExists(folderPath: folderPath, accessToken: accessToken)

            let windowKey = "\(client.id)_\(fileURL.deletingPathExtension().lastPathComponent)"
            let mappings = store.loadDriveMappings()
            let existingMapping = mappings.first { $0.windowKey == windowKey }

            let remoteFileId: String
            if let existing = existingMapping {
                remoteFileId = try updateFile(
                    fileId: existing.driveFileId,
                    fileURL: fileURL,
                    accessToken: accessToken
                )
            } else {
                remoteFileId = try createFile(
                    fileURL: fileURL,
                    parentId: folderId,
                    accessToken: accessToken
                )
                var updated = mappings
                updated.removeAll { $0.windowKey == windowKey }
                updated.append(DriveFileMapping(windowKey: windowKey, driveFileId: remoteFileId))
                store.saveDriveMappings(updated)
            }

            return .success(remoteFileId)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Folder Management

    private static func ensureFolderPathExists(folderPath: String, accessToken: String) throws -> String {
        let segments = folderPath.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        var parentId: String? = nil
        for segment in segments {
            parentId = try ensureSingleFolderExists(name: segment, parentId: parentId, accessToken: accessToken)
        }
        guard let finalId = parentId else {
            throw makeError("Drive folder path is empty.")
        }
        return finalId
    }

    private static func ensureSingleFolderExists(name: String, parentId: String?, accessToken: String) throws -> String {
        let escapedName = name.replacingOccurrences(of: "'", with: "\\'")
        let parentQuery = parentId.map { "and '\($0)' in parents" } ?? "and 'root' in parents"
        let query = "mimeType = '\(folderMimeType)' and trashed = false and name = '\(escapedName)' \(parentQuery)"

        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "spaces", value: "drive"),
            .init(name: "fields", value: "files(id,name)"),
            .init(name: "pageSize", value: "1")
        ]

        let result = try performRequest(url: components.url!, method: "GET", accessToken: accessToken, body: nil, contentType: nil)
        if let files = result["files"] as? [[String: Any]], let existing = files.first, let id = existing["id"] as? String {
            return id
        }

        // Create folder
        let metadata: [String: Any] = [
            "name": name,
            "mimeType": folderMimeType,
            "parents": [parentId ?? "root"]
        ]
        let body = try JSONSerialization.data(withJSONObject: metadata)
        let created = try performRequest(
            url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id,name")!,
            method: "POST",
            accessToken: accessToken,
            body: body,
            contentType: "application/json"
        )
        guard let id = created["id"] as? String else {
            throw makeError("Failed to create Drive folder.")
        }
        return id
    }

    // MARK: - File Upload

    private static func createFile(fileURL: URL, parentId: String, accessToken: String) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let metadata: [String: Any] = [
            "name": fileURL.lastPathComponent,
            "mimeType": "text/csv",
            "parents": [parentId]
        ]
        return try multipartUpload(metadata: metadata, fileData: data, accessToken: accessToken)
    }

    private static func updateFile(fileId: String, fileURL: URL, accessToken: String) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(fileId)?uploadType=media&fields=id")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("text/csv", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let response = try synchronousRequest(request)
        guard let id = response["id"] as? String else { return fileId }
        return id
    }

    private static func multipartUpload(metadata: [String: Any], fileData: Data, accessToken: String) throws -> String {
        let boundary = "boundary_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
        let url = URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let metadataJSON = try JSONSerialization.data(withJSONObject: metadata)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(metadataJSON)
        body.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--".data(using: .utf8)!)

        request.httpBody = body
        let response = try synchronousRequest(request)
        guard let id = response["id"] as? String else {
            throw makeError("No file ID returned from Drive upload.")
        }
        return id
    }

    // MARK: - HTTP

    private static func performRequest(
        url: URL,
        method: String,
        accessToken: String,
        body: Data?,
        contentType: String?
    ) throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        return try synchronousRequest(request)
    }

    private static func refreshAccessToken(refreshToken: String) -> Result<GoogleDriveAuthManager.TokenInfo, Error> {
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
            let json = try synchronousRequest(request)
            guard let accessToken = json["access_token"] as? String else {
                return .failure(makeError("No access token in refresh response."))
            }
            let expiresIn = json["expires_in"] as? TimeInterval ?? 3600
            let newRefreshToken = json["refresh_token"] as? String ?? refreshToken
            let existing = GoogleDriveAuthManager.loadToken()
            let token = GoogleDriveAuthManager.TokenInfo(
                accessToken: accessToken,
                refreshToken: newRefreshToken,
                expiresAt: Date().addingTimeInterval(expiresIn),
                email: existing?.email ?? ""
            )
            GoogleDriveAuthManager.saveToken(token)
            return .success(token)
        } catch {
            return .failure(error)
        }
    }

    private static func synchronousRequest(_ request: URLRequest) throws -> [String: Any] {
        final class Box: @unchecked Sendable { var data: Data?; var error: Error? }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, _, error in
            box.data = data
            box.error = error
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let error = box.error { throw error }
        guard let data = box.data else { throw makeError("No response data.") }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw makeError("Invalid JSON response.")
        }
        if let errorObj = json["error"] as? [String: Any],
           let message = errorObj["message"] as? String {
            throw makeError("Drive API error: \(message)")
        }
        return json
    }

    // MARK: - Folder Path

    static func buildClientRemoteFolder(baseFolder: String, clientName: String) -> String {
        let base = baseFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty
            ? rootFolderName
            : baseFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let safeClientName = sanitizeDriveFolderSegment(clientName)
        let lastSegment = base.split(separator: "/").last.map(String.init) ?? ""
        if lastSegment.caseInsensitiveCompare(safeClientName) == .orderedSame ||
            lastSegment.caseInsensitiveCompare(clientName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
            return base
        }
        return "\(base)/\(safeClientName)"
    }

    private static func sanitizeDriveFolderSegment(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_").isEmpty
            ? "Client" : trimmed.replacingOccurrences(of: "/", with: "_")
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(domain: "TimekeeperGoogleDriveSync", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
