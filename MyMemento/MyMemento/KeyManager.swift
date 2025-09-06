import Foundation
import CryptoKit
import Security

enum KeyManagerError: Error {
    case keyGenerationFailed
    case keychainStoreFailed
    case keychainRetrieveFailed
    case keyNotFound
    case invalidKeyData
    case rsaKeyGenerationFailed
    case invalidRSAKeyData
}

class KeyManager {
    static let shared = KeyManager()
    
    private let keychainService = "app.jam.ios.MyMemento.encryption"
    private let keychainAccount = "master-key"
    private let exportKeyTag = "com.mymemento.exportkey"
    
    private var cachedKey: SymmetricKey?
    private var cachedPrivateKey: SecKey?
    private var cachedPublicKey: SecKey?
    private var isTestMode = false
    
    private init() {}
    
    /// Enables test mode (for unit testing)
    func enableTestMode() {
        isTestMode = true
        cachedKey = nil
        cachedPrivateKey = nil
        cachedPublicKey = nil
    }
    
    /// Disables test mode
    func disableTestMode() {
        isTestMode = false
        cachedKey = nil
        cachedPrivateKey = nil
        cachedPublicKey = nil
    }
    
    /// Retrieves or generates the encryption key
    /// - Returns: The symmetric encryption key
    /// - Throws: KeyManagerError if key operations fail
    func getEncryptionKey() throws -> SymmetricKey {
        // In test mode, use UserDefaults instead of keychain
        if isTestMode {
            return try getTestEncryptionKey()
        }
        
        // Return cached key if available
        if let cachedKey = cachedKey {
            return cachedKey
        }
        
        // Try to retrieve existing key from keychain
        do {
            let key = try retrieveKeyFromKeychain()
            cachedKey = key
            return key
        } catch KeyManagerError.keyNotFound {
            // Generate new key if none exists
            let newKey = try generateAndStoreNewKey()
            cachedKey = newKey
            return newKey
        }
    }
    
    /// Sets a test encryption key (for unit testing)
    func setTestEncryptionKey(_ key: SymmetricKey) {
        guard isTestMode else { return }
        let keyData = key.withUnsafeBytes { Data($0) }
        UserDefaults.standard.set(keyData, forKey: "test-encryption-key")
    }
    
    /// Retrieves test encryption key from UserDefaults
    private func getTestEncryptionKey() throws -> SymmetricKey {
        guard let keyData = UserDefaults.standard.data(forKey: "test-encryption-key") else {
            throw KeyManagerError.keyNotFound
        }
        return SymmetricKey(data: keyData)
    }
    
    /// Generates a new encryption key and stores it in the keychain
    /// - Returns: The newly generated symmetric key
    /// - Throws: KeyManagerError if generation or storage fails
    private func generateAndStoreNewKey() throws -> SymmetricKey {
        // Generate new 256-bit AES key
        let key = SymmetricKey(size: .bits256)
        
        // Store in keychain
        try storeKeyInKeychain(key)
        
        return key
    }
    
    /// Stores a symmetric key in the keychain
    /// - Parameter key: The key to store
    /// - Throws: KeyManagerError if storage fails
    private func storeKeyInKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing key first
        SecItemDelete(query as CFDictionary)
        
