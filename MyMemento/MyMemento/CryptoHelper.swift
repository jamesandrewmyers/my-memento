import Foundation
import CryptoKit

enum CryptoError: Error {
    case encryptionFailed
    case decryptionFailed
    case invalidData
}

struct CryptoHelper {
    
    /// Encrypts a Codable payload using AES.GCM
    /// - Parameters:
    ///   - payload: The Codable object to encrypt
    ///   - key: The symmetric key for encryption
    /// - Returns: Encrypted data containing both the sealed box and nonce
    /// - Throws: CryptoError if encryption fails
    static func encrypt<T: Codable>(_ payload: T, key: SymmetricKey) throws -> Data {
        do {
            // Encode the payload to JSON data
            let jsonData = try JSONEncoder().encode(payload)
            
            // Encrypt using AES.GCM
            let sealedBox = try AES.GCM.seal(jsonData, using: key)
            
            // Combine nonce and ciphertext for storage
            var combinedData = Data()
            combinedData.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
            combinedData.append(sealedBox.ciphertext)
            combinedData.append(sealedBox.tag)
            
            return combinedData
        } catch {
            throw CryptoError.encryptionFailed
        }
    }
    
    /// Decrypts data back to a Codable payload using AES.GCM
    /// - Parameters:
    ///   - data: The encrypted data containing nonce, ciphertext, and tag
    ///   - key: The symmetric key for decryption
    ///   - type: The expected type to decode to
    /// - Returns: The decrypted and decoded object
    /// - Throws: CryptoError if decryption or decoding fails
    static func decrypt<T: Codable>(_ data: Data, key: SymmetricKey, as type: T.Type) throws -> T {
        guard data.count >= 28 else { // 12 bytes nonce + 16 bytes tag minimum
            throw CryptoError.invalidData
        }
        
        do {
            // Extract components from combined data
            let nonceData = data.prefix(12) // AES.GCM nonce is 12 bytes
            let tagData = data.suffix(16)   // AES.GCM tag is 16 bytes
            let ciphertextData = data.dropFirst(12).dropLast(16)
            
            // Reconstruct the sealed box
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
            
            // Decrypt the data
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            
            // Decode the JSON back to the original type
            let decodedObject = try JSONDecoder().decode(type, from: decryptedData)
            
            return decodedObject
        } catch {
            throw CryptoError.decryptionFailed
        }
    }
}