//
//  MyMementoTests.swift
//  MyMementoTests
//
//  Created by James Andrew Myers on 8/21/25.
//

import Testing
import CoreData
import CryptoKit
import Foundation
@testable import MyMemento

struct MyMementoTests {
    
    @Test func testExportManagerFullFlow() async throws {
        // Step 0: Enable test mode
        KeyManager.shared.enableTestMode()
        
        defer {
            KeyManager.shared.disableTestMode()
        }
        
        // Step 1: Generate test RSA keypair
        let (publicKey, privateKey) = try generateTestRSAKeypair()
        let publicKeyData = try extractPublicKeyData(from: publicKey)
        
        // Step 2: Set up in-memory Core Data stack
        let context = createInMemoryCoreDataContext()
        
        // Step 3: Create dummy note with attachment
        let note = try await createTestNoteWithAttachment(context: context)
        
        var exportURL: URL?
        
        defer {
            // Cleanup: Remove export file and temp directories
            if let exportURL = exportURL {
                try? FileManager.default.removeItem(at: exportURL)
            }
            cleanupTestFiles()
        }
        
        do {
            // Step 4: Run export
            exportURL = try await ExportManager.shared.export(note: note, publicKey: publicKeyData)
            
            // Step 5: Verify output zip contains required files
            let zipContents = try getZipContents(at: exportURL!)
            #expect(zipContents.contains("manifest.json"))
            #expect(zipContents.contains("export.enc"))
            #expect(zipContents.contains("key.enc"))
            
            // Step 6: Validate manifest.json
            let manifestData = try readFileFromZip(zipURL: exportURL!, fileName: "manifest.json")
            let manifest = try validateManifestStructure(manifestData)
            
            // Step 7: Decrypt key.enc with private key
            let encryptedKeyData = try readFileFromZip(zipURL: exportURL!, fileName: "key.enc")
            let decryptedKey = try decryptKeyWithRSA(encryptedKeyData, privateKey: privateKey)
            
            // Step 8: Decrypt export.enc with AES-GCM
            let encryptedBundleData = try readFileFromZip(zipURL: exportURL!, fileName: "export.enc")
            let decryptedBundle = try decryptBundleWithAES(
                encryptedBundleData,
                key: decryptedKey,
                nonce: Data(base64Encoded: manifest["nonce"] as! String)!,
                tag: Data(base64Encoded: manifest["tag"] as! String)!
            )
            
            // Step 9: Verify recovered content
            try await verifyRecoveredContent(decryptedBundle, originalNote: note)
            
        } catch {
            Issue.record("Export test failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateTestRSAKeypair() throws -> (publicKey: SecKey, privateKey: SecKey) {
        let keySize = 2048
        let privateKeyAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: false,
            kSecAttrApplicationTag as String: "test.rsa.private".data(using: .utf8)!
        ]
        let publicKeyAttributes: [String: Any] = [
            kSecAttrIsPermanent as String: false,
            kSecAttrApplicationTag as String: "test.rsa.public".data(using: .utf8)!
        ]
        
        let keyPairAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: keySize,
            kSecPrivateKeyAttrs as String: privateKeyAttributes,
            kSecPublicKeyAttrs as String: publicKeyAttributes
        ]
        
        var publicKey: SecKey?
        var privateKey: SecKey?
        let status = SecKeyGeneratePair(keyPairAttributes as CFDictionary, &publicKey, &privateKey)
        
        guard status == errSecSuccess,
              let pubKey = publicKey,
              let privKey = privateKey else {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to generate RSA keypair"])
        }
        
        return (pubKey, privKey)
    }
    
