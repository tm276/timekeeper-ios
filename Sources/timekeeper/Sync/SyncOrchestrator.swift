import Foundation

enum SyncOrchestrator {

    static func availableServices(for client: ClientProfile?) -> [SyncService] {
        guard let client else {
            return []
        }

        var services: [SyncService] = []

        if !client.googleDriveAccount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            services.append(.googleDrive)
        }

        if !client.nextcloudUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !client.nextcloudUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !client.nextcloudPassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            services.append(.nextcloud)
        }

        return services
    }

    static func sync(store: TimeLogStore) -> Result<String, Error> {
        guard let client = store.getClientById(store.activeClientId) ?? store.clients.first else {
            store.markSyncFailed()
            return .failure(makeError("No client is available to sync."))
        }

        do {
            let entries = store.getEntriesForClient(clientId: client.id)

            let localUrls = try CsvShareUtils.writeWindowedCSVs(
                entries: entries,
                client: client,
                settings: store.settings
            )

            let available = availableServices(for: client)

            if available.isEmpty {
                store.markSyncSuccess()
                return .success("Local CSV sync complete. Wrote \(localUrls.count) file(s).")
            }

            var messages: [String] = []
            var failedError: Error?

            if available.contains(.googleDrive) {
                let result = GoogleDriveSyncManager.syncCurrentWindow(
                    store: store,
                    client: client
                )

                switch result {
                case .success(let remoteId):
                    messages.append("Google Drive synced: \(remoteId)")
                case .failure(let error):
                    failedError = error
                    messages.append(error.localizedDescription)
                }
            }

            if available.contains(.nextcloud) {
                let settings = NextcloudSettings(
                    serverUrl: client.nextcloudUrl,
                    username: client.nextcloudUser,
                    appPassword: client.nextcloudPassword,
                    remoteFolder: client.nextcloudFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "TimeKeeper"
                        : client.nextcloudFolder
                )

                let result = NextcloudSyncManager.syncCurrentWindow(
                    store: store,
                    clientProfile: client,
                    settings: settings
                )

                switch result {
                case .success:
                    messages.append("Nextcloud synced.")
                case .failure(let error):
                    failedError = error
                    messages.append(error.localizedDescription)
                }
            }

            if let failedError {
                store.markSyncFailed()
                let combined = messages.joined(separator: "\n")
                return .failure(makeError(combined.isEmpty ? failedError.localizedDescription : combined))
            }

            store.markSyncSuccess()
            return .success(messages.isEmpty ? "Sync complete." : messages.joined(separator: "\n"))
        } catch {
            store.markSyncFailed()
            return .failure(error)
        }
    }

    private static func makeError(_ message: String) -> NSError {
        NSError(
            domain: "TimekeeperSync",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
