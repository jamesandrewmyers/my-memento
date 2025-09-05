import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

struct EncryptedExportView: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @StateObject private var errorManager = ErrorManager.shared
    
    @State private var publicKeyText = ""
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportProgress = 0.0
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var validationMessage = ""
    @State private var isKeyValid = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Public Key Required")
                        .font(.headline)
                    
                    Text("Enter or import an RSA public key to encrypt the export. The key can be in PEM or DER format.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Button("Import Key File") {
                            isImporting = true
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                    }
                    
                    Text("Or paste PEM text:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 8) {
                    TextEditor(text: $publicKeyText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .onChange(of: publicKeyText) { _ in
                            validatePublicKey()
                        }
                    
                    HStack {
                        if !validationMessage.isEmpty {
                            Image(systemName: isKeyValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isKeyValid ? .green : .red)
                            Text(validationMessage)
                                .font(.caption)
                                .foregroundColor(isKeyValid ? .green : .red)
                        }
                        Spacer()
                    }
                }
                
                if isExporting {
                    VStack(spacing: 12) {
                        ProgressView(value: exportProgress)
                        Text("Exporting encrypted note...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Export Encrypted Note") {
                    startExport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isKeyValid || isExporting || publicKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle("Encrypted Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.data, .text],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ActivityView(activityItems: [url])
            }
        }
        .alert("Error", isPresented: $errorManager.showError) {
            Button("OK") { }
        } message: {
            Text(errorManager.errorMessage)
        }
    }
    
    private func validatePublicKey() {
        let trimmed = publicKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            validationMessage = ""
            isKeyValid = false
            return
        }
        
        do {
            let keyData = try parsePublicKeyData(from: trimmed)
            let _ = try createSecKey(from: keyData)
            validationMessage = "Valid RSA public key"
            isKeyValid = true
        } catch {
            validationMessage = "Invalid public key format"
            isKeyValid = false
        }
    }
    
    private func parsePublicKeyData(from text: String) throws -> Data {
        // First try as PEM format
        if text.contains("BEGIN PUBLIC KEY") || text.contains("BEGIN RSA PUBLIC KEY") {
            let base64String = text
                .replacingOccurrences(of: "-----BEGIN PUBLIC KEY-----", with: "")
                .replacingOccurrences(of: "-----END PUBLIC KEY-----", with: "")
                .replacingOccurrences(of: "-----BEGIN RSA PUBLIC KEY-----", with: "")
                .replacingOccurrences(of: "-----END RSA PUBLIC KEY-----", with: "")
                .replacingOccurrences(of: "\\n", with: "")
                .replacingOccurrences(of: "\\r", with: "")
                .replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let data = Data(base64Encoded: base64String) else {
                throw CryptoError.invalidPublicKey
            }
            return data
        } else {
            // Try as raw base64 or hex
            if let base64Data = Data(base64Encoded: text) {
                return base64Data
            } else {
                throw CryptoError.invalidPublicKey
            }
        }
    }
    
    private func createSecKey(from data: Data) throws -> SecKey {
        var error: Unmanaged<CFError>?
        
        guard let secKey = SecKeyCreateWithData(data as CFData, [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic
        ] as CFDictionary, &error) else {
            if let err = error?.takeRetainedValue() {
                throw err
            }
            throw CryptoError.invalidPublicKey
        }
        
        return secKey
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                let data = try Data(contentsOf: url)
                if let text = String(data: data, encoding: .utf8) {
                    publicKeyText = text
                    validatePublicKey()
                } else {
                    // Try as binary data
                    publicKeyText = data.base64EncodedString()
                    validatePublicKey()
                }
            } catch {
                errorManager.handleError(error, context: "Failed to read key file")
            }
            
        case .failure(let error):
            errorManager.handleError(error, context: "Failed to import key file")
        }
    }
    
    private func startExport() {
        guard isKeyValid, let keyData = try? parsePublicKeyData(from: publicKeyText) else {
            return
        }
        
        isExporting = true
        exportProgress = 0.0
        
        Task {
            do {
                // Update progress
                await MainActor.run { exportProgress = 0.2 }
                
                // Call ExportManager
                let exportURL = try await ExportManager.shared.export(note: note, publicKey: keyData)
                
                await MainActor.run {
                    exportProgress = 1.0
                    exportedFileURL = exportURL
                    isExporting = false
                    showShareSheet = true
                }
                
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportProgress = 0.0
                    errorManager.handleError(error, context: "Encrypted export failed")
                }
            }
        }
    }
}

#Preview {
    // Create a mock Note for preview
    let context = PersistenceController.preview.container.viewContext
    let note = Note(context: context)
    note.id = UUID()
    note.createdAt = Date()
    
    return EncryptedExportView(note: note)
}