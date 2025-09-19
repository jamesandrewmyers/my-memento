import Foundation
import CoreData
import CoreLocation
import MapKit
import CryptoKit

class LocationManager: ObservableObject {
    private let viewContext: NSManagedObjectContext
    private let keyManager: KeyManager
    
    init(context: NSManagedObjectContext, keyManager: KeyManager) {
        self.viewContext = context
        self.keyManager = keyManager
    }
    
    // MARK: - Location Storage
    
    /// Saves a location with encrypted placemark data
    /// - Parameters:
    ///   - name: Unique text name for the location
    ///   - coordinate: CLLocationCoordinate2D containing latitude and longitude
    ///   - placemark: Optional MKPlacemark or CLPlacemark for address information
    ///   - altitude: Optional altitude value
    ///   - horizontalAccuracy: Optional horizontal accuracy
    ///   - verticalAccuracy: Optional vertical accuracy
    /// - Returns: The created Location entity
    /// - Throws: Error if saving fails
    @discardableResult
    func saveLocation(
        name: String,
        coordinate: CLLocationCoordinate2D,
        placemark: Any? = nil,
        altitude: Double? = nil,
        horizontalAccuracy: Double? = nil,
        verticalAccuracy: Double? = nil
    ) throws -> Location {
        let location = Location(context: viewContext)
        location.id = UUID()
        location.name = name
        location.latitude = coordinate.latitude
        location.longitude = coordinate.longitude
        location.createdAt = Date()
        
        if let altitude = altitude {
            location.altitude = altitude
        }
        if let horizontalAccuracy = horizontalAccuracy {
            location.horizontalAccuracy = horizontalAccuracy
        }
        if let verticalAccuracy = verticalAccuracy {
            location.verticalAccuracy = verticalAccuracy
        }
        
        // Encrypt placemark data if provided
        if let placemark = placemark {
            let placemarkPayload: LocationPlacemarkPayload
            
            if let mkPlacemark = placemark as? MKPlacemark {
                placemarkPayload = LocationPlacemarkPayload(from: mkPlacemark)
            } else if let clPlacemark = placemark as? CLPlacemark {
                placemarkPayload = LocationPlacemarkPayload(from: clPlacemark)
            } else {
                throw LocationError.invalidPlacemarkType
            }
            
            let key = try keyManager.getEncryptionKey()
            let encryptedData = try CryptoHelper.encrypt(placemarkPayload, key: key)
            location.encryptedPlacemarkData = encryptedData
        }
        
        try viewContext.save()
        return location
    }
    
    /// Convenience method to save a location from CLLocation
    /// - Parameters:
    ///   - name: Unique text name for the location
    ///   - clLocation: CLLocation object
    ///   - placemark: Optional placemark data
    /// - Returns: The created Location entity
    /// - Throws: Error if saving fails
    @discardableResult
    func saveLocation(
        name: String,
        from clLocation: CLLocation,
        placemark: Any? = nil
    ) throws -> Location {
        return try saveLocation(
            name: name,
            coordinate: clLocation.coordinate,
            placemark: placemark,
            altitude: clLocation.altitude,
            horizontalAccuracy: clLocation.horizontalAccuracy,
            verticalAccuracy: clLocation.verticalAccuracy
        )
    }
    
    // MARK: - Location Retrieval
    
