import Foundation

final class LocalPersistence {

    private let defaults = UserDefaults.standard

    private let settingsKey = "settings"
    private let clientsKey = "clients"
    private let entriesKey = "entries"
    private let driveMappingsKey = "drive_mappings"
    private let activeClientIdKey = "activeClientId"
    private let activeStartMillisKey = "activeStartMillis"
    private let lastSyncMillisKey = "lastSyncMillis"
    private let lastSyncFailedKey = "lastSyncFailed"

    func saveSettings(_ settings: TimeSettings) {
        saveJSON(settings, key: settingsKey)
    }

    func loadSettings() -> TimeSettings {
        loadJSON(TimeSettings.self, key: settingsKey) ?? TimeSettings.default()
    }

    func saveClients(_ clients: [ClientProfile]) {
        saveJSON(clients, key: clientsKey)
    }

    func loadClients() -> [ClientProfile] {
        loadJSON([ClientProfile].self, key: clientsKey) ?? []
    }

    func saveEntries(_ entries: [TimeEntry]) {
        saveJSON(entries, key: entriesKey)
    }

    func loadEntries() -> [TimeEntry] {
        loadJSON([TimeEntry].self, key: entriesKey) ?? []
    }

    func saveDriveMappings(_ mappings: [DriveFileMapping]) {
        saveJSON(mappings, key: driveMappingsKey)
    }

    func loadDriveMappings() -> [DriveFileMapping] {
        loadJSON([DriveFileMapping].self, key: driveMappingsKey) ?? []
    }

    func saveActiveClientId(_ clientId: String?) {
        defaults.set(clientId, forKey: activeClientIdKey)
    }

    func loadActiveClientId() -> String? {
        defaults.string(forKey: activeClientIdKey)
    }

    func clearActiveClientId() {
        defaults.removeObject(forKey: activeClientIdKey)
    }

    func saveActiveStartMillis(_ startMillis: Int64?) {
        if let startMillis {
            defaults.set(startMillis, forKey: activeStartMillisKey)
        } else {
            defaults.removeObject(forKey: activeStartMillisKey)
        }
    }

    func loadActiveStartMillis() -> Int64? {
        if defaults.object(forKey: activeStartMillisKey) == nil {
            return nil
        }
        return Int64(defaults.integer(forKey: activeStartMillisKey))
    }

    func clearActiveStartMillis() {
        defaults.removeObject(forKey: activeStartMillisKey)
    }

    func saveLastSyncSuccess(_ syncMillis: Int64) {
        defaults.set(syncMillis, forKey: lastSyncMillisKey)
        defaults.set(false, forKey: lastSyncFailedKey)
    }

    func saveLastSyncFailure() {
        defaults.set(true, forKey: lastSyncFailedKey)
    }

    func loadLastSyncMillis() -> Int64? {
        if defaults.object(forKey: lastSyncMillisKey) == nil {
            return nil
        }
        return Int64(defaults.integer(forKey: lastSyncMillisKey))
    }

    func loadLastSyncFailed() -> Bool {
        defaults.bool(forKey: lastSyncFailedKey)
    }

    private func saveJSON<T: Encodable>(_ value: T, key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            let json = String(data: data, encoding: .utf8)
            defaults.set(json, forKey: key)
        } catch {
            print("LocalPersistence save error for \(key): \(error)")
        }
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let json = defaults.string(forKey: key),
              let data = json.data(using: .utf8) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("LocalPersistence load error for \(key): \(error)")
            return nil
        }
    }
}