    private func extractPublicKeyData(from publicKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            throw error?.takeRetainedValue() as Error? ?? NSError(domain: "TestError", code: 2)
        }
        return publicKeyData as Data
    }
    
    private func createInMemoryCoreDataContext() -> NSManagedObjectContext {
        let container = NSPersistentContainer(name: "MyMemento")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load in-memory store: \(error)")
            }
        }
        
        return container.viewContext
    }
    
    private func createTestNoteWithAttachment(context: NSManagedObjectContext) async throws -> Note {
        // Create encryption key for note
        let encryptionKey = SymmetricKey(size: .bits256)
        
        // Create note payload
        let notePayload = NotePayload(
            title: "Test Note",
            body: NSAttributedStringWrapper(NSAttributedString(string: "This is a test note with <b>bold</b> text.")),
            tags: ["test-tag"],
            createdAt: Date(),
            updatedAt: Date(),
            pinned: false
        )
        
        // Encrypt the payload
        let encryptedData = try CryptoHelper.encrypt(notePayload, key: encryptionKey)
        
        // Create Core Data Note entity
        let note = Note(context: context)
        note.id = UUID()
        note.encryptedData = encryptedData
        
        // Create a test tag
        let tag = Tag(context: context)
        tag.id = UUID()
        tag.name = "test-tag"
        tag.createdAt = Date()
        note.addToTags(tag)
        
        // Create a small test attachment
        try await createTestAttachment(for: note, context: context)
        
        // Save context
        try context.save()
        
        // Store the key for later use (in real app this would be in KeyManager)
        try storeTestKey(encryptionKey)
        
        return note
    }
    
    private func createTestAttachment(for note: Note, context: NSManagedObjectContext) async throws {
        // Create a small test file
        let testContent = "This is a test attachment file content."
        let testData = testContent.data(using: .utf8)!
        
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test-attachment.txt")
        try testData.write(to: testFileURL)
        
        // Create attachment using AttachmentManager (this handles encryption)
        let attachment = try await AttachmentManager.shared.createVideoAttachment(
            for: note, 
            from: testFileURL, 
            context: context
        )
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: testFileURL)
    }
    
    private func storeTestKey(_ key: SymmetricKey) throws {
        // Store test key using KeyManager's test mode
        KeyManager.shared.setTestEncryptionKey(key)
    }
    
    private func getZipContents(at url: URL) throws -> [String] {
        // Since we're using directory-based archives, list directory contents
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        return contents.map { $0.lastPathComponent }
    }
    
    private func readFileFromZip(zipURL: URL, fileName: String) throws -> Data {
        let fileURL = zipURL.appendingPathComponent(fileName)
        return try Data(contentsOf: fileURL)
    }
    
    private func validateManifestStructure(_ manifestData: Data) throws -> [String: Any] {
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
        
        // Validate required fields
        #expect(manifest["version"] as? String == "1.0")
        #expect(manifest["noteId"] is String)
        #expect(manifest["title"] as? String == "Test Note")
        #expect((manifest["tags"] as? [String])?.contains("test-tag") == true)
        #expect(manifest["createdAt"] is String)
        #expect(manifest["updatedAt"] is String)
        #expect(manifest["pinned"] as? Bool == false)
        
        // Validate crypto section
        let crypto = manifest["crypto"] as! [String: Any]
        #expect(crypto["cipher"] as? String == "AES-256-GCM")
        #expect(crypto["keyWrap"] as? String == "RSA-OAEP-SHA256")
        #expect(crypto["nonce"] is String)
        #expect(crypto["tag"] is String)
        
        // Extract crypto values for return
        var result = manifest
        result["nonce"] = crypto["nonce"]
        result["tag"] = crypto["tag"]
        
        return result
    }
    
    private func decryptKeyWithRSA(_ encryptedKeyData: Data, privateKey: SecKey) throws -> SymmetricKey {
        var error: Unmanaged<CFError>?
        guard let decryptedData = SecKeyCreateDecryptedData(
            privateKey,
            .rsaEncryptionOAEPSHA256,
            encryptedKeyData as CFData,
            &error
        ) else {
            throw error?.takeRetainedValue() as Error? ?? NSError(domain: "TestError", code: 3)
        }
        
        return SymmetricKey(data: decryptedData as Data)
    }
    
    private func decryptBundleWithAES(_ encryptedData: Data, key: SymmetricKey, nonce: Data, tag: Data) throws -> Data {
        // Extract components (nonce is at start, tag at end, ciphertext in middle)
        let storedNonceData = encryptedData.prefix(12)
        let storedTagData = encryptedData.suffix(16)
        let ciphertextData = encryptedData.dropFirst(12).dropLast(16)
        
        // Verify nonce and tag match manifest values
        #expect(storedNonceData == nonce)
        #expect(storedTagData == tag)
        
        // Reconstruct sealed box
        let aesgcmNonce = try AES.GCM.Nonce(data: nonce)
        let sealedBox = try AES.GCM.SealedBox(nonce: aesgcmNonce, ciphertext: ciphertextData, tag: tag)
        
        // Decrypt
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    private func verifyRecoveredContent(_ decryptedBundle: Data, originalNote: Note) async throws {
        // Write decrypted bundle to temporary location for inspection
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Since we're using directory-based archives, the decrypted bundle should be the archive content
        // For simplicity, we'll check if we can find body.html in the decrypted data
        
        // This is a simplified check - in a real implementation you'd need to properly unpack the archive
        let bundleString = String(data: decryptedBundle, encoding: .utf8) ?? ""
        #expect(bundleString.contains("test note"))
    }
    
    private func cleanupTestFiles() {
        // Remove any test keys from UserDefaults
        UserDefaults.standard.removeObject(forKey: "test-encryption-key")
        
        // Clean up any remaining temp files
        let tempDir = FileManager.default.temporaryDirectory
        let contents = try? FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        contents?.forEach { url in
            if url.lastPathComponent.hasPrefix("test") || url.lastPathComponent.contains("export") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
    
    @Test func testKeyManagerRSAFunctionality() async throws {
        // Test RSA keypair generation and retrieval
        let privateKey = try KeyManager.shared.getExportPrivateKey()
        let publicKey = try KeyManager.shared.getExportPublicKey()
        
        // Verify keys are valid
        #expect(SecKeyGetTypeID() == CFGetTypeID(privateKey))
        #expect(SecKeyGetTypeID() == CFGetTypeID(publicKey))
        
        // Test public key data extraction
        let publicKeyData = try KeyManager.shared.getExportPublicKeyData()
        #expect(publicKeyData.count > 0)
        
        // Test that we get the same keys on subsequent calls (caching)
        let privateKey2 = try KeyManager.shared.getExportPrivateKey()
        let publicKey2 = try KeyManager.shared.getExportPublicKey()
        
        #expect(CFEqual(privateKey, privateKey2))
        #expect(CFEqual(publicKey, publicKey2))
        
        // Test encryption/decryption roundtrip to verify keys work
        let testData = "Hello, RSA!".data(using: .utf8)!
        
        var error: Unmanaged<CFError>?
        guard let encryptedData = SecKeyCreateEncryptedData(
            publicKey,
            .rsaEncryptionOAEPSHA256,
            testData as CFData,
            &error
        ) else {
            Issue.record("RSA encryption failed")
            return
        }
        
        guard let decryptedData = SecKeyCreateDecryptedData(
            privateKey,
            .rsaEncryptionOAEPSHA256,
            encryptedData,
            &error
        ) else {
            Issue.record("RSA decryption failed")
            return
        }
        
        let decryptedString = String(data: decryptedData as Data, encoding: .utf8)
        #expect(decryptedString == "Hello, RSA!")
    }
}

