import SwiftUI
import MapKit
import CoreData

struct LocationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var noteIndexViewModel: NoteIndexViewModel
    let location: Location
    let viewContext: NSManagedObjectContext
    let onLocationSelected: (Location) -> Void
    
    @State private var region: MKCoordinateRegion
    @State private var cameraPosition: MapCameraPosition
    @State private var locationManager: LocationManager?
    @State private var formattedAddress = "Loading address..."
    @State private var isLoadingAddress = true
    @State private var notesWithLocation: [IndexPayload] = []
    @State private var addressSearchText = ""
    @State private var isSearching = false
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPlacemark: CLPlacemark?
    @State private var showLocationChangeDialog = false
    @State private var newLocationName = ""
    @State private var mapRefreshTrigger = false
    @State private var displayLocationName: String = ""
    
    init(location: Location, viewContext: NSManagedObjectContext, onLocationSelected: @escaping (Location) -> Void) {
        self.location = location
        self.viewContext = viewContext
        self.onLocationSelected = onLocationSelected
        
        // Initialize region centered on the location
        let center = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        self._region = State(initialValue: MKCoordinateRegion(center: center, span: span))
        self._cameraPosition = State(initialValue: .region(MKCoordinateRegion(center: center, span: span)))
    }
    
    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    contentView
                        .navigationDestination(for: IndexPayload.self) { indexPayload in
                            NoteEditView(indexPayload: indexPayload)
                                .onDisappear {
                                    noteIndexViewModel.refreshIndex(from: viewContext)
                                    loadNotesWithLocation()
                                }
                        }
                }
            } else {
                NavigationView {
                    contentView
                        .navigationDestination(for: IndexPayload.self) { indexPayload in
                            NoteEditView(indexPayload: indexPayload)
                                .onDisappear {
                                    noteIndexViewModel.refreshIndex(from: viewContext)
                                    loadNotesWithLocation()
                                }
                        }
                }
            }
        }
        .onAppear {
            displayLocationName = location.name ?? "Unnamed Location"
            setupLocationManager()
            loadFormattedAddress()
            loadNotesWithLocation()
        }
        .alert("Change Location", isPresented: $showLocationChangeDialog) {
            Button("Keep \"\(displayLocationName)\"") {
                updateLocationCoordinates(keepCurrentLabel: true)
            }
            Button("Change") {
                updateLocationCoordinates(keepCurrentLabel: false)
            }
            Button("Cancel", role: .cancel) {
                selectedCoordinate = nil
                selectedPlacemark = nil
            }
        } message: {
            Text("Current Label: \(displayLocationName)\n\nNew Address: \(newLocationName)\n\n\"Keep\" preserves the current label with new coordinates. \"Change\" updates both label and coordinates.")
        }
    }
    
    private var contentView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Address Search Input - Fixed at top
                HStack {
                    TextField("Search for places, businesses, or addresses...", text: $addressSearchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onSubmit {
                            searchForAddress()
                        }
                    
                    Button(action: searchForAddress) {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    .disabled(addressSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                
                // Interactive Map View
                VStack(spacing: 0) {
                    ZStack {
                        if #available(iOS 17.0, *) {
                            Map(position: $cameraPosition) {
                                Marker("", coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
                                    .tint(.blue)
                            }
                            .onMapCameraChange { context in
                                // Update region when camera changes
                                region = context.region
                            }
                            .onTapGesture(coordinateSpace: .local) { screenLocation in
                                handleMapTap(screenLocation: screenLocation)
                            }
                            .id(mapRefreshTrigger)
                        } else {
                            Map(coordinateRegion: $region, annotationItems: [LocationDetailMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))]) { annotation in
                                MapPin(coordinate: annotation.coordinate, tint: .blue)
                            }
                            .onTapGesture { screenLocation in
                                handleMapTap(screenLocation: screenLocation)
                            }
                            .id(mapRefreshTrigger)
                        }
                        
                        // Crosshair overlay to show tap target
                        if selectedCoordinate != nil {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Text("Tap to change location")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.black.opacity(0.7))
                                        .foregroundColor(.white)
                                        .cornerRadius(4)
                                        .padding(.trailing)
                                        .padding(.bottom, 8)
                                }
                            }
                        }
                    }
                    .frame(height: 250)
                    
                    // Location Info Summary
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(displayLocationName)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                if isLoadingAddress {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("Loading address...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else {
                                    Text(formattedAddress)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Text("\(notesWithLocation.count) note\(notesWithLocation.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(radius: 2)
                .padding()
                
                // Notes List with full functionality
                NoteListWithFiltersView.readOnly(
                    allIndices: notesWithLocation,
                    navigationTitle: "Notes with this location",
                    showSearch: true,
                    showSort: true
                )
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Location Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Select") {
                    onLocationSelected(location)
                    dismiss()
                }
            }
        }
    }
    
    private func setupLocationManager() {
        locationManager = LocationManager(context: viewContext, keyManager: KeyManager.shared)
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
    
    private func searchForAddress() {
        let searchText = addressSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        
        // Try MKLocalSearch first for points of interest and businesses
        searchWithMKLocalSearch(searchText) { [self] success in
            if !success {
                // Fall back to geocoding for traditional address searches
                searchWithGeocoding(searchText)
            }
        }
    }
    
    private func searchWithMKLocalSearch(_ searchText: String, completion: @escaping (Bool) -> Void) {
        let searchRequest = MKLocalSearch.Request()
        searchRequest.naturalLanguageQuery = searchText
        
        // Set search region to current map region for better local results
        searchRequest.region = region
        
        let search = MKLocalSearch(request: searchRequest)
        search.start { response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("MKLocalSearch failed: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                guard let response = response,
                      let firstItem = response.mapItems.first else {
                    print("No MKLocalSearch results found")
                    completion(false)
                    return
                }
                
                self.handleSearchSuccess(
                    coordinate: firstItem.placemark.coordinate,
                    placemark: firstItem.placemark,
                    searchText: searchText
                )
                completion(true)
            }
        }
    }
    
    private func searchWithGeocoding(_ searchText: String) {
        let geocoder = CLGeocoder()
        
        geocoder.geocodeAddressString(searchText) { placemarks, error in
            DispatchQueue.main.async {
                self.isSearching = false
                
                if let error = error {
                    print("Geocoding failed: \(error.localizedDescription)")
                    return
                }
                
                guard let placemark = placemarks?.first,
                      let location = placemark.location else {
                    print("No results found for '\(searchText)'")
                    return
                }
                
                self.handleSearchSuccess(
                    coordinate: location.coordinate,
                    placemark: placemark,
                    searchText: searchText
                )
            }
        }
    }
    
    private func handleSearchSuccess(coordinate: CLLocationCoordinate2D, placemark: CLPlacemark, searchText: String) {
        isSearching = false
        
        // Center map on the found location with animation
        let newRegion = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        withAnimation(.easeInOut(duration: 1.0)) {
            region = newRegion
            cameraPosition = .region(newRegion)
        }
        
        // Show location change confirmation
        selectedCoordinate = coordinate
        selectedPlacemark = placemark
        
        // Set suggested name from placemark
        if let name = placemark.name ?? placemark.thoroughfare {
            newLocationName = name
        } else {
            newLocationName = formatCoordinate(coordinate)
        }
        
        showLocationChangeDialog = true
        
        // Clear the search text
        addressSearchText = ""
        
        print("Found location: \(placemark.name ?? "Unknown") at \(coordinate)")
    }
    
    private func handleMapTap(screenLocation: CGPoint) {
        // For now, use region center as the tapped coordinate
        // In a real implementation, you'd convert screen coordinates to map coordinates
        let coordinate = region.center
        
        selectedCoordinate = coordinate
        selectedPlacemark = nil
        
        // Reverse geocode to get address information
        let geocoder = CLGeocoder()
        let tapLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(tapLocation) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    self.selectedPlacemark = placemark
                    // Auto-suggest a name based on the address
                    if let name = placemark.name ?? placemark.thoroughfare {
                        self.newLocationName = name
                    } else {
                        self.newLocationName = self.formatCoordinate(coordinate)
                    }
                } else {
                    self.newLocationName = self.formatCoordinate(coordinate)
                }
                
                self.showLocationChangeDialog = true
            }
        }
    }
    
    private func updateLocationCoordinates(keepCurrentLabel: Bool) {
        guard let coordinate = selectedCoordinate,
              let locationManager = locationManager else {
            return
        }
        
        Task {
            do {
                // Update the location's coordinates
                try locationManager.updateLocationCoordinate(location, to: coordinate)
                
                // Update label if requested
                if !keepCurrentLabel {
                    let trimmedName = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedName.isEmpty {
                        try locationManager.updateLocationName(location, to: trimmedName)
                        print("DEBUG: Updated location name to: \(trimmedName)")
                    }
                }
                
                // Update placemark data if available
                if let placemark = selectedPlacemark {
                    let placemarkPayload = LocationPlacemarkPayload(
                        thoroughfare: placemark.thoroughfare,
                        subThoroughfare: placemark.subThoroughfare,
                        locality: placemark.locality,
                        subLocality: placemark.subLocality,
                        administrativeArea: placemark.administrativeArea,
                        subAdministrativeArea: placemark.subAdministrativeArea,
                        postalCode: placemark.postalCode,
                        country: placemark.country,
                        countryCode: placemark.isoCountryCode,
                        timeZone: placemark.timeZone?.identifier
                    )
                    
                    // Encrypt and store placemark data
                    let encryptionKey = try KeyManager.shared.getEncryptionKey()
                    let encryptedPlacemarkData = try CryptoHelper.encrypt(placemarkPayload, key: encryptionKey)
                    location.encryptedPlacemarkData = encryptedPlacemarkData
                }
                
                try viewContext.save()
                
                // Refresh the Core Data object to ensure we have the latest data
                viewContext.refresh(location, mergeChanges: true)
                
                await MainActor.run {
                    // Update the view's region and camera to the new location
                    let newRegion = MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    )
                    self.region = newRegion
                    self.cameraPosition = .region(newRegion)
                    
                    // Refresh UI and update displayed name
                    if !keepCurrentLabel {
                        // Directly use the new name we just set
                        let trimmedName = self.newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.displayLocationName = trimmedName.isEmpty ? "Unnamed Location" : trimmedName
                        print("DEBUG: Display name updated to: \(self.displayLocationName)")
                    } else {
                        // Keep the current display name
                        print("DEBUG: Keeping current display name: \(self.displayLocationName)")
                    }
                    loadFormattedAddress()
                    mapRefreshTrigger.toggle()
                    
                    // Clear selection
                    selectedCoordinate = nil
                    selectedPlacemark = nil
                }
                
            } catch {
                await MainActor.run {
                    print("Failed to update location: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
    
    private func loadNotesWithLocation() {
        // Find all attachments that reference this location
        let fetchRequest: NSFetchRequest<Attachment> = Attachment.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "location == %@", location)
        
        do {
            let attachments = try viewContext.fetch(fetchRequest)
            let noteIds = Set(attachments.compactMap { $0.note?.id })
            
            // Filter noteIndexViewModel to only include notes with this location
            notesWithLocation = noteIndexViewModel.indexPayloads.filter { indexPayload in
                noteIds.contains(indexPayload.id)
            }.sorted { index1, index2 in
                // Sort by pinned status first, then by creation date
                if index1.pinned != index2.pinned {
                    return index1.pinned && !index2.pinned
                }
                return index1.createdAt > index2.createdAt
            }
        } catch {
            print("Error loading notes with location: \(error)")
            notesWithLocation = []
        }
    }
}

// Helper struct for map annotations
private struct LocationDetailMapAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    // Create a mock location for preview
    let context = PersistenceController.preview.container.viewContext
    let location = Location(context: context)
    location.id = UUID()
    location.name = "Sample Location"
    location.latitude = 37.7749
    location.longitude = -122.4194
    location.createdAt = Date()
    
    return LocationDetailView(
        location: location,
        viewContext: context,
        onLocationSelected: { _ in }
    )
}
