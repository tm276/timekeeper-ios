import Foundation

struct WorkSite: Codable, Identifiable {
    let id: String
    let clientId: String
    let siteName: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double

    static let DEFAULT_RADIUS_METERS: Double = 100.0

    init(
        id: String,
        clientId: String,
        siteName: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = WorkSite.DEFAULT_RADIUS_METERS
    ) {
        self.id = id
        self.clientId = clientId
        self.siteName = siteName
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
    }
}
