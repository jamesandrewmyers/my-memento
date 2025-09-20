import SwiftUI
import MapKit
import CoreData

struct LocationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let location: Location
    let viewContext: NSManagedObjectContext
    let onLocationSelected: (Location) -> Void
    
    @State private var region: MKCoordinateRegion
    @State private var cameraPosition: MapCameraPosition
    @State private var locationManager: LocationManager?
    @State private var formattedAddress = "Loading address..."
    @State private var isLoadingAddress = true
    
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
        NavigationView {
            VStack(spacing: 0) {
                // Map View
                if #available(iOS 17.0, *) {
                    Map(position: $cameraPosition) {
                        Marker("", coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))
                            .tint(.blue)
                    }
                    .frame(height: 300)
                } else {
                    Map(coordinateRegion: $region, annotationItems: [LocationDetailMapAnnotation(coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude))]) { annotation in
                        MapPin(coordinate: annotation.coordinate, tint: .blue)
                    }
                    .frame(height: 300)
                }
                
                // Location Details
                VStack(alignment: .leading, spacing: 16) {
                    // Location Name
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(location.name ?? "Unnamed Location")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            if isLoadingAddress {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading address...")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(formattedAddress)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // Coordinates
                    HStack {
                        Image(systemName: "globe")
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Coordinates")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(String(format: "%.6f, %.6f", location.latitude, location.longitude))
                                .font(.body)
                                .monospaced()
                        }
                        
                        Spacer()
                    }
                    
                    // Created Date
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Created")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(location.createdAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                                .font(.body)
                        }
                        
                        Spacer()
                    }
                    
                    Spacer()
                }
                .padding()
                .background(Color(.systemBackground))
            }
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
        .onAppear {
            setupLocationManager()
            loadFormattedAddress()
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