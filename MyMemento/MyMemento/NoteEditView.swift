//
//  NoteEditView.swift
//  MyMemento
//
//  Created by James Andrew Myers on 8/22/25.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreData
import Foundation
import AVFoundation
import PhotosUI

struct NoteEditView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var noteIndexViewModel: NoteIndexViewModel
    @StateObject private var errorManager = ErrorManager.shared
    
    let indexPayload: IndexPayload
    @State private var note: Note?
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)],
        animation: .default)
    private var allNotes: FetchedResults<Note>
    
    @State private var title: String = ""
    @State private var tags: String = ""
    @State private var noteBody: NSAttributedString = NSAttributedString()
    @State private var editorCoordinator: RichTextEditor.Coordinator?
    @State private var isBold = false
    @State private var isItalic = false
    @State private var isUnderlined = false
    @State private var isStrikethrough = false
    @State private var isBulletList = false
    @State private var isNumberedList = false
    @State private var isH1 = false
    @State private var isH2 = false
    @State private var isH3 = false
    @State private var showLinkDialog = false
    @State private var linkDisplayLabel = ""
    @State private var linkURL = ""
    
    // MARK: - Attachments UI State
    @State private var videoThumbnails: [UUID: UIImage] = [:]
    @State private var generatingThumbnailIDs: Set<UUID> = []
    @State private var selectedVideoAttachment: Attachment?
    @State private var isEncryptingAttachment = false
    @State private var showAttachOptions = false
    @State private var showVideoLibraryPicker = false
    @State private var showVideoCameraPicker = false
    @State private var attachmentsRefreshID = UUID()
    
    var body: some View {
        Form {
            Section(header: Text("Note Details")) {
                TextField("Title", text: $title)
                    .font(.headline)
                
                TextField("Tags", text: $tags)
                    .font(.subheadline)
            }
            
            Section(header: contentHeader) {
                if #available(iOS 15.0, *) {
                    RichTextEditorWrapper(
                        attributedText: $noteBody,
                        coordinator: $editorCoordinator,
                        isBold: $isBold,
                        isItalic: $isItalic,
                        isUnderlined: $isUnderlined,
                        isStrikethrough: $isStrikethrough,
                        isBulletList: $isBulletList,
                        isNumberedList: $isNumberedList,
                        isH1: $isH1,
                        isH2: $isH2,
                        isH3: $isH3
                    )
                    .frame(minHeight: 200)
                } else {
                    Text("Rich text editor requires iOS 15.0+")
                }
            }

            // MARK: - Attachments Section
            Section(header: Text("Attachments")) {
                // Attach Video button
                Button(action: { showAttachOptions = true }) {
                    HStack {
                        Image(systemName: "paperclip")
                        Text("Attach Video")
                        if isEncryptingAttachment {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isEncryptingAttachment || note == nil)

                if let attachmentSet = note?.attachments as? Set<Attachment>, !attachmentSet.isEmpty {
                    let videos = attachmentSet
                        .filter { ($0.type ?? "").lowercased() == "video" }
                        .sorted { (a, b) in
                            (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
                        }

                    if videos.isEmpty {
                        Text("No video attachments")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(videos, id: \.id) { attachment in
                            AttachmentVideoRow(
                                attachment: attachment,
                                thumbnail: thumbnailImage(for: attachment),
                                onAppear: { ensureThumbnail(for: attachment) },
                                onTap: {
                                    selectedVideoAttachment = attachment
                                }
                            )
                        }
                    }
                } else {
                    Text("No attachments")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .id(attachmentsRefreshID)
        }
        .navigationTitle("Edit Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .principal) {
                Button(action: togglePin) {
                    Image(systemName: note?.isPinned == true ? "pin.slash" : "pin")
                        .foregroundColor(note?.isPinned == true ? .orange : .gray)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: exportNoteAndPresentShare) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveNote()
                }
            }
        }
        .onAppear {
            loadNoteData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("EditHyperlink"))) { notification in
            if let userInfo = notification.userInfo,
               let displayLabel = userInfo["displayLabel"] as? String,
               let url = userInfo["url"] as? String {
                linkDisplayLabel = displayLabel
                linkURL = url
                showLinkDialog = true
            }
        }
        .alert("Error", isPresented: $errorManager.showError) {
            Button("OK") { }
        } message: {
            Text(errorManager.errorMessage)
        }
        .sheet(isPresented: $showLinkDialog) {
            NavigationView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display Label")
                            .font(.headline)
                        TextField("Enter display text", text: $linkDisplayLabel)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("URL")
                            .font(.headline)
                        TextField("Enter URL", text: $linkURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                    }
                    
                    HStack {
                        Spacer()
                        Button("OK") {
                            createLink()
                            showLinkDialog = false
                        }
                        .disabled(linkDisplayLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || linkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    Spacer()
                }
                .padding()
                .navigationTitle("Add Link")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showLinkDialog = false
                            linkDisplayLabel = ""
                            linkURL = ""
                        }
                    }
                }
            }
        }
        // Video playback sheet driven by selected item to avoid race conditions
        .sheet(item: $selectedVideoAttachment, onDismiss: { selectedVideoAttachment = nil }) { attachment in
            VideoAttachmentPlayer(attachment: attachment)
        }
        // Video pickers
        .sheet(isPresented: $showVideoLibraryPicker) {
            VideoLibraryPicker { url in
                showVideoLibraryPicker = false
                if let url = url { handlePickedVideo(url: url) }
            }
        }
        .sheet(isPresented: $showVideoCameraPicker) {
            VideoCameraPicker { url in
                showVideoCameraPicker = false
                if let url = url { handlePickedVideo(url: url) }
            }
        }
        // Choose source
        .confirmationDialog("Attach Video", isPresented: $showAttachOptions, titleVisibility: .visible) {
            Button("Record Video") { showVideoCameraPicker = true }
            Button("Choose from Library") { showVideoLibraryPicker = true }
            Button("Cancel", role: .cancel) { }
        }
    }
    
    private func loadNoteData() {
        // Fetch the Note entity by id
        let request: NSFetchRequest<Note> = Note.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", indexPayload.id as CVarArg)
        request.fetchLimit = 1
        
        do {
            let notes = try viewContext.fetch(request)
            if let fetchedNote = notes.first {
                note = fetchedNote
                
                // Try to decrypt existing data first
                if let encryptedData = fetchedNote.encryptedData {
                    do {
                        let encryptionKey = try KeyManager.shared.getEncryptionKey()
                        let decryptedPayload = try CryptoHelper.decrypt(encryptedData, key: encryptionKey, as: NotePayload.self)
                        
                        title = decryptedPayload.title
                        tags = decryptedPayload.tags.joined(separator: ", ")
                        noteBody = decryptedPayload.body.attributedString
                        return
                    } catch {
                        print("Failed to decrypt note data, falling back to legacy fields: \(error)")
                    }
                }
                
                // Fallback to legacy unencrypted fields
                title = fetchedNote.title ?? ""
                tags = tagsToString(fetchedNote.tags)
                noteBody = fetchedNote.richText ?? NSAttributedString()
            } else {
                // Create new Note if it doesn't exist (for new notes from addNote)
                let newNote = Note(context: viewContext)
                newNote.id = indexPayload.id
                newNote.createdAt = indexPayload.createdAt
                newNote.isPinned = indexPayload.pinned
                note = newNote
                
                // Initialize with IndexPayload data
                title = indexPayload.title
                tags = indexPayload.tags.joined(separator: ", ")
                noteBody = NSAttributedString()
            }
        } catch {
            print("Failed to fetch note: \(error)")
            // Initialize with IndexPayload data as fallback
            title = indexPayload.title
            tags = indexPayload.tags.joined(separator: ", ")
            noteBody = NSAttributedString()
        }
    }
    
    private func tagsToString(_ tagSet: NSSet?) -> String {
        guard let tagSet = tagSet as? Set<Tag> else { return "" }
        return tagSet.compactMap { $0.name }.sorted().joined(separator: ", ")
    }
    
    private func stringToTags(_ tagString: String) -> Set<Tag> {
        let tagNames = tagString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var tagSet = Set<Tag>()
        
        for tagName in tagNames {
            guard !tagName.isEmpty else { continue }
            
            // Find existing tag or create new one
            let request: NSFetchRequest<Tag> = Tag.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", tagName)
            
            do {
                let existingTags = try viewContext.fetch(request)
                if let existingTag = existingTags.first {
                    tagSet.insert(existingTag)
                } else {
                    let newTag = Tag(context: viewContext)
                    newTag.id = UUID()
                    newTag.name = tagName
                    newTag.createdAt = Date()
                    tagSet.insert(newTag)
                }
            } catch {
                print("Error fetching/creating tag: \(error)")
            }
        }
        
        return tagSet
    }
    
    private func saveNote() {
        // Capture current state immediately
        let currentTitle = title
        let currentTags = tags
        let currentNoteBody = noteBody
        guard let noteToSave = note else { return }
        
        // Perform save operation completely async
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Get encryption key
                let encryptionKey = try KeyManager.shared.getEncryptionKey()
                
                // Parse tags from string
                let tagNames = currentTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                
                // Create current timestamp for updates
                let now = Date()
                
                // Build NotePayload from captured state first (off main thread)
                let notePayload = NotePayload(
                    title: currentTitle,
                    body: NSAttributedStringWrapper(currentNoteBody),
                    tags: tagNames,
                    createdAt: noteToSave.createdAt ?? now, // Preserve original creation date
                    updatedAt: now,
                    pinned: noteToSave.isPinned
                )
                
                // Encrypt NotePayload
                let encryptedNoteData = try CryptoHelper.encrypt(notePayload, key: encryptionKey)
                
                // Build IndexPayload for search
                let summary = currentNoteBody.string.prefix(100).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Perform Core Data operations on main queue
                DispatchQueue.main.async {
                    do {
                        // Ensure note has an ID
                        if noteToSave.id == nil {
                            noteToSave.id = UUID()
                        }
                        
                        // Store encrypted data
                        noteToSave.encryptedData = encryptedNoteData
                        
                        // Find or create matching SearchIndex entity
                        let searchIndexRequest: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
                        searchIndexRequest.predicate = NSPredicate(format: "id == %@", noteToSave.id! as CVarArg)
                        
                        let searchIndex: SearchIndex
                        if let existingIndex = try self.viewContext.fetch(searchIndexRequest).first {
                            searchIndex = existingIndex
                        } else {
                            searchIndex = SearchIndex(context: self.viewContext)
                            searchIndex.id = noteToSave.id!
                        }
                        
                        // Build IndexPayload with correct ID
                        let indexPayload = IndexPayload(
                            id: noteToSave.id!,
                            title: currentTitle,
                            tags: tagNames,
                            summary: String(summary),
                            createdAt: noteToSave.createdAt ?? now, // Preserve original creation date
                            updatedAt: now,
                            pinned: noteToSave.isPinned
                        )
                        
                        // Encrypt IndexPayload and store
                        let encryptedIndexData = try CryptoHelper.encrypt(indexPayload, key: encryptionKey)
                        searchIndex.encryptedIndexData = encryptedIndexData
                        
                        print("=== SAVE DEBUG ===")
                        print("Note ID: \(noteToSave.id?.uuidString ?? "nil")")
                        print("Encrypted data size: \(encryptedNoteData.count) bytes")
                        print("SearchIndex ID: \(searchIndex.id?.uuidString ?? "nil")")
                        print("Encrypted index size: \(encryptedIndexData.count) bytes")
                        print("==================")
                        
                        // Save the Core Data context (directly on main queue)
                        try self.viewContext.save()
                        
                        print("=== SAVE SUCCESS ===")
                        
                        // Refresh the index to reflect tag changes
                        self.noteIndexViewModel.refreshIndex(from: self.viewContext)
                        
                        // Upload notes for sync (will need to be updated for encrypted data)
                        SyncService.shared.upload(notes: Array(self.allNotes))
                        
                        self.dismiss()
                        
                    } catch {
                        let nsError = error as NSError
                        print("=== CORE DATA SAVE ERROR ===")
                        print("Error: \(nsError)")
                        print("Domain: \(nsError.domain)")
                        print("Code: \(nsError.code)")
                        print("UserInfo: \(nsError.userInfo)")
                        print("=============================")
                        self.errorManager.handleCoreDataError(nsError, context: "Failed to save encrypted note")
                    }
                }
                
            } catch {
                DispatchQueue.main.async {
                    let nsError = error as NSError
                    print("=== ENCRYPTION ERROR ===")
                    print("Error: \(nsError)")
                    print("Domain: \(nsError.domain)")
                    print("Code: \(nsError.code)")
                    print("=========================")
                    self.errorManager.handleCoreDataError(nsError, context: "Failed to encrypt note data")
                }
            }
        }
    }
    
    private func togglePin() {
        guard let noteToSave = note else { return }
        noteToSave.isPinned.toggle()

        // Also update the SearchIndex
        let searchIndexRequest: NSFetchRequest<SearchIndex> = SearchIndex.fetchRequest()
        searchIndexRequest.predicate = NSPredicate(format: "id == %@", noteToSave.id! as CVarArg)

        do {
            if let searchIndex = try viewContext.fetch(searchIndexRequest).first,
               let encryptedData = searchIndex.encryptedIndexData {
                
                let encryptionKey = try KeyManager.shared.getEncryptionKey()
                
                // Decrypt, update, re-encrypt
                var decryptedPayload = try CryptoHelper.decrypt(encryptedData, key: encryptionKey, as: IndexPayload.self)
                decryptedPayload.pinned = noteToSave.isPinned
                
                let encryptedIndexData = try CryptoHelper.encrypt(decryptedPayload, key: encryptionKey)
                searchIndex.encryptedIndexData = encryptedIndexData
            }

            try viewContext.save()
            
            // Refresh the index to reflect the pin status change
            noteIndexViewModel.refreshIndex(from: viewContext)
            
            SyncService.shared.upload(notes: Array(allNotes))
        } catch {
            let nsError = error as NSError
            errorManager.handleCoreDataError(nsError, context: "Failed to update note pin status or search index")
        }
    }

    
    private func createLink() {
        guard let editorCoordinator = editorCoordinator else { return }
        editorCoordinator.createLink(displayLabel: linkDisplayLabel, url: linkURL)
        
        // Clear the input fields
        linkDisplayLabel = ""
        linkURL = ""
    }
    
    private func exportNoteAndPresentShare() {
        guard let generated = generateHTMLTempFile() else { return }
        // Present standard iOS share sheet with a real file URL
        presentShareSheet(for: generated.url)
    }

    private func generateHTMLTempFile() -> (url: URL, data: Data, name: String)? {
        let content = noteBody
        guard content.length > 0 else { return nil }
        do {
            let htmlData = try content.data(
                from: NSRange(location: 0, length: content.length),
                documentAttributes: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
                ]
            )
            let fileNameBase = (title.isEmpty ? "Note" : title)
                .replacingOccurrences(of: "[\\/:\n\r\t]+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let suggestedName = "\(fileNameBase.isEmpty ? "Note" : fileNameBase).html"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
            // Write the HTML Data directly to preserve encoding and formatting
            try htmlData.write(to: tempURL, options: .atomic)
            return (tempURL, htmlData, suggestedName)
        } catch {
            errorManager.handleError(error, context: "Failed to export note as HTML")
            return nil
        }
    }

    private func presentShareSheet(for url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = UIApplication.shared.windows.first { $0.isKeyWindow }
            if let sourceView = popover.sourceView {
                popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        topViewController()?.present(activityVC, animated: true)
    }

    private func topViewController(base: UIViewController? = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.keyWindow }
        .first?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }

    // MARK: - Attachments Helpers
    private func thumbnailImage(for attachment: Attachment) -> UIImage? {
        guard let id = attachment.id else { return nil }
        return videoThumbnails[id]
    }

    private func ensureThumbnail(for attachment: Attachment) {
        guard let id = attachment.id else { return }
        // Avoid regenerating
        if videoThumbnails[id] != nil || generatingThumbnailIDs.contains(id) { return }
        // Defer state mutation to avoid publishing during view updates
        DispatchQueue.main.async {
            self.generatingThumbnailIDs.insert(id)
        }

        // Capture path info on main thread to avoid Core Data threading issues
        let relativePath = attachment.relativePath

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let relativePath = relativePath,
                      let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    throw DecryptedAssetError.fileNotFound
                }

                let encryptedURL = appSupport.appendingPathComponent(relativePath)
                guard FileManager.default.fileExists(atPath: encryptedURL.path) else {
                    throw DecryptedAssetError.fileNotFound
                }

                let key = try KeyManager.shared.getEncryptionKey()
                let asset = DecryptedAsset(encryptedFileURL: encryptedURL, key: key)

                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                // Try a small offset to avoid black first frame
                let time = CMTime(seconds: 0.1, preferredTimescale: 600)
                var actualTime = CMTime.zero
                let cgImage = try generator.copyCGImage(at: time, actualTime: &actualTime)
                let image = UIImage(cgImage: cgImage)

                DispatchQueue.main.async {
                    self.videoThumbnails[id] = image
                    self.generatingThumbnailIDs.remove(id)
                }
            } catch {
                DispatchQueue.main.async {
                    self.generatingThumbnailIDs.remove(id)
                    // Non-critical: log only, avoid presenting alerts during view updates
                    ErrorManager.shared.log(error, context: "Generating video thumbnail")
                }
            }
        }
    }

    private func handlePickedVideo(url: URL) {
        guard let note = note else { return }
        isEncryptingAttachment = true
        Task { @MainActor in
            do {
                // Call manager (runs on @MainActor)
                _ = try await AttachmentManager.createVideoAttachment(for: note, from: url, context: viewContext)
                // Save is done in manager, but ensure UI reflects changes
                attachmentsRefreshID = UUID()
                // Kick off thumbnails for new attachments
                if let newSet = note.attachments as? Set<Attachment> {
                    for att in newSet where (att.type ?? "").lowercased() == "video" {
                        ensureThumbnail(for: att)
                    }
                }
            } catch {
                ErrorManager.shared.handleError(error, context: "Attaching video")
            }
            isEncryptingAttachment = false
        }
    }
}

