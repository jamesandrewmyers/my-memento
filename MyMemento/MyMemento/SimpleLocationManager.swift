import Foundation
import CoreLocation

class SimpleLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var currentLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
    }
    
    func requestLocationPermission() {
        print("DEBUG: SimpleLocationManager - Current authorization status: \(authorizationStatus.rawValue)")
        print("DEBUG: SimpleLocationManager - Accuracy authorization: \(locationManager.accuracyAuthorization.rawValue)")
        
        switch authorizationStatus {
        case .notDetermined:
            print("DEBUG: SimpleLocationManager - Requesting when in use authorization")
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            print("DEBUG: SimpleLocationManager - Permission denied/restricted")
            // Permission denied - could show alert to go to settings
            break
        case .authorizedWhenInUse, .authorizedAlways:
            print("DEBUG: SimpleLocationManager - Already authorized, requesting location")
            // Check if we have limited accuracy and request full accuracy
            if locationManager.accuracyAuthorization == .reducedAccuracy {
                print("DEBUG: SimpleLocationManager - Has reduced accuracy, requesting full accuracy")
                locationManager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "location-search")
            }
            locationManager.requestLocation()
        @unknown default:
            print("DEBUG: SimpleLocationManager - Unknown authorization status")
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        authorizationStatus = status
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }
    }
}