import Foundation
import CryptoKit
import Security

enum KeyManagerError: Error {
    case keyGenerationFailed
    case keychainStoreFailed
    case keychainRetrieveFailed
    case keyNotFound
    case invalidKeyData
}

class KeyManager {
    static let shared = KeyManager()
    
    private let keychainService = "app.jam.ios.MyMemento.encryption"
    private let keychainAccount = "master-key"
    
    private var cachedKey: SymmetricKey?
    
    private init() {}
    
    /// Retrieves or generates the encryption key
    /// - Returns: The symmetric encryption key
    /// - Throws: KeyManagerError if key operations fail
    func getEncryptionKey() throws -> SymmetricKey {
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
}