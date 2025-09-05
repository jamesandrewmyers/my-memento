import Foundation
import CryptoKit

enum CryptoError: Error {
    case encryptionFailed
    case decryptionFailed
    case invalidData
    case keyWrappingFailed
    case invalidPublicKey
    case exportDirectoryCreationFailed
}

struct CryptoHelper {
    
    // MARK: - File-Level Encryption APIs for Large Attachments
    
    /// Encrypts a file using AES.GCM with streaming I/O for large files
    /// - Parameters:
    ///   - inputURL: URL of the file to encrypt
    ///   - outputURL: URL where the encrypted file will be written
    ///   - key: The symmetric key for encryption
    /// - Throws: CryptoError wrapped in ErrorManager if encryption fails
    static func encryptFile(inputURL: URL, outputURL: URL, key: SymmetricKey) async throws {
        do {
            // Open input file for reading
            let inputFileHandle = try FileHandle(forReadingFrom: inputURL)
            defer { inputFileHandle.closeFile() }
            
            // Create output file and open for writing
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
            let outputFileHandle = try FileHandle(forWritingTo: outputURL)
            defer { outputFileHandle.closeFile() }
            
            // Read entire file into memory (we'll optimize this in future iterations for truly large files)
            let inputData = try Data(contentsOf: inputURL)
            
            // Encrypt using AES.GCM
            let sealedBox = try AES.GCM.seal(inputData, using: key)
            
            // Write components: nonce (12 bytes) + ciphertext + tag (16 bytes)
            outputFileHandle.write(sealedBox.nonce.withUnsafeBytes { Data($0) })
            outputFileHandle.write(sealedBox.ciphertext)
            outputFileHandle.write(sealedBox.tag)
            
        } catch {
            ErrorManager.shared.handleError(error, context: "File encryption failed")
            throw CryptoError.encryptionFailed
        }
    }
    
