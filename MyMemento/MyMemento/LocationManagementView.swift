//
//  LocationManagementView.swift
//  MyMemento
//
//  Created by Claude on 9/20/25.
//

import SwiftUI
import CoreData
import CoreLocation

struct LocationManagementView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var locations: [Location] = []
    @State private var locationToDelete: Location?
    @State private var showDeleteConfirmation = false
    @State private var deleteWarningMessage = ""
    @State private var isLoading = true
    @State private var selectedLocationForDetail: Location?
    @State private var refreshTrigger = false
    
    var filteredLocations: [Location] {
        if searchText.isEmpty {
            return locations
        } else {
            return locations.filter { location in
                location.name?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Search input
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search locations...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .padding(.horizontal)
                .padding(.top)
                
                if isLoading {
                    ProgressView("Loading locations...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredLocations.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "location.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text(searchText.isEmpty ? "No locations saved" : "No locations match your search")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        if searchText.isEmpty {
                            Text("Locations are saved when you add them to notes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Locations list
                    List {
                        ForEach(filteredLocations, id: \.id) { location in
                            LocationRowView(location: location)
                                .id("\(location.id?.uuidString ?? "")-\(refreshTrigger)")
                                .onTapGesture {
                                    selectedLocationForDetail = location
                                }
                        }
                        .onDelete(perform: deleteLocations)
                    }
                }
            }
            .navigationTitle("Manage Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadLocations()
            }
            .alert("Delete Location", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let location = locationToDelete {
                        performDelete(location: location)
                    }
                }
            } message: {
                Text(deleteWarningMessage)
            }
            .sheet(item: $selectedLocationForDetail) { location in
                LocationDetailView(
                    location: location,
                    viewContext: viewContext,
                    onLocationSelected: { _ in
                        selectedLocationForDetail = nil
                    }
                )
                .onDisappear {
                    // Force UI refresh by toggling the refresh trigger
                    refreshTrigger.toggle()
                }
            }
        }
    }
    
    private func loadLocations() {
        Task {
            do {
                let locationManager = LocationManager(context: viewContext, keyManager: KeyManager.shared)
                let fetchedLocations = try locationManager.fetchAllLocations()
                
                await MainActor.run {
                    self.locations = fetchedLocations
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    ErrorManager.shared.handleError(error, context: "Loading locations")
                }
            }
        }
    }
    
    private func deleteLocations(offsets: IndexSet) {
        for index in offsets {
            let location = filteredLocations[index]
            checkLocationUsageAndDelete(location: location)
        }
    }
    
    private func checkLocationUsageAndDelete(location: Location) {
        // Check if location is referenced by any attachments
        let fetchRequest: NSFetchRequest<Attachment> = Attachment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "location == %@", location)
        
        do {
            let attachments = try viewContext.fetch(fetchRequest)
            if attachments.isEmpty {
                // No attachments reference this location, safe to delete
                performDelete(location: location)
            } else {
                // Location is in use, show confirmation dialog
                let noteCount = Set(attachments.compactMap { $0.note?.id }).count
                locationToDelete = location
                deleteWarningMessage = "This location is attached to \(noteCount) note\(noteCount == 1 ? "" : "s"). Deleting it will remove the location from \(noteCount == 1 ? "that note" : "those notes"). This action cannot be undone."
                showDeleteConfirmation = true
            }
        } catch {
            ErrorManager.shared.handleError(error, context: "Checking location usage")
        }
    }
    
    private func performDelete(location: Location) {
        Task {
            do {
                // First, delete all attachments that reference this location
                let fetchRequest: NSFetchRequest<Attachment> = Attachment.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "location == %@", location)
                let attachments = try viewContext.fetch(fetchRequest)
                
                for attachment in attachments {
                    viewContext.delete(attachment)
                }
                
                // Then delete the location itself
                let locationManager = LocationManager(context: viewContext, keyManager: KeyManager.shared)
                try locationManager.deleteLocation(location)
                
                // Remove from local array
                await MainActor.run {
                    if let index = locations.firstIndex(where: { $0.id == location.id }) {
                        locations.remove(at: index)
                    }
                    locationToDelete = nil
                }
                
                print("Successfully deleted location: \(location.name ?? "unknown")")
                
            } catch {
                await MainActor.run {
                    ErrorManager.shared.handleError(error, context: "Deleting location")
                    locationToDelete = nil
                }
            }
        }
    }
}

// MARK: - Location Row View
private struct LocationRowView: View {
    let location: Location
    @Environment(\.managedObjectContext) private var viewContext
    @State private var formattedAddress = "Loading address..."
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "location.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name ?? "Unnamed Location")
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(formattedAddress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(location.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? "")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text("\(location.latitude, specifier: "%.6f"), \(location.longitude, specifier: "%.6f")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            loadFormattedAddress()
        }
    }
    
    private func loadFormattedAddress() {
        Task {
            do {
                let locationManager = LocationManager(context: viewContext, keyManager: KeyManager.shared)
                let address = try locationManager.formatAddress(from: location)
                
                await MainActor.run {
                    formattedAddress = address
                }
            } catch {
                await MainActor.run {
                    formattedAddress = "Address unavailable"
                }
            }
        }
    }
}