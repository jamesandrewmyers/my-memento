import Foundation

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