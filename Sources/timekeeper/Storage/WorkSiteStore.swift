import Foundation

final class WorkSiteStore {

    private let defaults = UserDefaults.standard

    private static let keyWorkSites = "work_sites"
    private static let defaultSiteName = "Work site"
    private static let minRadiusMeters = 25.0

    func loadSites() -> [WorkSite] {
        guard let json = defaults.string(forKey: Self.keyWorkSites),
              let data = json.data(using: .utf8) else {
            return []
        }

        do {
            return try JSONDecoder().decode([WorkSite].self, from: data)
        } catch {
            print("WorkSiteStore load error:", error)
            return []
        }
    }

    func saveSites(_ sites: [WorkSite]) {
        do {
            let data = try JSONEncoder().encode(sites)
            let json = String(data: data, encoding: .utf8)
            defaults.set(json, forKey: Self.keyWorkSites)
        } catch {
            print("WorkSiteStore save error:", error)
        }
    }

    func sitesForClient(_ clientId: String) -> [WorkSite] {
        loadSites().filter { $0.clientId == clientId }
    }

    @discardableResult
    func addSite(
        clientId: String,
        siteName: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = WorkSite.DEFAULT_RADIUS_METERS
    ) -> WorkSite {
        let site = WorkSite(
            id: UUID().uuidString,
            clientId: clientId,
            siteName: normalizedSiteName(siteName),
            latitude: latitude,
            longitude: longitude,
            radiusMeters: max(radiusMeters, Self.minRadiusMeters)
        )

        saveSites(loadSites() + [site])
        return site
    }

    func upsertSite(_ site: WorkSite) {
        let normalizedSite = WorkSite(
            id: site.id,
            clientId: site.clientId,
            siteName: normalizedSiteName(site.siteName),
            latitude: site.latitude,
            longitude: site.longitude,
            radiusMeters: max(site.radiusMeters, Self.minRadiusMeters)
        )

        let updated = loadSites()
            .filter { $0.id != normalizedSite.id } + [normalizedSite]

        saveSites(updated)
    }

    func deleteSite(siteId: String) {
        saveSites(loadSites().filter { $0.id != siteId })
    }

    func deleteSitesForClient(clientId: String) {
        saveSites(loadSites().filter { $0.clientId != clientId })
    }

    private func normalizedSiteName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultSiteName : trimmed
    }
}