// MARK: - Attachment Video Row View
private struct AttachmentVideoRow: View {
    let attachment: Attachment
    let thumbnail: UIImage?
    let onAppear: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    if let thumbnail = thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                        ProgressView()
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.white)
                        .shadow(radius: 2)
                }
                .frame(width: 120, height: 68)
                .clipped()
                .cornerRadius(8)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Video")
                        .font(.headline)
                        .foregroundColor(.primary)
                    if let date = attachment.createdAt {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .onAppear(perform: onAppear)
    }
}

// Ensure Core Data Attachment works with `sheet(item:)`


// MARK: - UIKit/PhotosUI Wrappers
private struct VideoLibraryPicker: UIViewControllerRepresentable {
    typealias UIViewControllerType = PHPickerViewController
    var onComplete: (URL?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onComplete: (URL?) -> Void
        init(onComplete: @escaping (URL?) -> Void) { self.onComplete = onComplete }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let provider = results.first?.itemProvider else {
                picker.dismiss(animated: true) { self.onComplete(nil) }
                return
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    var exportedURL: URL? = nil
                    if let error = error {
                        ErrorManager.shared.log(error, context: "Picking video from library")
                    } else if let srcURL = url {
                        // Copy to a stable temp location before dismissing the picker
                        let tmpDir = FileManager.default.temporaryDirectory
                        let ext = srcURL.pathExtension.isEmpty ? "mov" : srcURL.pathExtension
                        let dstURL = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                        do {
                            // Remove if exists (unlikely)
                            try? FileManager.default.removeItem(at: dstURL)
                            try FileManager.default.copyItem(at: srcURL, to: dstURL)
                            exportedURL = dstURL
                        } catch {
                            ErrorManager.shared.log(error, context: "Copying picked video to temp")
                        }
                    }
                    DispatchQueue.main.async {
                        picker.dismiss(animated: true) { self.onComplete(exportedURL) }
                    }
                }
            } else {
                picker.dismiss(animated: true) { self.onComplete(nil) }
            }
        }
    }
}