    /// Fetches all locations from Core Data
    /// - Returns: Array of Location entities
    /// - Throws: Error if fetch fails
    func fetchAllLocations() throws -> [Location] {
        let request: NSFetchRequest<Location> = Location.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Location.createdAt, ascending: false)]
        return try viewContext.fetch(request)
    }
    
    /// Fetches a location by ID
    /// - Parameter id: UUID of the location
    /// - Returns: Location entity if found, nil otherwise
    /// - Throws: Error if fetch fails
    func fetchLocation(by id: UUID) throws -> Location? {
        let request: NSFetchRequest<Location> = Location.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try viewContext.fetch(request).first
    }
    
    /// Fetches a location by name
    /// - Parameter name: Name of the location
    /// - Returns: Location entity if found, nil otherwise
    /// - Throws: Error if fetch fails
    func fetchLocation(by name: String) throws -> Location? {
        let request: NSFetchRequest<Location> = Location.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", name)
        request.fetchLimit = 1
        return try viewContext.fetch(request).first
    }
    
    /// Searches for locations by name (case-insensitive partial match)
    /// - Parameter searchText: Text to search for in location names
    /// - Returns: Array of matching Location entities
    /// - Throws: Error if fetch fails
    func searchLocations(by searchText: String) throws -> [Location] {
        let request: NSFetchRequest<Location> = Location.fetchRequest()
        request.predicate = NSPredicate(format: "name CONTAINS[cd] %@", searchText)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Location.name, ascending: true)]
        return try viewContext.fetch(request)
    }
    
    // MARK: - Location Updates
    
    /// Updates a location's name
    /// - Parameters:
    ///   - location: Location entity to update
    ///   - newName: New name for the location
    /// - Throws: Error if saving fails
    func updateLocationName(_ location: Location, to newName: String) throws {
        location.name = newName
        try viewContext.save()
    }
    
    /// Updates a location's coordinates
    /// - Parameters:
    ///   - location: Location entity to update
    ///   - coordinate: New coordinate
    /// - Throws: Error if saving fails
    func updateLocationCoordinate(_ location: Location, to coordinate: CLLocationCoordinate2D) throws {
        location.latitude = coordinate.latitude
        location.longitude = coordinate.longitude
        try viewContext.save()
    }
    
    // MARK: - Location Deletion
    
    /// Deletes a location
    /// - Parameter location: Location entity to delete
    /// - Throws: Error if deletion fails
    func deleteLocation(_ location: Location) throws {
        viewContext.delete(location)
        try viewContext.save()
    }
    
    /// Deletes multiple locations
    /// - Parameter locations: Array of Location entities to delete
    /// - Throws: Error if deletion fails
    func deleteLocations(_ locations: [Location]) throws {
        for location in locations {
            viewContext.delete(location)
        }
        try viewContext.save()
    }
    
    // MARK: - Placemark Decryption
    
    /// Decrypts placemark data from a location
    /// - Parameter location: Location entity with encrypted placemark data
    /// - Returns: LocationPlacemarkPayload if decryption succeeds, nil otherwise
    /// - Throws: Error if decryption fails
    func decryptPlacemark(from location: Location) throws -> LocationPlacemarkPayload? {
        guard let encryptedData = location.encryptedPlacemarkData else {
            return nil
        }
        
        let key = try keyManager.getEncryptionKey()
        return try CryptoHelper.decrypt(encryptedData, key: key, as: LocationPlacemarkPayload.self)
    }
    
    // MARK: - Utility Methods
    
    /// Creates a CLLocation object from a stored Location entity
    /// - Parameter location: Location entity from Core Data
    /// - Returns: CLLocation object
    func createCLLocation(from location: Location) -> CLLocation {
        let coordinate = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        
        return CLLocation(
            coordinate: coordinate,
            altitude: location.altitude,
            horizontalAccuracy: location.horizontalAccuracy,
            verticalAccuracy: location.verticalAccuracy,
            timestamp: location.createdAt ?? Date()
        )
    }
    
    /// Creates a formatted address string from encrypted placemark data
    /// - Parameter location: Location entity with encrypted placemark data
    /// - Returns: Formatted address string, or coordinate string if no placemark data
    /// - Throws: Error if decryption fails
    func formatAddress(from location: Location) throws -> String {
        guard let placemark = try decryptPlacemark(from: location) else {
            return String(format: "%.6f, %.6f", location.latitude, location.longitude)
        }
        
        var components: [String] = []
        
        if let number = placemark.subThoroughfare, let street = placemark.thoroughfare {
            components.append("\(number) \(street)")
        } else if let street = placemark.thoroughfare {
            components.append(street)
        }
        
        if let city = placemark.locality {
            components.append(city)
        }
        
        if let state = placemark.administrativeArea {
            components.append(state)
        }
        
        if let zip = placemark.postalCode {
            components.append(zip)
        }
        
        if let country = placemark.country {
            components.append(country)
        }
        
        return components.isEmpty ? String(format: "%.6f, %.6f", location.latitude, location.longitude) : components.joined(separator: ", ")
    }
}

// MARK: - Location Errors
enum LocationError: Error, LocalizedError {
    case invalidPlacemarkType
    case locationNotFound
    case duplicateLocationName
    case encryptionFailed
    case decryptionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidPlacemarkType:
            return "Invalid placemark type. Expected MKPlacemark or CLPlacemark."
        case .locationNotFound:
            return "Location not found."
        case .duplicateLocationName:
            return "A location with this name already exists."
        case .encryptionFailed:
            return "Failed to encrypt location data."
        case .decryptionFailed:
            return "Failed to decrypt location data."
        }
    }
}