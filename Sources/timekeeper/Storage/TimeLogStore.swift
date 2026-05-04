import Foundation

final class TimeLogStore: @unchecked Sendable {

    private let persistence = LocalPersistence()

    private(set) var settings: TimeSettings
    private(set) var clients: [ClientProfile]
    private(set) var entries: [TimeEntry]
    private(set) var activeClientId: String?
    private(set) var activeStartMillis: Int64?
    private(set) var lastSyncMillis: Int64?
    private(set) var lastSyncFailed: Bool

    init() {
        let loadedSettings = persistence.loadSettings()
        let loadedEntries = persistence.loadEntries()
        let loadedClients = persistence.loadClients()

        self.settings = loadedSettings
        self.entries = loadedEntries
        self.activeClientId = persistence.loadActiveClientId()
        self.activeStartMillis = persistence.loadActiveStartMillis()
        self.lastSyncMillis = persistence.loadLastSyncMillis()
        self.lastSyncFailed = persistence.loadLastSyncFailed()

        if loadedClients.isEmpty {
            let defaultClientName = "Default Client"
            let defaultClient = ClientProfile(
                id: UUID().uuidString,
                clientName: defaultClientName,
                userName: loadedSettings.userName,
                localFolder: Self.defaultLocalFolderForClient(defaultClientName)
            )
            self.clients = [defaultClient]
            persistence.saveClients(self.clients)
        } else {
            self.clients = loadedClients
        }

        if let activeClientId,
           !clients.contains(where: { $0.id == activeClientId }) {
            self.activeClientId = nil
            self.activeStartMillis = nil
            persistence.clearActiveClientId()
            persistence.clearActiveStartMillis()
        }
    }

    func updateSettings(_ newSettings: TimeSettings) {
        settings = newSettings
        persistence.saveSettings(newSettings)
    }

    func addClient(clientName: String) {
        let trimmed = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let client = ClientProfile(
            id: UUID().uuidString,
            clientName: trimmed,
            userName: settings.userName,
            localFolder: Self.defaultLocalFolderForClient(trimmed)
        )

        clients.append(client)
        persistence.saveClients(clients)
    }


    func updateClient(_ updatedClient: ClientProfile) {
        guard let index = clients.firstIndex(where: { $0.id == updatedClient.id }) else {
            return
        }

        clients[index] = updatedClient
        persistence.saveClients(clients)
    }

    func deleteClient(clientId: String) {
        guard let client = getClientById(clientId) else {
            return
        }

        if activeClientId == clientId {
            cancelActiveTimer()
        }

        _ = deleteAllLocalFilesForClient(client)

        WorkSiteStore().deleteSitesForClient(clientId: clientId)
        clients.removeAll { $0.id == clientId }
        persistence.saveClients(clients)

        if clients.isEmpty {
            let fallbackName = "Default Client"
            let fallback = ClientProfile(
                id: UUID().uuidString,
                clientName: fallbackName,
                userName: settings.userName,
                localFolder: Self.defaultLocalFolderForClient(fallbackName)
            )

            clients.append(fallback)
            persistence.saveClients(clients)
        }
    }

    func getClientById(_ clientId: String?) -> ClientProfile? {
        guard let clientId else { return nil }
        return clients.first { $0.id == clientId }
    }

    func getEntriesForClient(clientId: String) -> [TimeEntry] {
        entries.filter { $0.clientId == clientId }
    }


    @discardableResult
    func updateEntryDescription(
        clientId: String,
        startMillis: Int64,
        stopMillis: Int64,
        description: String
    ) -> Bool {
        guard let index = entries.firstIndex(where: {
            $0.clientId == clientId &&
            $0.startMillis == startMillis &&
            $0.stopMillis == stopMillis
        }) else {
            return false
        }

        let old = entries[index]
        entries[index] = TimeEntry(
            id: old.id,
            clientId: old.clientId,
            startMillis: old.startMillis,
            stopMillis: old.stopMillis,
            description: description,
            durationMinutes: old.durationMinutes
        )

        persistence.saveEntries(entries)
        return true
    }

