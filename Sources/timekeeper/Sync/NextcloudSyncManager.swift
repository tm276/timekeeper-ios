import Foundation


private final class LockedHTTPResult: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()

    private var storedStatusCode: Int?
    private var storedError: Error?

    func set(statusCode: Int?, error: Error?) {
        lock.lock()
        storedStatusCode = statusCode
        storedError = error
        lock.unlock()
        semaphore.signal()
    }

    func wait() -> (statusCode: Int?, error: Error?) {
        semaphore.wait()
        lock.lock()
        let result = (storedStatusCode, storedError)
        lock.unlock()
        return result
    }
}

enum NextcloudSyncManager {

    static func syncCurrentWindow(
        store: TimeLogStore,
        clientProfile: ClientProfile,
        settings: NextcloudSettings
    ) -> Result<Void, Error> {
        guard !settings.serverUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !settings.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !settings.appPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(makeError("Nextcloud settings are incomplete."))
        }

        do {
            let entries = store.getEntriesForClient(clientId: clientProfile.id)

            let urls = try CsvShareUtils.writeWindowedCSVs(
                entries: entries,
                client: clientProfile,
                settings: store.settings
            )

            guard let fileURL = urls.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else {
                return .failure(makeError("No CSV file was generated for Nextcloud upload."))
            }

            let trimmedServer = settings.serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let encodedUsername = encodeDavSegment(settings.username)
            let remoteFolder = buildClientRemoteFolder(
                baseFolder: settings.remoteFolder,
                clientName: clientProfile.clientName
            )
            let auth = basicAuth(username: settings.username, password: settings.appPassword)

            try ensureRemoteFolderExists(
                serverUrl: trimmedServer,
                encodedUsername: encodedUsername,
                remoteFolder: remoteFolder,
                auth: auth
            )

            let remoteFolderPath = encodeRemotePath(remoteFolder)
            let encodedFileName = encodeDavSegment(fileURL.lastPathComponent)

            let remoteFileURL = "\(trimmedServer)/remote.php/dav/files/\(encodedUsername)/\(remoteFolderPath)/\(encodedFileName)"

            try uploadFile(
                fileURL: fileURL,
                remoteFileURL: remoteFileURL,
                auth: auth
            )

            return .success(())
        } catch {
            return .failure(error)
        }
    }

    static func buildClientRemoteFolder(baseFolder: String, clientName: String) -> String {
        let base = trimSlashes(baseFolder).isEmpty ? "TimeKeeper" : trimSlashes(baseFolder)
        let safeClientName = sanitizeRemoteSegment(clientName)
        let lastSegment = base.split(separator: "/").last.map(String.init) ?? ""

        if lastSegment.caseInsensitiveCompare(safeClientName) == .orderedSame ||
            lastSegment.caseInsensitiveCompare(clientName.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
            return base
        }

        return "\(base)/\(safeClientName)"
    }

    static func encodeRemotePath(_ path: String) -> String {
        path
            .split(separator: "/")
            .filter { !$0.isEmpty }
            .map { encodeDavSegment(String($0)) }
            .joined(separator: "/")
    }

    static func encodeDavSegment(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func ensureRemoteFolderExists(
        serverUrl: String,
        encodedUsername: String,
        remoteFolder: String,
        auth: String
    ) throws {
        let segments = remoteFolder
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }

        var currentPath = ""

        for segment in segments {
            currentPath = currentPath.isEmpty ? segment : "\(currentPath)/\(segment)"
            let encodedPath = encodeRemotePath(currentPath)
            let urlString = "\(serverUrl)/remote.php/dav/files/\(encodedUsername)/\(encodedPath)"

            try performRequest(
                urlString: urlString,
                method: "MKCOL",
                auth: auth,
                body: nil,
                contentType: nil,
                acceptedStatusCodes: Set(Array(200...299) + [301, 405])
            )
        }
    }

    private static func uploadFile(
        fileURL: URL,
        remoteFileURL: String,
        auth: String
    ) throws {
        let data = try Data(contentsOf: fileURL)

        try performRequest(
            urlString: remoteFileURL,
            method: "PUT",
            auth: auth,
            body: data,
            contentType: "text/csv",
            acceptedStatusCodes: Set(Array(200...299) + [201, 204])
        )
    }

    private static func performRequest(
        urlString: String,
        method: String,
        auth: String,
        body: Data?,
        contentType: String?,
        acceptedStatusCodes: Set<Int>
    ) throws {
        guard let url = URL(string: urlString) else {
            throw makeError("Invalid Nextcloud URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(auth, forHTTPHeaderField: "Authorization")

        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        request.httpBody = body

        let result = LockedHTTPResult()

        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            result.set(
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                error: error
            )
        }

        task.resume()

        let response = result.wait()

        if let error = response.error {
            throw error
        }

        guard let code = response.statusCode else {
            throw makeError("Nextcloud did not return an HTTP response.")
        }

        guard acceptedStatusCodes.contains(code) else {
            throw makeError("Nextcloud \(method) failed with HTTP \(code).")
        }
    }

    private static func basicAuth(username: String, password: String) -> String {
        let raw = "\(username):\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    private static func sanitizeRemoteSegment(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let sanitized = trimmed
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")

        return sanitized.isEmpty ? "Client" : sanitized
    }

    private static func trimSlashes(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(
            domain: "TimekeeperNextcloudSync",
            code: 501,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