private struct VideoCameraPicker: UIViewControllerRepresentable {
    typealias UIViewControllerType = UIImagePickerController
    var onComplete: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoQuality = .typeMedium
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onComplete: onComplete) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onComplete: (URL?) -> Void
        init(onComplete: @escaping (URL?) -> Void) { self.onComplete = onComplete }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true) { self.onComplete(nil) }
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            var outputURL: URL? = nil
            if let srcURL = info[.mediaURL] as? URL {
                // Copy to a stable temp location before dismissing
                let tmpDir = FileManager.default.temporaryDirectory
                let ext = srcURL.pathExtension.isEmpty ? "mov" : srcURL.pathExtension
                let dstURL = tmpDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
                do {
                    try? FileManager.default.removeItem(at: dstURL)
                    try FileManager.default.copyItem(at: srcURL, to: dstURL)
                    outputURL = dstURL
                } catch {
                    ErrorManager.shared.log(error, context: "Copying recorded video to temp")
                }
            }
            picker.dismiss(animated: true) { self.onComplete(outputURL) }
        }
    }
}

// MARK: - UIActivityItemSource for HTML files
// No custom UIActivityItemSource; using the file URL directly yields the broadest set of system share targets

// MARK: - Formatting Bar (visual only)

extension NoteEditView {
    private var contentHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
            formattingBar
        }
    }

    private var formattingBar: some View {
        HStack(spacing: 8) {
            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleBold()
                }
            }) {
                Image(systemName: "bold")
                    .imageScale(.medium)
                    .accessibilityLabel("Bold")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isBold))

            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleItalic()
                }
            }) {
                Image(systemName: "italic")
                    .imageScale(.medium)
                    .accessibilityLabel("Italic")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isItalic))

            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleUnderline()
                }
            }) {
                Image(systemName: "underline")
                    .imageScale(.medium)
                    .accessibilityLabel("Underline")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isUnderlined))

            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleStrikethrough()
                }
            }) {
                Image(systemName: "strikethrough")
                    .imageScale(.medium)
                    .accessibilityLabel("Strikethrough")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isStrikethrough))
            
            // Header dropdown menu
            Menu {
                Button(action: {
                    if #available(iOS 15.0, *) {
                        editorCoordinator?.toggleHeader1()
                    }
                }) {
                    HStack {
                        Text("H1")
                        Spacer()
                        if isH1 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Button(action: {
                    if #available(iOS 15.0, *) {
                        editorCoordinator?.toggleHeader2()
                    }
                }) {
                    HStack {
                        Text("H2")
                        Spacer()
                        if isH2 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Button(action: {
                    if #available(iOS 15.0, *) {
                        editorCoordinator?.toggleHeader3()
                    }
                }) {
                    HStack {
                        Text("H3")
                        Spacer()
                        if isH3 {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            } label: {
                Text("H")
                    .font(.system(size: 16, weight: .medium))
                    .accessibilityLabel("Headers")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isH1 || isH2 || isH3))
            
            // Link button
            Button(action: {
                // Set display label to selected text if any
                if let editorCoordinator = editorCoordinator {
                    linkDisplayLabel = editorCoordinator.getSelectedText()
                }
                showLinkDialog = true
            }) {
                Image(systemName: "link")
                    .imageScale(.medium)
                    .accessibilityLabel("Link")
            }
            .buttonStyle(FormattingButtonStyle(isActive: false))
            
            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleBulletList()
                }
            }) {
                Image(systemName: "list.bullet")
                    .imageScale(.medium)
                    .accessibilityLabel("Bullet List")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isBulletList))

            Button(action: {
                if #available(iOS 15.0, *) {
                    editorCoordinator?.toggleNumberedList()
                }
            }) {
                Image(systemName: "list.number")
                    .imageScale(.medium)
                    .accessibilityLabel("Numbered List")
            }
            .buttonStyle(FormattingButtonStyle(isActive: isNumberedList))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.gray.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Share Sheet Wrapper + Custom Button Styles