    func startTimer(clientId: String) {
        let now = currentTimeMillis()
        activeClientId = clientId
        activeStartMillis = now
        persistence.saveActiveClientId(clientId)
        persistence.saveActiveStartMillis(now)
    }

    func stopTimer(description: String) {
        guard let clientId = activeClientId,
              let startMillis = activeStartMillis else {
            return
        }

        let stopMillis = currentTimeMillis()
        let durationMinutes = max((stopMillis - startMillis) / 60000, 1)

        entries.append(
            TimeEntry(
                clientId: clientId,
                startMillis: startMillis,
                stopMillis: stopMillis,
                description: description,
                durationMinutes: durationMinutes
            )
        )

        persistence.saveEntries(entries)

        activeClientId = nil
        activeStartMillis = nil
        persistence.clearActiveClientId()
        persistence.clearActiveStartMillis()
    }

    func cancelActiveTimer() {
        activeClientId = nil
        activeStartMillis = nil
        persistence.clearActiveClientId()
        persistence.clearActiveStartMillis()
    }


    func markSyncSuccess(syncMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        lastSyncMillis = syncMillis
        lastSyncFailed = false
        persistence.saveLastSyncSuccess(syncMillis)
    }

    func markSyncFailed() {
        lastSyncFailed = true
        persistence.saveLastSyncFailure()
    }



    func loadDriveMappings() -> [DriveFileMapping] {
        persistence.loadDriveMappings()
    }

    func saveDriveMappings(_ mappings: [DriveFileMapping]) {
        persistence.saveDriveMappings(mappings)
    }

    func getLocalFilesForClient(clientId: String) -> [URL] {
        guard let client = getClientById(clientId) else { return [] }
        return getLocalFilesForClient(client)
    }

    @discardableResult
    func deleteAllLocalFilesForClient(clientId: String) -> Int {
        guard let client = getClientById(clientId) else { return 0 }
        return deleteAllLocalFilesForClient(client)
    }

    func deleteLocalFileForClient(clientId: String, fileName: String) -> Bool {
        guard let client = getClientById(clientId) else { return false }
        let folder = clientFolderURL(for: client)
        let fileURL = folder.appendingPathComponent(fileName)
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }

    func deleteEntriesForClient(clientId: String) {
        entries.removeAll { $0.clientId == clientId }
        persistence.saveEntries(entries)
    }

    private func deleteAllLocalFilesForClient(_ client: ClientProfile) -> Int {
        let files = getLocalFilesForClient(client)
        var deletedCount = 0

        for file in files {
            do {
                try FileManager.default.removeItem(at: file)
                deletedCount += 1
            } catch {
                continue
            }
        }

        return deletedCount
    }

    private func getLocalFilesForClient(_ client: ClientProfile) -> [URL] {
        let safeClientName = Self.sanitizeFileName(client.clientName)
        let folder = clientFolderURL(for: client)

        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        )) ?? []

        return files
            .filter {
                $0.lastPathComponent.hasPrefix("timelog_\(safeClientName)_") &&
                $0.lastPathComponent.hasSuffix(".csv")
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func clientFolderURL(for client: ClientProfile) -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = client.localFolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultLocalFolderForClient(client.clientName)
            : client.localFolder

        return documents.appendingPathComponent(folder, isDirectory: true)
    }

    private static func defaultLocalFolderForClient(_ clientName: String) -> String {
        "defaultfolder/\(sanitizeFileName(clientName))"
    }

    private static func sanitizeFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed.replacingOccurrences(
            of: "[^A-Za-z0-9._-]+",
            with: "_",
            options: .regularExpression
        )
        let cleaned = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return cleaned.isEmpty ? "client" : cleaned
    }

    private func currentTimeMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
