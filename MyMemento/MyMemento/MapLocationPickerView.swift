import SwiftUI
import MapKit
import CoreData

struct MapLocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let viewContext: NSManagedObjectContext
    let onLocationSelected: (Location) -> Void
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco default
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var cameraPosition = MapCameraPosition.region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectedPlacemark: CLPlacemark?
    @State private var isLoadingLocation = false
    @State private var showingNameDialog = false
    @State private var locationName = ""
    @State private var errorMessage: String?
    @State private var locationManager: LocationManager?
    @State private var addressSearchText = ""
    @State private var isSearching = false
    @State private var mapRefreshTrigger = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack {
                // Address Search Input
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
                .zIndex(1)
                
                // Map View with crosshair
                ZStack {
                    if #available(iOS 17.0, *) {
                        Map(position: $cameraPosition) {
                            if let coordinate = selectedCoordinate {
                                Marker("", coordinate: coordinate)
                                    .tint(.red)
                            }
                        }
                        .id(mapRefreshTrigger)
                    } else {
                        Map(coordinateRegion: $region, annotationItems: selectedCoordinate.map { [MapAnnotation(coordinate: $0)] } ?? []) { annotation in
                            MapPin(coordinate: annotation.coordinate, tint: .red)
                        }
                        .id(mapRefreshTrigger)
                    }
                    
                    // Crosshair in center
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white).frame(width: 30, height: 30))
                        .shadow(radius: 2)
                    
                    // Select center location button
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button(action: {
                                handleMapTap(at: region.center, screenLocation: .zero)
                            }) {
                                HStack {
                                    Image(systemName: "location.fill")
                                    Text("Select This Location")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                                .shadow(radius: 2)
                            }
                            .padding(.trailing)
                            .padding(.bottom, 8)
                        }
                    }
                }
                .frame(height: 350)
                
                // Instructions
                VStack(spacing: 12) {
                    if selectedCoordinate != nil {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "location.fill")
                                    .foregroundColor(.blue)
                                Text("Location Selected")
                                    .font(.headline)
                                Spacer()
                            }
                            
                            if let placemark = selectedPlacemark {
                                Text(formatPlacemark(placemark))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(formatCoordinate(selectedCoordinate!))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    } else {
                        Text("Search for an address or pan the map, then use the crosshair to select a location")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    Spacer()
                }
                .padding()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Select Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Use Location") {
                        if selectedCoordinate != nil {
                            showingNameDialog = true
                        }
                    }
                    .disabled(selectedCoordinate == nil)
                }
            }
        }
        .onAppear {
            setupLocationManager()
            requestUserLocation()
        }
        .alert("Name This Location", isPresented: $showingNameDialog) {
            TextField("Enter location name", text: $locationName)
            Button("Save") {
                saveSelectedLocation()
            }
            .disabled(locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {
                locationName = ""
            }
        } message: {
            Text("Give this location a memorable name")
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
    
    private func setupLocationManager() {
        locationManager = LocationManager(context: viewContext, keyManager: KeyManager.shared)
    }
    
    private func requestUserLocation() {
        let locationManager = CLLocationManager()
        locationManager.requestWhenInUseAuthorization()
        
        if let userLocation = locationManager.location {
            let newRegion = MKCoordinateRegion(
                center: userLocation.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            region = newRegion
            cameraPosition = .region(newRegion)
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
                    self.errorMessage = "Location search failed: \(error.localizedDescription)"
                    return
                }
                
                guard let placemark = placemarks?.first,
                      let location = placemark.location else {
                    self.errorMessage = "No results found for '\(searchText)'"
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
        errorMessage = nil
        
        // Center map on the found location with animation
        let newRegion = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
        withAnimation(.easeInOut(duration: 1.0)) {
            region = newRegion
            cameraPosition = .region(newRegion)
        }
        
        // Auto-select this location
        selectedCoordinate = coordinate
        selectedPlacemark = placemark
        
        // Force map refresh after a small delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            mapRefreshTrigger.toggle()
        }
        
        // Clear the search text
        addressSearchText = ""
        
        print("Found location: \(placemark.name ?? "Unknown") at \(coordinate)")
    }
    
    private func handleMapTap(at coordinate: CLLocationCoordinate2D, screenLocation: CGPoint) {
        selectedCoordinate = coordinate
        selectedPlacemark = nil
        
        // Reverse geocode to get address information
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        isLoadingLocation = true
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                isLoadingLocation = false
                if let placemark = placemarks?.first {
                    selectedPlacemark = placemark
                    // Auto-suggest a name based on the address
                    if let name = placemark.name ?? placemark.thoroughfare {
                        locationName = name
                    }
                }
            }
        }
    }
    
    private func saveSelectedLocation() {
        guard let coordinate = selectedCoordinate,
              let locationManager = locationManager else {
            return
        }
        
        let trimmedName = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Please enter a location name"
            return
        }
        
        Task {
            do {
                let savedLocation = try locationManager.saveLocation(
                    name: trimmedName,
                    coordinate: coordinate,
                    placemark: selectedPlacemark
                )
                
                await MainActor.run {
                    onLocationSelected(savedLocation)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save location: \\(error.localizedDescription)"
                }
            }
        }
    }
    
    private func formatPlacemark(_ placemark: CLPlacemark) -> String {
        var components: [String] = []
        
        if let name = placemark.name {
            components.append(name)
        }
        if let locality = placemark.locality {
            components.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            components.append(administrativeArea)
        }
        
        return components.isEmpty ? formatCoordinate(CLLocationCoordinate2D(latitude: placemark.location?.coordinate.latitude ?? 0, longitude: placemark.location?.coordinate.longitude ?? 0)) : components.joined(separator: ", ")
    }
    
    private func formatCoordinate(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
}

// Helper struct for map annotations
struct MapAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    MapLocationPickerView(
        viewContext: PersistenceController.preview.container.viewContext,
        onLocationSelected: { _ in }
    )
}