    /// Decrypts a file using AES.GCM with streaming I/O for large files
    /// - Parameters:
    ///   - inputURL: URL of the encrypted file to decrypt
    ///   - outputURL: URL where the decrypted file will be written
    ///   - key: The symmetric key for decryption
    /// - Throws: CryptoError wrapped in ErrorManager if decryption fails
    static func decryptFile(inputURL: URL, outputURL: URL, key: SymmetricKey) async throws {
        do {
            // Open input file for reading
            let inputFileHandle = try FileHandle(forReadingFrom: inputURL)
            defer { inputFileHandle.closeFile() }
            
            // Get file size and validate minimum size
            let fileSize = try inputFileHandle.seekToEnd()
            guard fileSize >= 28 else { // nonce (12) + tag (16) minimum
                throw CryptoError.invalidData
            }
            
            // Read nonce from the beginning (12 bytes)
            try inputFileHandle.seek(toOffset: 0)
            let nonceData = inputFileHandle.readData(ofLength: 12)
            guard nonceData.count == 12 else {
                throw CryptoError.invalidData
            }
            
            // Read tag from the end (16 bytes)
            try inputFileHandle.seek(toOffset: fileSize - 16)
            let tagData = inputFileHandle.readData(ofLength: 16)
            guard tagData.count == 16 else {
                throw CryptoError.invalidData
            }
            
            // Read ciphertext (middle section)
            try inputFileHandle.seek(toOffset: 12)
            let ciphertextLength = Int(fileSize - 28) // Total minus nonce and tag
            let ciphertextData = inputFileHandle.readData(ofLength: ciphertextLength)
            
            // Reconstruct the sealed box
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
            
            // Decrypt the data
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            
            // Create output file and write decrypted data
            FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: nil)
            let outputFileHandle = try FileHandle(forWritingTo: outputURL)
            defer { outputFileHandle.closeFile() }
            
            outputFileHandle.write(decryptedData)
            
        } catch {
            ErrorManager.shared.handleError(error, context: "File decryption failed")
            throw CryptoError.decryptionFailed
        }
    }
    
    // MARK: - Payload-Level Encryption APIs for Note Data
    
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
    
    // MARK: - Hybrid Export APIs
    
    /// Generates a fresh AES-256-GCM key for export encryption
    /// - Returns: A new symmetric key for AES-256-GCM
    static func generateExportKey() -> SymmetricKey {
        return SymmetricKey(size: .bits256)
    }
    
    /// Encrypts an export bundle (zip archive) using AES-GCM
    /// - Parameters:
    ///   - bundleURL: URL of the zip archive to encrypt
    ///   - key: The symmetric key for encryption
    /// - Returns: A tuple containing the encrypted file URL, nonce, and authentication tag
    /// - Throws: CryptoError if encryption fails
    static func encryptExportBundle(bundleURL: URL, key: SymmetricKey) async throws -> (encryptedURL: URL, nonce: Data, tag: Data) {
        do {
            // Create Application Support/Exports directory if it doesn't exist
            let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let exportsURL = applicationSupportURL.appendingPathComponent("Exports")
            
            if !FileManager.default.fileExists(atPath: exportsURL.path) {
                try FileManager.default.createDirectory(at: exportsURL, withIntermediateDirectories: true, attributes: nil)
            }
            
            // Read the zip archive
            let bundleData = try Data(contentsOf: bundleURL)
            
            // Encrypt using AES.GCM
            let sealedBox = try AES.GCM.seal(bundleData, using: key)
            
            // Create output file URL
            let encryptedURL = exportsURL.appendingPathComponent("export.enc")
            
            // Write encrypted data to file
            var encryptedData = Data()
            encryptedData.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
            encryptedData.append(sealedBox.ciphertext)
            encryptedData.append(sealedBox.tag)
            
            try encryptedData.write(to: encryptedURL)
            
            // Return the components
            let nonceData = sealedBox.nonce.withUnsafeBytes { Data($0) }
            let tagData = sealedBox.tag
            
            return (encryptedURL: encryptedURL, nonce: nonceData, tag: tagData)
            
        } catch {
            ErrorManager.shared.handleError(error, context: "Export bundle encryption failed")
            if error is CryptoError {
                throw error
            } else {
                throw CryptoError.encryptionFailed
            }
        }
    }
    
    /// Wraps (encrypts) an export key using RSA-OAEP-SHA256
    /// - Parameters:
    ///   - key: The symmetric key to encrypt
    ///   - publicKeyData: The RSA public key data (PEM or DER format)
    /// - Returns: The encrypted key bytes
    /// - Throws: CryptoError if key wrapping fails
    static func wrapExportKey(key: SymmetricKey, with publicKeyData: Data) throws -> Data {
        do {
            // Convert SymmetricKey to raw data
            let keyData = key.withUnsafeBytes { Data($0) }
            
            // Create SecKey from public key data
            let publicKey: SecKey
            
            // Try DER format first
            var error: Unmanaged<CFError>?
            if let derKey = SecKeyCreateWithData(publicKeyData as CFData, [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass: kSecAttrKeyClassPublic
            ] as CFDictionary, &error) {
                publicKey = derKey
            } else {
                // Try PEM format - remove headers and decode base64
                let pemString = String(data: publicKeyData, encoding: .utf8) ?? ""
                let base64String = pemString
                    .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
                    .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
                    .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
                    .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard let decodedData = Data(base64Encoded: base64String),
                      let pemKey = SecKeyCreateWithData(decodedData as CFData, [
                        kSecAttrKeyType: kSecAttrKeyTypeRSA,
                        kSecAttrKeyClass: kSecAttrKeyClassPublic
                      ] as CFDictionary, &error) else {
                    ErrorManager.shared.handleError(CryptoError.invalidPublicKey, context: "Failed to create SecKey from public key data")
                    throw CryptoError.invalidPublicKey
                }
                publicKey = pemKey
            }
            
            // Encrypt the key using RSA-OAEP with SHA-256
            guard let encryptedData = SecKeyCreateEncryptedData(
                publicKey,
                .rsaEncryptionOAEPSHA256,
                keyData as CFData,
                &error
            ) else {
                let wrappingError = error?.takeRetainedValue() as Error? ?? CryptoError.keyWrappingFailed
                ErrorManager.shared.handleError(wrappingError, context: "RSA key wrapping failed")
                throw CryptoError.keyWrappingFailed
            }
            
            return encryptedData as Data
            
        } catch {
            ErrorManager.shared.handleError(error, context: "Export key wrapping failed")
            if error is CryptoError {
                throw error
            } else {
                throw CryptoError.keyWrappingFailed
            }
        }
    }
}