import Foundation
import CoreLocation
import MapKit

// MARK: - NSAttributedString Codable Wrapper
struct NSAttributedStringWrapper: Codable {
    let attributedString: NSAttributedString
    
    init(_ attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }
    
    enum CodingKeys: String, CodingKey {
        case htmlData
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Convert to HTML data for safe encoding
        let htmlData = try attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
            ]
        )
        try container.encode(htmlData, forKey: .htmlData)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let htmlData = try container.decode(Data.self, forKey: .htmlData)
        
        // Convert HTML data back to NSAttributedString
        let attributedString = try NSAttributedString(
            data: htmlData,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        )
        
        self.attributedString = attributedString
    }
}

// MARK: - Encrypted Storage Payloads
struct NotePayload: Codable {
    var title: String
    var body: NSAttributedStringWrapper
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var pinned: Bool
}

struct IndexPayload: Codable, Hashable {
    var id: UUID
    var title: String
    var tags: [String]
    var summary: String
    var createdAt: Date
    var updatedAt: Date
    var pinned: Bool
}

// MARK: - Location Storage Payloads
struct LocationPlacemarkPayload: Codable {
    var thoroughfare: String?
    var subThoroughfare: String?
    var locality: String?
    var subLocality: String?
    var administrativeArea: String?
    var subAdministrativeArea: String?
    var postalCode: String?
    var country: String?
    var countryCode: String?
    var timeZone: String?
    
    init(thoroughfare: String? = nil, subThoroughfare: String? = nil, locality: String? = nil, subLocality: String? = nil, administrativeArea: String? = nil, subAdministrativeArea: String? = nil, postalCode: String? = nil, country: String? = nil, countryCode: String? = nil, timeZone: String? = nil) {
        self.thoroughfare = thoroughfare
        self.subThoroughfare = subThoroughfare
        self.locality = locality
        self.subLocality = subLocality
        self.administrativeArea = administrativeArea
        self.subAdministrativeArea = subAdministrativeArea
        self.postalCode = postalCode
        self.country = country
        self.countryCode = countryCode
        self.timeZone = timeZone
    }
    
    init(from placemark: MKPlacemark) {
        self.thoroughfare = placemark.thoroughfare
        self.subThoroughfare = placemark.subThoroughfare
        self.locality = placemark.locality
        self.subLocality = placemark.subLocality
        self.administrativeArea = placemark.administrativeArea
        self.subAdministrativeArea = placemark.subAdministrativeArea
        self.postalCode = placemark.postalCode
        self.country = placemark.country
        self.countryCode = placemark.countryCode
        self.timeZone = placemark.timeZone?.identifier
    }
    
    init(from placemark: CLPlacemark) {
        self.thoroughfare = placemark.thoroughfare
        self.subThoroughfare = placemark.subThoroughfare
        self.locality = placemark.locality
        self.subLocality = placemark.subLocality
        self.administrativeArea = placemark.administrativeArea
        self.subAdministrativeArea = placemark.subAdministrativeArea
        self.postalCode = placemark.postalCode
        self.country = placemark.country
        self.countryCode = placemark.isoCountryCode
        self.timeZone = placemark.timeZone?.identifier
    }
}