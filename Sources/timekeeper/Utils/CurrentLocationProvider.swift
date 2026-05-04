import Foundation
import CoreLocation

final class CurrentLocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func getCurrentLocation() async -> CLLocation? {
        // Request permission if needed and wait for it
        let status = manager.authorizationStatus
        if status == .notDetermined {
            await MainActor.run { self.manager.requestWhenInUseAuthorization() }
            // Poll until status changes
            var waited = 0
            while manager.authorizationStatus == .notDetermined && waited < 30 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                waited += 1
            }
        }

        let resolved = manager.authorizationStatus
        print("[Location] Final auth status: \(resolved.rawValue)")
        guard resolved == .authorizedWhenInUse || resolved == .authorizedAlways else {
            print("[Location] Not authorized")
            return nil
        }

        // Request location with 15 second timeout
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async {
                        self.locationContinuation = continuation
                        self.manager.requestLocation()
                        print("[Location] requestLocation called")
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                print("[Location] Timed out")
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("[Location] Got location: \(locations.last?.coordinate ?? CLLocationCoordinate2D())")
        locationContinuation?.resume(returning: locations.last)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Location] Failed: \(error.localizedDescription)")
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("[Location] Auth changed to: \(manager.authorizationStatus.rawValue)")
    }
}
