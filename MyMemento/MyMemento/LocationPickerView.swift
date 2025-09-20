import SwiftUI
import CoreData
import MapKit

struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let viewContext: NSManagedObjectContext
    let onLocationSelected: (Location) -> Void
    
    @State private var searchText = ""
    @State private var locations: [Location] = []
    @State private var filteredLocations: [Location] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var locationManager: LocationManager?
    @State private var showingMapPicker = false
    @State private var selectedLocationForDetail: Location?
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading locations...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if locations.isEmpty {
                    VStack(spacing: 16) {
                        // Find Location option
                        Button(action: {
                            showingMapPicker = true
                        }) {
                            HStack {
                                Image(systemName: "map.fill")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                                    .frame(width: 40)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Find Location")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("Use map to select a new location")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        
                        Spacer().frame(height: 20)
                        
                        Image(systemName: "location.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Saved Locations")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Use the Find Location option above or save locations elsewhere in the app to attach them to notes.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // Find Location option at the top
                        Button(action: {
                            showingMapPicker = true
                        }) {
                            HStack {
                                Image(systemName: "map.fill")
                                    .foregroundColor(.blue)
                                    .font(.title2)
                                    .frame(width: 40)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Find Location")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("Use map to select a new location")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        
                        // Existing locations
                        ForEach(filteredLocations, id: \.id) { location in
                            LocationRow(location: location, locationManager: locationManager) {
                                selectedLocationForDetail = location
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search locations...")
                    .onChange(of: searchText) { _, newValue in
                        filterLocations()
                    }
                }
            }
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
        .sheet(isPresented: $showingMapPicker) {
            MapLocationPickerView(viewContext: viewContext) { selectedLocation in
                onLocationSelected(selectedLocation)
                dismiss()
            }
        }
        .sheet(item: $selectedLocationForDetail) { location in
            LocationDetailView(location: location, viewContext: viewContext) { selectedLocation in
                onLocationSelected(selectedLocation)
                dismiss()
            }
        }
        .onAppear {
            setupLocationManager()
            loadLocations()
        }
    }
    
    private func setupLocationManager() {
        locationManager = LocationManager(context: viewContext, keyManager: KeyManager.shared)
    }
    
    private func loadLocations() {
        guard let locationManager = locationManager else { return }
        
        Task {
            do {
                let fetchedLocations = try locationManager.fetchAllLocations()
                await MainActor.run {
                    self.locations = fetchedLocations
                    self.filteredLocations = fetchedLocations
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load locations: \\(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func filterLocations() {
        if searchText.isEmpty {
            filteredLocations = locations
        } else {
            filteredLocations = locations.filter { location in
                (location.name ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

struct LocationRow: View {
    let location: Location
    let locationManager: LocationManager?
    let onTap: () -> Void
    
    @State private var formattedAddress: String = ""
    @State private var isLoadingAddress = true
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(location.name ?? "Unnamed Location")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    
                    if isLoadingAddress {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading address...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text(formattedAddress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Text("\(String(format: "%.6f", location.latitude)), \(String(format: "%.6f", location.longitude))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadFormattedAddress()
        }
    }
    
    private func loadFormattedAddress() {
        guard let locationManager = locationManager else {
            formattedAddress = String(format: "%.6f, %.6f", location.latitude, location.longitude)
            isLoadingAddress = false
            return
        }
        
        Task {
            do {
                let address = try locationManager.formatAddress(from: location)
                await MainActor.run {
                    self.formattedAddress = address
                    self.isLoadingAddress = false
                }
            } catch {
                await MainActor.run {
                    self.formattedAddress = String(format: "%.6f, %.6f", location.latitude, location.longitude)
                    self.isLoadingAddress = false
                }
            }
        }
    }
}



#Preview {
    LocationPickerView(
        viewContext: PersistenceController.preview.container.viewContext,
        onLocationSelected: { _ in }
    )
}