// Simple UIKit share sheet wrapper
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

struct FormattingButtonStyle: ButtonStyle {
    let isActive: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(isActive ? .primary : .secondary)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor(isActive: isActive, isPressed: configuration.isPressed))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(borderColor(isActive: isActive, isPressed: configuration.isPressed), lineWidth: 1)
                    )
                    .shadow(
                        color: shadowColor(isActive: isActive, isPressed: configuration.isPressed),
                        radius: shadowRadius(isActive: isActive, isPressed: configuration.isPressed),
                        x: 0,
                        y: shadowOffset(isActive: isActive, isPressed: configuration.isPressed)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isActive)
    }
    
    private func backgroundColor(isActive: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return isActive ? Color.blue.opacity(0.2) : Color.gray.opacity(0.15)
        } else if isActive {
            return Color.blue.opacity(0.15)
        } else {
            return Color(UIColor.systemBackground)
        }
    }
    
    private func borderColor(isActive: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return isActive ? Color.blue.opacity(0.4) : Color.gray.opacity(0.4)
        } else if isActive {
            return Color.blue.opacity(0.3)
        } else {
            return Color.gray.opacity(0.3)
        }
    }
    
    private func shadowColor(isActive: Bool, isPressed: Bool) -> Color {
        if isPressed {
            return Color.clear
        } else {
            return Color.black.opacity(0.1)
        }
    }
    
    private func shadowRadius(isActive: Bool, isPressed: Bool) -> CGFloat {
        return isPressed ? 0 : 1
    }
    
    private func shadowOffset(isActive: Bool, isPressed: Bool) -> CGFloat {
        return isPressed ? 0 : 1
    }
}

