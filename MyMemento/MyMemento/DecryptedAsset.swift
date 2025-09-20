import Foundation
import AVFoundation
import AVKit
import CryptoKit
import SwiftUI
import OSLog
import UniformTypeIdentifiers

/// Custom AVURLAsset that decrypts encrypted video files on-the-fly for playback
class DecryptedAsset: AVURLAsset, @unchecked Sendable {
    
    private let encryptedFileURL: URL
    private let encryptionKey: SymmetricKey
    private let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "DecryptedAsset")
    private let customResourceLoader: DecryptedAssetResourceLoader
    
    /// Custom scheme used to trigger our resource loader
    private static let customScheme = "mymemento-encrypted"
    
    /// Initializes a DecryptedAsset with an encrypted file and decryption key
    /// - Parameters:
    ///   - encryptedFileURL: URL to the encrypted .vaultvideo file
    ///   - key: SymmetricKey for decryption
    init(encryptedFileURL: URL, key: SymmetricKey) {
        self.encryptedFileURL = encryptedFileURL
        self.encryptionKey = key
        
        // Create a custom URL with our scheme to trigger resource loading
        var components = URLComponents(url: encryptedFileURL, resolvingAgainstBaseURL: false)!
        components.scheme = DecryptedAsset.customScheme
        let customURL = components.url!
        
        // Create resource loader before calling super.init
        self.customResourceLoader = DecryptedAssetResourceLoader(
            encryptedFileURL: encryptedFileURL,
            key: key
        )
        
        super.init(url: customURL, options: nil)
        
        // Set up resource loader delegate using the inherited resourceLoader property
        self.resourceLoader.setDelegate(self.customResourceLoader, queue: DispatchQueue(label: "DecryptedAssetResourceLoader"))
        
        logger.info("DecryptedAsset initialized for file: \(encryptedFileURL.lastPathComponent)")
    }
}

// MARK: - Resource Loader Implementation

/// Handles resource loading requests for encrypted video data
fileprivate class DecryptedAssetResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    
    private let encryptedFileURL: URL
    private let encryptionKey: SymmetricKey
    private let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "DecryptedAssetResourceLoader")
    private let fileManager = FileManager.default
    
    // Cache decrypted data to avoid re-decryption
    private var decryptedData: Data?
    private let decryptionQueue = DispatchQueue(label: "DecryptedAssetDecryption", qos: .userInitiated)
    
    init(encryptedFileURL: URL, key: SymmetricKey) {
        self.encryptedFileURL = encryptedFileURL
        self.encryptionKey = key
        super.init()
    }
    
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        logger.info("Resource loading requested for: \(loadingRequest.request.url?.absoluteString ?? "unknown")")
        
        // Handle the request asynchronously
        decryptionQueue.async {
            self.handleLoadingRequest(loadingRequest)
        }
        
        return true
    }
    
    private func handleLoadingRequest(_ loadingRequest: AVAssetResourceLoadingRequest) {
        do {
            // Decrypt the file if we haven't already
            if decryptedData == nil {
                decryptedData = try decryptFile()
            }
            
            guard let data = decryptedData else {
                throw DecryptedAssetError.decryptionFailed
            }
            
            // Handle content information request
            if let contentInformationRequest = loadingRequest.contentInformationRequest {
                // Detect container type from 'ftyp' box if available
                let detectedType = detectContentUTI(from: data)
                contentInformationRequest.contentType = detectedType
                contentInformationRequest.contentLength = Int64(data.count)
                contentInformationRequest.isByteRangeAccessSupported = true
                logger.info("Provided content info - length: \(data.count)")
            }
            
            // Handle data request
            if let dataRequest = loadingRequest.dataRequest {
                let _ = Int(dataRequest.requestedOffset)
                let requestedLength = dataRequest.requestedLength
                let currentOffset = Int(dataRequest.currentOffset)
                
                // Calculate actual range to serve
                let startOffset = currentOffset
                let endOffset = min(startOffset + requestedLength, data.count)
                let rangeLength = endOffset - startOffset
                
                if startOffset < data.count && rangeLength > 0 {
                    let responseData = data.subdata(in: startOffset..<endOffset)
                    dataRequest.respond(with: responseData)
                    logger.info("Served data range: \(startOffset)-\(endOffset-1) (\(rangeLength) bytes)")
                } else {
                    logger.warning("Requested data range out of bounds: \(startOffset)-\(endOffset)")
                }
            }
            
            // Complete the loading request
            loadingRequest.finishLoading()
            
        } catch {
            logger.error("Failed to handle loading request: \(error.localizedDescription)")
            ErrorManager.shared.handleError(error, context: "Video decryption")
            loadingRequest.finishLoading(with: error)
        }
    }

    private func decryptFile() throws -> Data {
        logger.info("Starting decryption of: \(self.encryptedFileURL.lastPathComponent)")
        
        // Read the encrypted file
        let encryptedData = try Data(contentsOf: encryptedFileURL)
        
        // Validate minimum file size (nonce + tag = 28 bytes minimum)
        guard encryptedData.count >= 28 else {
            throw DecryptedAssetError.invalidEncryptedFile
        }
        
        // Extract components from the encrypted data
        let nonceData = encryptedData.prefix(12) // AES.GCM nonce is 12 bytes
        let tagData = encryptedData.suffix(16)   // AES.GCM tag is 16 bytes
        let ciphertextData = encryptedData.dropFirst(12).dropLast(16)
        
        // Reconstruct the sealed box
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
        
        // Decrypt the data
        let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)
        
        logger.info("Successfully decrypted \(encryptedData.count) bytes to \(decryptedData.count) bytes")
        
        return decryptedData
    }

    /// Attempts to detect an appropriate UTI for the decrypted movie
    /// Defaults to public.movie, prefers QuickTime for typical iOS camera MOV files
    private func detectContentUTI(from data: Data) -> String {
        // ISO Base Media File Format starts with 4-byte size then 'ftyp'
        guard data.count >= 12 else { return UTType.movie.identifier }
        let typeRange = 4..<8
        let brandRange = 8..<12
        if let type = String(data: data[typeRange], encoding: .ascii), type == "ftyp" {
            if let major = String(data: data[brandRange], encoding: .ascii) {
                let lower = major.lowercased()
                if lower.hasPrefix("qt") { // QuickTime brand
                    return UTType.quickTimeMovie.identifier
                }
                // Common MP4 brands: isom, mp41, mp42, avc1
                if ["isom","mp41","mp42","avc1","hvc1","heic"].contains(lower) {
                    return AVFileType.mp4.rawValue
                }
            }
        }
        return UTType.movie.identifier
    }
}

