import Foundation

@objc(AttributedStringTransformer)
class AttributedStringTransformer: NSSecureUnarchiveFromDataTransformer {
    
    override class var allowedTopLevelClasses: [AnyClass] {
        return [NSAttributedString.self, NSMutableAttributedString.self]
    }
    
    static let transformerName = NSValueTransformerName(rawValue: "AttributedStringTransformer")
    
    static func register() {
        let transformer = AttributedStringTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: transformerName)
    }
}