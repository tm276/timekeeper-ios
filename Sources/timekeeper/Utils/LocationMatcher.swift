import Foundation

enum LocationMatcher {

    struct Match {
        let workSite: WorkSite
        let distanceMeters: Double
    }

    /// Returns the closest work site that contains the given location.
    static func findCurrentSite(
        latitude: Double,
        longitude: Double,
        workSites: [WorkSite]
    ) -> Match? {
        workSites
            .map { site in
                Match(
                    workSite: site,
                    distanceMeters: distanceMeters(
                        fromLatitude: latitude,
                        fromLongitude: longitude,
                        toLatitude: site.latitude,
                        toLongitude: site.longitude
                    )
                )
            }
            .filter { $0.distanceMeters <= $0.workSite.radiusMeters }
            .min { $0.distanceMeters < $1.distanceMeters }
    }

    /// Returns all work sites containing the given location, closest first.
    static func findCurrentSites(
        latitude: Double,
        longitude: Double,
        workSites: [WorkSite]
    ) -> [Match] {
        workSites
            .map { site in
                Match(
                    workSite: site,
                    distanceMeters: distanceMeters(
                        fromLatitude: latitude,
                        fromLongitude: longitude,
                        toLatitude: site.latitude,
                        toLongitude: site.longitude
                    )
                )
            }
            .filter { $0.distanceMeters <= $0.workSite.radiusMeters }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    static func isInsideSite(
        latitude: Double,
        longitude: Double,
        workSite: WorkSite
    ) -> Bool {
        distanceMeters(
            fromLatitude: latitude,
            fromLongitude: longitude,
            toLatitude: workSite.latitude,
            toLongitude: workSite.longitude
        ) <= workSite.radiusMeters
    }

    /// Haversine distance between two coordinates in meters.
    static func distanceMeters(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ) -> Double {
        let earthRadius = 6_371_000.0
        let fromLat = fromLatitude * .pi / 180
        let toLat = toLatitude * .pi / 180
        let deltaLat = (toLatitude - fromLatitude) * .pi / 180
        let deltaLon = (toLongitude - fromLongitude) * .pi / 180

        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(fromLat) * cos(toLat) *
                sin(deltaLon / 2) * sin(deltaLon / 2)

        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}