// MARK: - Error Types

enum DecryptedAssetError: Error, LocalizedError {
    case decryptionFailed
    case invalidEncryptedFile
    case fileNotFound
    case invalidKey
    
    var errorDescription: String? {
        switch self {
        case .decryptionFailed:
            return "Failed to decrypt video file"
        case .invalidEncryptedFile:
            return "Invalid encrypted file format"
        case .fileNotFound:
            return "Encrypted video file not found"
        case .invalidKey:
            return "Invalid decryption key"
        }
    }
}

// MARK: - SwiftUI Video Player View

/// SwiftUI view that plays encrypted video attachments using DecryptedAsset
struct VideoAttachmentPlayer: View {
    
    let attachment: Attachment
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var hasError = false
    @State private var errorMessage: String?
    
    private let logger = Logger(subsystem: "app.jam.ios.MyMemento", category: "VideoAttachmentPlayer")
    
    var body: some View {
        ZStack {
            if let player = player, !hasError {
                VideoPlayer(player: player)
                    .onAppear {
                        do {
                            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
                            try AVAudioSession.sharedInstance().setActive(true)
                        } catch {
                            ErrorManager.shared.handleError(error, context: "Activating audio session for video playback")
                        }
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else if hasError {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    
                    Text("Cannot play video")
                        .font(.headline)
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button("Retry") {
                        loadVideo()
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("Loading video...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            loadVideo()
        }
        .onDisappear {
            cleanup()
        }
    }
    
    private func loadVideo() {
        Task {
            await loadVideoAsync()
        }
    }
    
    @MainActor
    private func loadVideoAsync() async {
        isLoading = true
        hasError = false
        errorMessage = nil
        
        do {
            // Validate attachment
            guard let relativePath = attachment.relativePath else {
                throw DecryptedAssetError.fileNotFound
            }
            
            // Get encrypted file URL
            guard let applicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                throw DecryptedAssetError.fileNotFound
            }
            
            let encryptedFileURL = applicationSupportURL.appendingPathComponent(relativePath)
            
            // Verify file exists
            guard FileManager.default.fileExists(atPath: encryptedFileURL.path) else {
                throw DecryptedAssetError.fileNotFound
            }
            
            // Get decryption key
            let encryptionKey = try KeyManager.shared.getEncryptionKey()
            
            // Create DecryptedAsset
            let decryptedAsset = DecryptedAsset(encryptedFileURL: encryptedFileURL, key: encryptionKey)
            
            // Create player
            let newPlayer = AVPlayer(playerItem: AVPlayerItem(asset: decryptedAsset))
            
            // Update UI
            player = newPlayer
            isLoading = false
            
            logger.info("Successfully loaded encrypted video: \(attachment.id?.uuidString ?? "unknown")")
            
        } catch {
            logger.error("Failed to load encrypted video: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            hasError = true
            isLoading = false
            
            ErrorManager.shared.handleError(error, context: "Loading encrypted video")
        }
    }
    
    private func cleanup() {
        player?.pause()
        player = nil
        logger.info("Cleaned up video player")
    }
}

// MARK: - Preview Support

#if DEBUG
struct VideoAttachmentPlayer_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock attachment for preview
        let context = PersistenceController.preview.container.viewContext
        let mockAttachment = Attachment(context: context)
        mockAttachment.id = UUID()
        mockAttachment.type = "video"
        mockAttachment.relativePath = "Media/preview.vaultvideo"
        mockAttachment.createdAt = Date()
        
        return VideoAttachmentPlayer(attachment: mockAttachment)
            .frame(height: 300)
            .previewLayout(.sizeThatFits)
    }
}
#endif