        // Add the new key
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeyManagerError.keychainStoreFailed
        }
    }
    
    /// Retrieves the symmetric key from the keychain
    /// - Returns: The retrieved symmetric key
    /// - Throws: KeyManagerError if retrieval fails
    private func retrieveKeyFromKeychain() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeyManagerError.keyNotFound
            } else {
                throw KeyManagerError.keychainRetrieveFailed
            }
        }
        
        guard let keyData = result as? Data else {
            throw KeyManagerError.invalidKeyData
        }
        
        return SymmetricKey(data: keyData)
    }
    
    /// Clears the cached key (useful for testing or logout scenarios)
    func clearCachedKey() {
        cachedKey = nil
    }
    
    /// Deletes the key from keychain (useful for logout or reset scenarios)
    /// - Throws: KeyManagerError if deletion fails
    func deleteKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeyManagerError.keychainStoreFailed
        }
        
        clearCachedKey()
    }
    
    // MARK: - RSA Export Key Management
    
    /// Retrieves the RSA private key for export operations
    /// - Returns: The RSA private key
    /// - Throws: KeyManagerError if key operations fail
    func getExportPrivateKey() throws -> SecKey {
        if let cachedPrivateKey = cachedPrivateKey {
            return cachedPrivateKey
        }
        
        do {
            let privateKey = try retrieveRSAPrivateKeyFromKeychain()
            cachedPrivateKey = privateKey
            return privateKey
        } catch KeyManagerError.keyNotFound {
            // Generate new keypair if none exists
            let (privateKey, publicKey) = try generateAndStoreRSAKeypair()
            cachedPrivateKey = privateKey
            cachedPublicKey = publicKey
            return privateKey
        } catch {
            ErrorManager.shared.handleError(error, context: "Failed to retrieve export private key")
            throw error
        }
    }
    
    /// Retrieves the RSA public key for export operations
    /// - Returns: The RSA public key
    /// - Throws: KeyManagerError if key operations fail
    func getExportPublicKey() throws -> SecKey {
        if let cachedPublicKey = cachedPublicKey {
            return cachedPublicKey
        }
        
        do {
            let publicKey = try retrieveRSAPublicKeyFromKeychain()
            cachedPublicKey = publicKey
            return publicKey
        } catch KeyManagerError.keyNotFound {
            // Generate new keypair if none exists
            let (privateKey, publicKey) = try generateAndStoreRSAKeypair()
            cachedPrivateKey = privateKey
            cachedPublicKey = publicKey
            return publicKey
        } catch {
            ErrorManager.shared.handleError(error, context: "Failed to retrieve export public key")
            throw error
        }
    }
    
    /// Returns the RSA public key in DER format for sharing
    /// - Returns: The public key data in DER format
    /// - Throws: KeyManagerError if key operations fail
    func getExportPublicKeyData() throws -> Data {
        let publicKey = try getExportPublicKey()
        
        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            let keyError = error?.takeRetainedValue() as Error? ?? KeyManagerError.invalidRSAKeyData
            ErrorManager.shared.handleError(keyError, context: "Failed to extract public key data")
            throw KeyManagerError.invalidRSAKeyData
        }
        
        return keyData as Data
    }
    
    // MARK: - Private RSA Key Management
    
    /// Generates and stores a new RSA keypair in the keychain
    /// - Returns: A tuple containing the private and public keys
    /// - Throws: KeyManagerError if generation or storage fails
    private func generateAndStoreRSAKeypair() throws -> (SecKey, SecKey) {
        do {
            // Define key attributes for 3072-bit RSA private key
            let privateKeyAttrs: [String: Any] = [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits as String: 3072,
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: exportKeyTag.data(using: .utf8)!,
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            
            // Generate private key using SecKeyCreateRandomKey
            var error: Unmanaged<CFError>?
            guard let privateKey = SecKeyCreateRandomKey(privateKeyAttrs as CFDictionary, &error) else {
                let keyError = error?.takeRetainedValue() as Error? ?? KeyManagerError.rsaKeyGenerationFailed
                ErrorManager.shared.handleError(keyError, context: "RSA private key generation failed")
                throw KeyManagerError.rsaKeyGenerationFailed
            }
            
            // Get the public key from the private key
            guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
                ErrorManager.shared.handleError(KeyManagerError.rsaKeyGenerationFailed, context: "Failed to extract public key from private key")
                throw KeyManagerError.rsaKeyGenerationFailed
            }
            
            // Store public key in keychain separately for easy retrieval
            let publicKeyAttrs: [String: Any] = [
                kSecClass as String: kSecClassKey,
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
                kSecAttrApplicationTag as String: (exportKeyTag + ".public").data(using: .utf8)!,
                kSecValueRef as String: publicKey,
                kSecAttrIsPermanent as String: true
            ]
            
            let status = SecItemAdd(publicKeyAttrs as CFDictionary, nil)
            if status != errSecSuccess && status != errSecDuplicateItem {
                ErrorManager.shared.handleError(KeyManagerError.keychainStoreFailed, context: "Failed to store public key in keychain, status: \(status)")
                // Continue anyway - we can extract public key from private key if needed
            }
            
            return (privateKey, publicKey)
            
        } catch {
            ErrorManager.shared.handleError(error, context: "Failed to generate RSA keypair")
            throw KeyManagerError.rsaKeyGenerationFailed
        }
    }
    
    /// Retrieves the RSA private key from the keychain
    /// - Returns: The RSA private key
    /// - Throws: KeyManagerError if retrieval fails
    private func retrieveRSAPrivateKeyFromKeychain() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: exportKeyTag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeyManagerError.keyNotFound
            } else {
                ErrorManager.shared.handleError(KeyManagerError.keychainRetrieveFailed, context: "Failed to retrieve RSA private key, status: \(status)")
                throw KeyManagerError.keychainRetrieveFailed
            }
        }
        
        return result as! SecKey
    }
    
    /// Retrieves the RSA public key from the keychain
    /// - Returns: The RSA public key
    /// - Throws: KeyManagerError if retrieval fails
    private func retrieveRSAPublicKeyFromKeychain() throws -> SecKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: (exportKeyTag + ".public").data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeyManagerError.keyNotFound
            } else {
                ErrorManager.shared.handleError(KeyManagerError.keychainRetrieveFailed, context: "Failed to retrieve RSA public key, status: \(status)")
                throw KeyManagerError.keychainRetrieveFailed
            }
        }
        
        return result as! SecKey
    }
}