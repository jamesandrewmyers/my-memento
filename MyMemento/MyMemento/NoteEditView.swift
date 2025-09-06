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
    @State private var showEncryptedExport = false
    
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteAttachment(attachment)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
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
                Menu {
                    Button(action: exportNoteAndPresentShare) {
                        Label("Export as HTML", systemImage: "doc.text")
                    }
                    Button(action: exportNoteWithLocalKeyAndPresentShare) {
                        Label("Export (Local Key)", systemImage: "lock.app.dashed")
                    }
                    Button(action: { showEncryptedExport = true }) {
                        Label("Encrypted Export", systemImage: "lock.doc")
                    }
                } label: {
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
        // Encrypted Export Sheet
        .sheet(isPresented: $showEncryptedExport) {
            if let note = note {
                EncryptedExportView(note: note)
            }
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

    private func exportNoteWithLocalKeyAndPresentShare() {
        guard let note else { 
            print("Export: No note available for export")
            return 
        }
        
        print("Export: Starting local key export for note \(note.id?.uuidString ?? "unknown")")
        
        Task {
            do {
                print("Export: Calling ExportManager.shared.exportWithLocalKey")
                let url = try await ExportManager.shared.exportWithLocalKey(note: note)
                print("Export: Successfully exported to \(url.path)")
                
                // Verify the file exists before sharing
                if FileManager.default.fileExists(atPath: url.path) {
                    print("Export: File exists at \(url.path), presenting share sheet")
                    // Ensure UI updates happen on main thread
                    DispatchQueue.main.async {
                        self.presentShareSheet(for: url)
                    }
                } else {
                    print("Export: ERROR - File does not exist at \(url.path)")
                    DispatchQueue.main.async {
                        self.errorManager.handleError(ExportError.finalPackagingFailed, context: "Export file was not created")
                    }
                }
            } catch {
                print("Export: ERROR - \(error)")
                // Ensure error handling happens on main thread
                DispatchQueue.main.async {
                    self.errorManager.handleError(error, context: "Failed to export note with local key")
                }
            }
        }
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
        print("ShareSheet: Preparing to present share sheet for \(url.path)")
        print("ShareSheet: File extension is: \(url.pathExtension)")
        // Get file size for logging
        do {
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber ?? 0
            print("ShareSheet: File size: \(fileSize) bytes")
        } catch {
            print("ShareSheet: Could not get file size: \(error)")
        }
        
        // For maximum compatibility, share the file URL directly without custom wrappers
        // The file should already have a safe extension (.zip) from ExportManager
        print("ShareSheet: Using file URL directly for maximum compatibility")
        
        print("ShareSheet: Creating UIActivityViewController with direct file URL")
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        // Debug: Log all available activities
        print("ShareSheet: Available activities will be determined by iOS...")
        
        // Don't exclude any activities to see what's available
        activityVC.excludedActivityTypes = []
        print("ShareSheet: Set excludedActivityTypes to empty array to see all options")
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = UIApplication.shared.windows.first { $0.isKeyWindow }
            if let sourceView = popover.sourceView {
                popover.sourceRect = CGRect(x: sourceView.bounds.midX, y: sourceView.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        print("ShareSheet: Getting top view controller")
        guard let topVC = topViewController() else {
            print("ShareSheet: ERROR - No top view controller found")
            return
        }
        
        print("ShareSheet: Presenting activity view controller")
        topVC.present(activityVC, animated: true) {
            print("ShareSheet: Activity view controller presented successfully")
        }
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

    private func deleteAttachment(_ attachment: Attachment) {
        guard let id = attachment.id else { return }
        Task { @MainActor in
            do {
                try await AttachmentManager.deleteAttachment(attachment, context: viewContext)
                // Update UI caches and refresh the section
                videoThumbnails.removeValue(forKey: id)
                generatingThumbnailIDs.remove(id)
                attachmentsRefreshID = UUID()
            } catch {
                ErrorManager.shared.handleError(error, context: "Deleting attachment")
            }
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

// MARK: - UIActivityItemSource for sharing files
class ShareableFileItem: NSObject, UIActivityItemSource {
    let url: URL
    let filename: String
    
    init(url: URL, filename: String) {
        self.url = url
        self.filename = filename
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return url
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        if url.pathExtension == "memento" && activityType?.rawValue.contains("mail") == true {
            // Create a temporary copy with .txt extension for Gmail compatibility testing
            let tempURL = createTempFileForEmail()
            return tempURL ?? url
        }
        return url
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        let baseFilename = (filename as NSString).deletingPathExtension
        return "MyMemento Export: \(baseFilename)"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        if url.pathExtension == "memento" {
            // Use generic binary data UTI for better email client compatibility
            return "public.data"
        }
        return "public.item"
    }
    

    
    private func createTempFileForEmail() -> URL? {
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let tempFileName = "\((filename as NSString).deletingPathExtension).txt"
            let tempURL = tempDir.appendingPathComponent(tempFileName)
            
            // Remove if it exists
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            
            // Copy the file with .txt extension
            try FileManager.default.copyItem(at: url, to: tempURL)
            print("ShareSheet: Created temp file for email: \(tempURL.path)")
            return tempURL
        } catch {
            print("ShareSheet: Failed to create temp file for email: \(error)")
            return nil
        }
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        // Provide a custom icon for .memento files to help with recognition
        return UIImage(systemName: "doc.badge.gearshape.fill")
    }
}

// MARK: - AdaptiveShareItem that chooses the best approach per app

class AdaptiveShareItem: NSObject, UIActivityItemSource {
    let url: URL
    let data: Data
    let filename: String
    
    init(url: URL, data: Data, filename: String) {
        self.url = url
        self.data = data
        self.filename = filename
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return data // Use data as placeholder
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        guard let activityType = activityType else {
            print("ShareSheet: No activity type, using data")
            return data
        }
        
        print("ShareSheet: Activity type: \(activityType.rawValue)")
        
        // For mail apps (Gmail, Apple Mail, etc), use data to avoid file system issues
        if activityType.rawValue.contains("mail") || activityType.rawValue.contains("gmail") {
            print("ShareSheet: Using data for mail app (\(data.count) bytes)")
            return data
        }
        
        // For file-based apps (Files app, cloud storage), use file URL
        if activityType.rawValue.contains("files") || activityType.rawValue.contains("document") || 
           activityType.rawValue.contains("dropbox") || activityType.rawValue.contains("drive") {
            print("ShareSheet: Using file URL for file-based app")
            return url
        }
        
        // For messaging apps, try data first
        if activityType.rawValue.contains("message") || activityType.rawValue.contains("whatsapp") ||
           activityType.rawValue.contains("telegram") || activityType.rawValue.contains("signal") {
            print("ShareSheet: Using data for messaging app (\(data.count) bytes)")
            return data
        }
        
        // Default to data for unknown apps to avoid file system issues
        print("ShareSheet: Using data for unknown app type (\(data.count) bytes)")
        return data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        let baseFilename = (filename as NSString).deletingPathExtension
        return "MyMemento Export: \(baseFilename)"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        // Always use generic binary data UTI for maximum compatibility
        return "public.data"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        return UIImage(systemName: "doc.badge.gearshape.fill")
    }
}

// MARK: - ShareableDataItem for data-based sharing

class ShareableDataItem: NSObject, UIActivityItemSource {
    let data: Data
    let filename: String
    
    init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        // For mail apps, provide the data directly
        if activityType?.rawValue.contains("mail") == true {
            print("ShareSheet: Providing data directly for mail app (\(data.count) bytes)")
            return data
        }
        // For other apps, also provide data
        return data
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        let baseFilename = (filename as NSString).deletingPathExtension
        return "MyMemento Export: \(baseFilename)"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        // Use application/octet-stream for binary data
        return "public.data"
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, thumbnailImageForActivityType activityType: UIActivity.ActivityType?, suggestedSize size: CGSize) -> UIImage? {
        return UIImage(systemName: "doc.badge.gearshape.fill")
    }
}

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