// MARK: - RichTextEditorWrapper

@available(iOS 15.0, *)
struct RichTextEditorWrapper: UIViewRepresentable {
    @Binding var attributedText: NSAttributedString
    @Binding var coordinator: RichTextEditor.Coordinator?
    @Binding var isBold: Bool
    @Binding var isItalic: Bool
    @Binding var isUnderlined: Bool
    @Binding var isStrikethrough: Bool
    @Binding var isBulletList: Bool
    @Binding var isNumberedList: Bool
    @Binding var isH1: Bool
    @Binding var isH2: Bool
    @Binding var isH3: Bool
    
    func makeCoordinator() -> RichTextEditor.Coordinator {
        let coord = RichTextEditor.Coordinator()
        DispatchQueue.main.async {
            coordinator = coord
        }
        return coord
    }
    
    func makeUIView(context: Context) -> RichTextEditorView {
        let editorView = RichTextEditorView()
        editorView.onTextChange = { newAttributedText in
            DispatchQueue.main.async {
                attributedText = newAttributedText
            }
        }
        
        editorView.onFormattingChange = { bold, italic, underlined, strikethrough, bulletList, numberedList, h1, h2, h3 in
            DispatchQueue.main.async {
                isBold = bold
                isItalic = italic
                isUnderlined = underlined
                isStrikethrough = strikethrough
                isBulletList = bulletList
                isNumberedList = numberedList
                isH1 = h1
                isH2 = h2
                isH3 = h3
            }
        }
        
        // Store reference in coordinator for formatting methods
        context.coordinator.editorView = editorView
        
        return editorView
    }
    
    func updateUIView(_ uiView: RichTextEditorView, context: Context) {
        let currentText = uiView.getAttributedText()
        if !currentText.isEqual(to: attributedText) {
            uiView.setAttributedText(attributedText)
        }
    }
}
